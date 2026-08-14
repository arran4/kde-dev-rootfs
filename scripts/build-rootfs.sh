#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SUITE="${SUITE:-forky}"
ARCH="${ARCH:-amd64}"
MIRROR="${MIRROR:-https://deb.debian.org/debian}"
SNAPSHOT_TAG="${SNAPSHOT_TAG:-local}"
SOURCE_REVISION="${SOURCE_REVISION:-unknown}"
ROOTFS_DIR="${ROOTFS_DIR:-$REPO_ROOT/.work/rootfs}"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"

ARCHIVE_NAME="kde-dev-rootfs-${SUITE}-${ARCH}.tar.zst"
ARCHIVE="$DIST_DIR/$ARCHIVE_NAME"

if [[ ! -f packages.txt ]]; then
    echo "packages.txt not found" >&2
    exit 1
fi

rm -rf "$ROOTFS_DIR" "$DIST_DIR"
mkdir -p "$ROOTFS_DIR" "$DIST_DIR" "$REPO_ROOT/.work"

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    debootstrap \
    debian-archive-keyring \
    zstd

DEBOOTSTRAP_SCRIPT="/usr/share/debootstrap/scripts/$SUITE"
if [[ ! -e "$DEBOOTSTRAP_SCRIPT" ]]; then
    # Ubuntu-hosted runners can have a debootstrap package older than the
    # current Debian testing codename. The sid script is generic and accepts
    # an explicitly supplied suite such as forky.
    DEBOOTSTRAP_SCRIPT="/usr/share/debootstrap/scripts/sid"
fi

if [[ ! -e "$DEBOOTSTRAP_SCRIPT" ]]; then
    echo "No suitable debootstrap script found" >&2
    exit 1
fi

echo "Bootstrapping Debian $SUITE ($ARCH) from $MIRROR"
sudo debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    "$SUITE" \
    "$ROOTFS_DIR" \
    "$MIRROR" \
    "$DEBOOTSTRAP_SCRIPT"

# Package installation must never try to start services in the build chroot.
printf '#!/bin/sh\nexit 101\n' | sudo tee "$ROOTFS_DIR/usr/sbin/policy-rc.d" >/dev/null
sudo chmod 0755 "$ROOTFS_DIR/usr/sbin/policy-rc.d"

sudo chroot "$ROOTFS_DIR" \
    /usr/bin/env DEBIAN_FRONTEND=noninteractive \
    apt-get update

# Resolve the snapshot from the current state of Debian testing at build time.
sudo chroot "$ROOTFS_DIR" \
    /usr/bin/env DEBIAN_FRONTEND=noninteractive \
    apt-get -y full-upgrade

mapfile -t PACKAGES < <(
    sed \
        -e 's/[[:space:]]*#.*$//' \
        -e '/^[[:space:]]*$/d' \
        packages.txt
)

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    echo "packages.txt contains no packages" >&2
    exit 1
fi

sudo chroot "$ROOTFS_DIR" \
    /usr/bin/env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
    "${PACKAGES[@]}"

sudo rm -f "$ROOTFS_DIR/usr/sbin/policy-rc.d"

# Record the exact package set before removing APT metadata.
sudo chroot "$ROOTFS_DIR" \
    dpkg-query -W -f='${binary:Package}\t${Version}\n' \
    | LC_ALL=C sort \
    > "$DIST_DIR/package-manifest.txt"

bash "$SCRIPT_DIR/version-summary.sh" \
    "$ROOTFS_DIR" \
    "$DIST_DIR/package-manifest.txt" \
    > "$DIST_DIR/versions.md"

sudo mkdir -p "$ROOTFS_DIR/usr/share/kde-dev-rootfs"
sudo install -m 0644 \
    "$DIST_DIR/package-manifest.txt" \
    "$ROOTFS_DIR/usr/share/kde-dev-rootfs/package-manifest.txt"
sudo install -m 0644 \
    "$DIST_DIR/versions.md" \
    "$ROOTFS_DIR/usr/share/kde-dev-rootfs/versions.md"

{
    printf 'SNAPSHOT_TAG=%s\n' "$SNAPSHOT_TAG"
    printf 'SUITE=%s\n' "$SUITE"
    printf 'ARCH=%s\n' "$ARCH"
    printf 'MIRROR=%s\n' "$MIRROR"
    printf 'SOURCE_REVISION=%s\n' "$SOURCE_REVISION"
    printf 'BUILT_AT=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
} | sudo tee "$ROOTFS_DIR/usr/share/kde-dev-rootfs/release-info" >/dev/null

# Remove state that should not be shared between consumers.
sudo chroot "$ROOTFS_DIR" apt-get clean
sudo rm -rf "$ROOTFS_DIR/var/lib/apt/lists/"*
sudo rm -f "$ROOTFS_DIR/etc/machine-id"
sudo touch "$ROOTFS_DIR/etc/machine-id"
sudo rm -f "$ROOTFS_DIR/var/lib/dbus/machine-id"

while IFS= read -r -d '' log_file; do
    sudo truncate -s 0 "$log_file"
done < <(sudo find "$ROOTFS_DIR/var/log" -type f -print0)

bash "$SCRIPT_DIR/validate-rootfs.sh" "$ROOTFS_DIR"

echo "Creating $ARCHIVE"
sudo tar \
    --numeric-owner \
    --xattrs \
    --acls \
    -C "$ROOTFS_DIR" \
    -cf - . \
    | zstd -T0 -15 -o "$ARCHIVE"

(
    cd "$DIST_DIR"
    sha256sum "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
)

echo
echo "Build complete"
ls -lh "$ARCHIVE" "$ARCHIVE.sha256"
cat "$ARCHIVE.sha256"
