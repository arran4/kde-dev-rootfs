# KDE development rootfs

A reproducible Debian testing (`forky`) development root filesystem containing a current Qt 6 and KDE Frameworks 6 toolchain.

The repository builds a fresh rootfs every week from the current Debian testing repositories. Each successful build is published in two forms:

- a compressed `tar.zst` rootfs attached to a GitHub Release;
- the same rootfs and metadata as a public OCI artifact in GitHub Container Registry (GHCR).

The release archive is suitable for CI systems, development agents, chroots and PRoot-based environments that need a recent KDE/Qt development stack without pulling a conventional container image.

## Published artifacts

Weekly releases use tags of the form:

```text
snapshot-YYYYMMDD
```

A repeated manual build on the same UTC date receives a run-number suffix.

Release assets include:

```text
kde-dev-rootfs-forky-amd64.tar.zst
kde-dev-rootfs-forky-amd64.tar.zst.sha256
package-manifest.txt
versions.md
package-changes.md
```

The GHCR package is published as:

```text
ghcr.io/arran4/kde-dev-rootfs:snapshot-YYYYMMDD
ghcr.io/arran4/kde-dev-rootfs:forky-latest
ghcr.io/arran4/kde-dev-rootfs:latest
```

GHCR stores this as an OCI artifact whose payload is the rootfs archive and associated metadata. It is not intended to be a Dockerfile-derived application image.

## Contents

The package selection is maintained in [`packages.txt`](packages.txt). It includes:

- GCC/G++, CMake and Ninja;
- Qt 6 base, tools, QML/declarative, SVG, SQL and test development support;
- KDE Frameworks 6 development packages commonly required by desktop applications;
- SQLite and SQLCipher development libraries;
- DBus, Xvfb and X authentication utilities for headless GUI tests.

All transitive Debian dependencies are included by APT at build time.

## Build locally

The build requires a Debian or Ubuntu-like host with `sudo` and `apt-get`.

```bash
./scripts/build-rootfs.sh
```

Output is written to `dist/`:

```text
dist/kde-dev-rootfs-forky-amd64.tar.zst
dist/kde-dev-rootfs-forky-amd64.tar.zst.sha256
dist/package-manifest.txt
dist/versions.md
```

The build script runs the validation suite before creating the archive.

Environment variables can override the defaults:

```bash
SUITE=forky \
ARCH=amd64 \
MIRROR=https://deb.debian.org/debian \
./scripts/build-rootfs.sh
```

## Using a release rootfs

Download and verify a release archive before unpacking it:

```bash
sha256sum -c kde-dev-rootfs-forky-amd64.tar.zst.sha256
mkdir rootfs
sudo tar --zstd -xf kde-dev-rootfs-forky-amd64.tar.zst -C rootfs
```

For a privileged chroot, bind the directories needed by the workload and enter the rootfs normally. For unprivileged environments, the same archive can be used with PRoot or another userspace rootfs runner.

## Using the GHCR artifact

With ORAS:

```bash
oras pull ghcr.io/arran4/kde-dev-rootfs:forky-latest
```

The immutable `snapshot-YYYYMMDD` tags are preferred when reproducibility matters. `forky-latest` and `latest` move after each successful weekly publication.

## Release metadata

Every rootfs contains:

```text
/usr/share/kde-dev-rootfs/package-manifest.txt
/usr/share/kde-dev-rootfs/versions.md
/usr/share/kde-dev-rootfs/release-info
```

`package-manifest.txt` records every installed Debian package and exact version. The GitHub Release also contains a human-readable summary of important Qt, KDE Frameworks, compiler and build-tool versions and a package-level diff from the previous release.

## Security model

The output is designed to be public. The build starts with an empty directory populated by `debootstrap`; it does not archive the GitHub Actions runner or a developer home directory.

Before publication, [`scripts/validate-rootfs.sh`](scripts/validate-rootfs.sh) rejects common credential locations, verifies required packages, checks that machine identity is not persisted, and configures a small CMake project against the installed Qt/KF6 development files.

The build intentionally does not copy repository credentials, user configuration or CI environment files into the rootfs.

## Updating dependencies

Edit `packages.txt`. The next manual or scheduled workflow run resolves the current versions from Debian testing and records them in the manifest and release summary.

The scheduled workflow runs weekly and can also be started manually from the Actions tab.

## Redistribution

The rootfs is an aggregation of Debian packages. Package-specific copyright and licence information is retained under `/usr/share/doc/*/copyright`. Consumers and redistributors remain responsible for complying with the licences of the included packages.
