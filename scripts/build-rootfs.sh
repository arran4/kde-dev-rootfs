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

# Modern systemd and D-Bus package maintainer scripts expect the usual
# pseudo-filesystems to exist even when installing into an offline chroot.
# Keep /run private to the rootfs, and unmount all of these before archiving.
CHROOT_MOUNTS_ACTIVE=0

mount_chroot_filesystems() {
    sudo mkdir -p \
        "$ROOTFS_DIR/proc" \
        "$ROOTFS_DIR/sys" \
        "$ROOTFS_DIR/dev" \
        "$ROOTFS_DIR/run"

    sudo mount -t proc proc "$ROOTFS_DIR/proc"
    sudo mount -t sysfs sysfs "$ROOTFS_DIR/sys"
    sudo mount --rbind /dev "$ROOTFS_DIR/dev"
    sudo mount --make-rslave "$ROOTFS_DIR/dev"
    sudo mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs "$ROOTFS_DIR/run"

    CHROOT_MOUNTS_ACTIVE=1
}

unmount_chroot_filesystems() {
    if [[ "$CHROOT_MOUNTS_ACTIVE" -eq 0 ]]; then
        return
    fi

    # Reverse dependency order: /run is independent, /dev may contain nested
    # mounts such as /dev/pts because it was recursively bind-mounted.
    sudo umount "$ROOTFS_DIR/run" 2>/dev/null || true
    sudo umount -R "$ROOTFS_DIR/dev" 2>/dev/null || true
    sudo umount "$ROOTFS_DIR/sys" 2>/dev/null || true
    sudo umount "$ROOTFS_DIR/proc" 2>/dev/null || true

    CHROOT_MOUNTS_ACTIVE=0
}

trap unmount_chroot_filesystems EXIT
mount_chroot_filesystems

# Package installation must never try to start services in the build chroot.
printf '#!/bin/sh\nexit 101\n' | sudo tee "$ROOTFS_DIR/usr/sbin/policy-rc.d" >/dev/null
sudo chmod 0755 "$ROOTFS_DIR/usr/sbin/policy-rc.d"

sudo chroot "$ROOTFS_DIR" \
    /usr/bin/env \
        DEBIAN_FRONTEND=noninteractive \
        SYSTEMD_OFFLINE=1 \
    apt-get update

# Resolve the snapshot from the current state of Debian testing at build time.
sudo chroot "$ROOTFS_DIR" \
    /usr/bin/env \
        DEBIAN_FRONTEND=noninteractive \
        SYSTEMD_OFFLINE=1 \
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
    /usr/bin/env \
        DEBIAN_FRONTEND=noninteractive \
        SYSTEMD_OFFLINE=1 \
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

# Never archive mounted host/pseudo filesystems.
unmount_chroot_filesystems
trap - EXIT

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
