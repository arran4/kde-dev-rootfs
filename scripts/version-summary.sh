#!/usr/bin/env bash
set -euo pipefail

ROOTFS="${1:?rootfs path required}"
MANIFEST="${2:?package manifest required}"

if [[ ! -f "$ROOTFS/etc/os-release" ]]; then
    echo "Missing $ROOTFS/etc/os-release" >&2
    exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
    echo "Missing package manifest: $MANIFEST" >&2
    exit 1
fi

PRETTY_NAME="$(
    set +u
    . "$ROOTFS/etc/os-release"
    printf '%s' "${PRETTY_NAME:-Debian}"
)"

package_version() {
    local package="$1"

    awk -F '\t' -v package="$package" '
        $1 == package || index($1, package ":") == 1 {
            print $2
            found = 1
            exit
        }
        END {
            if (!found)
                print "not installed"
        }
    ' "$MANIFEST"
}

printf '## Key versions\n\n'
printf '| Component | Debian package | Version |\n'
printf '|---|---|---|\n'
printf '| Distribution | — | `%s` |\n' "$PRETTY_NAME"

while IFS='|' read -r description package; do
    printf '| %s | `%s` | `%s` |\n' \
        "$description" \
        "$package" \
        "$(package_version "$package")"
done <<'EOF'
Qt Base|qt6-base-dev
Qt Declarative/QML|qt6-declarative-dev
Qt Tools|qt6-tools-dev
Qt SVG|qt6-svg-dev
KDE Extra CMake Modules|extra-cmake-modules
KF6 CoreAddons|libkf6coreaddons-dev
KF6 Config|libkf6config-dev
KF6 ConfigWidgets|libkf6configwidgets-dev
KF6 DBusAddons|libkf6dbusaddons-dev
KF6 I18n|libkf6i18n-dev
KF6 Wallet|libkf6wallet-dev
KF6 XmlGui|libkf6xmlgui-dev
KF6 Notifications|libkf6notifications-dev
KF6 GlobalAccel|libkf6globalaccel-dev
KF6 StatusNotifierItem|libkf6statusnotifieritem-dev
KF6 Archive|libkf6archive-dev
CMake|cmake
Ninja|ninja-build
G++|g++
SQLCipher|libsqlcipher-dev
SQLite|libsqlite3-dev
EOF
