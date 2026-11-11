#!/usr/bin/env bash
set -euo pipefail

ROOTFS="${1:?rootfs path required}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [[ ! -d "$ROOTFS" ]]; then
    echo "Rootfs does not exist: $ROOTFS" >&2
    exit 1
fi

fail=0

check_absent() {
    local relative="$1"
    if [[ -e "$ROOTFS/$relative" || -L "$ROOTFS/$relative" ]]; then
        echo "ERROR: unexpected potentially-sensitive path: /$relative" >&2
        fail=1
    fi
}

for relative in \
    root/.ssh \
    root/.gnupg \
    root/.config/gh \
    root/.docker \
    root/.aws \
    root/.netrc \
    root/.npmrc \
    root/.git-credentials \
    home/runner \
    github/workspace; do
    check_absent "$relative"
done

if [[ ! -f "$ROOTFS/etc/machine-id" ]]; then
    echo "ERROR: /etc/machine-id is missing; expected an empty placeholder" >&2
    fail=1
elif [[ -s "$ROOTFS/etc/machine-id" ]]; then
    echo "ERROR: /etc/machine-id contains a persisted machine identity" >&2
    fail=1
fi

if [[ -e "$ROOTFS/var/lib/dbus/machine-id" ]]; then
    echo "ERROR: /var/lib/dbus/machine-id should not be persisted" >&2
    fail=1
fi

mapfile -t PACKAGES < <(
    sed \
        -e 's/[[:space:]]*#.*$//' \
        -e '/^[[:space:]]*$/d' \
        "$REPO_ROOT/packages.txt"
)

for package in "${PACKAGES[@]}"; do
    if ! sudo chroot "$ROOTFS" dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null \
        | grep -qx 'ii '; then
        echo "ERROR: required package is not installed: $package" >&2
        fail=1
    fi
done

# Search only locations that could plausibly have been populated by the build.
# Avoid scanning packaged documentation and test data, where token-shaped example
# strings can legitimately occur.
if sudo grep -RIlE \
    '(github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY-----)' \
    "$ROOTFS/root" \
    "$ROOTFS/home" \
    "$ROOTFS/usr/share/kde-dev-rootfs" \
    2>/dev/null; then
    echo "ERROR: possible credential material found in rootfs" >&2
    fail=1
fi

if (( fail != 0 )); then
    exit 1
fi

SMOKE_DIR="$ROOTFS/tmp/kde-dev-rootfs-smoke"
sudo rm -rf "$SMOKE_DIR"
sudo mkdir -p "$SMOKE_DIR"

sudo tee "$SMOKE_DIR/CMakeLists.txt" >/dev/null <<'EOF'
cmake_minimum_required(VERSION 3.20)
project(kde_dev_rootfs_smoke LANGUAGES CXX)

find_package(ECM REQUIRED NO_MODULE)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets Network Qml Sql DBus Svg Test)
find_package(KF6Archive REQUIRED)
find_package(KF6Config REQUIRED)
find_package(KF6ConfigWidgets REQUIRED)
find_package(KF6CoreAddons REQUIRED)
find_package(KF6DBusAddons REQUIRED)
find_package(KF6GlobalAccel REQUIRED)
find_package(KF6I18n REQUIRED)
find_package(KF6Notifications REQUIRED)
find_package(KF6StatusNotifierItem REQUIRED)
find_package(KF6Wallet REQUIRED)
find_package(KF6WidgetsAddons REQUIRED)
find_package(KF6XmlGui REQUIRED)
add_executable(kde_dev_rootfs_smoke main.cpp)
target_link_libraries(kde_dev_rootfs_smoke PRIVATE
    Qt6::Core
    Qt6::Widgets
    KF6::Archive
)
EOF

# Compile and link against real Qt and KDE libraries, then exercise them.
# CMake-only checks do not detect missing headers, linker problems, or
# dynamic-library/runtime incompatibilities.
sudo tee "$SMOKE_DIR/main.cpp" >/dev/null <<'EOF'
#include <QCoreApplication>
#include <QFileInfo>
#include <QIODevice>
#include <QWidget>
#include <KZip>

static_assert(sizeof(QWidget) > 0, "Qt Widgets headers must be usable");

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const QString path = QStringLiteral("/tmp/kde-dev-rootfs-smoke/smoke.zip");
    KZip archive(path);
    if (!archive.open(QIODevice::WriteOnly)) {
        return 1;
    }
    archive.close();
    return QFileInfo(path).size() > 0 ? 0 : 2;
}
EOF

sudo chroot "$ROOTFS" \
    cmake \
    -S /tmp/kde-dev-rootfs-smoke \
    -B /tmp/kde-dev-rootfs-smoke/build \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release

sudo chroot "$ROOTFS" \
    cmake --build /tmp/kde-dev-rootfs-smoke/build --parallel 2

sudo chroot "$ROOTFS" \
    /tmp/kde-dev-rootfs-smoke/build/kde_dev_rootfs_smoke

sudo rm -rf "$SMOKE_DIR"

echo "Rootfs validation passed"
