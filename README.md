# KDE development rootfs

A reproducible Debian testing (`forky`) development root filesystem containing a current Qt 6 and KDE Frameworks 6 toolchain.

The repository continuously validates and periodically publishes a fresh rootfs from the current Debian testing repositories. Published builds are distributed in two forms:

- a compressed `tar.zst` rootfs attached to a GitHub Release;
- the same rootfs and metadata as a public OCI artifact in GitHub Container Registry (GHCR).

The release archive is suitable for CI systems, development agents, chroots and PRoot-based environments that need a recent KDE/Qt development stack without pulling a conventional container image.

## Workflow behavior

The main workflow runs in four situations:

| Trigger | Full rootfs build | GitHub Release / GHCR publication | Version bump |
|---|---:|---:|---|
| Pull request opened, reopened, or updated against `main` | Yes | No | None |
| Push or merge to `main` | Yes | Yes | Patch |
| Weekly schedule | Yes | Yes | Patch |
| Manual dispatch from `main` | Yes | Yes | Patch, minor, or major |
| Manual dispatch from another branch | Yes | No | None |

A push to a branch with an open pull request triggers the `pull_request` `synchronize` event, so the proposed rootfs is rebuilt and validated for each PR update without publishing anything.

Publication is always gated on the checked-out ref being `refs/heads/main`. Pull-request builds and manual runs from other branches therefore never authenticate to GHCR, create tags, or create GitHub Releases.

## Versioning

Published releases use semantic tags:

```text
vMAJOR.MINOR.PATCH
```

Version calculation is performed by [`arran4/git-tag-inc-action`](https://github.com/arran4/git-tag-inc-action).

Normal pushes and merges to `main`, plus scheduled builds, increment the patch version. Manual dispatches from `main` expose a choice of:

```text
patch
minor
major
```

The prospective tag is created locally before the rootfs build so it can be embedded in the build metadata. It is not published merely because version calculation succeeded. GitHub creates the remote tag together with the Release only after the rootfs has built and passed validation.

## Published artifacts

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
ghcr.io/arran4/kde-dev-rootfs:vMAJOR.MINOR.PATCH
ghcr.io/arran4/kde-dev-rootfs:forky-latest
ghcr.io/arran4/kde-dev-rootfs:latest
```

The semantic version tag is immutable. `forky-latest` and `latest` are moved only after the corresponding GitHub Release has been created successfully.

GHCR stores this as an OCI artifact whose payload is the rootfs archive and associated metadata. It is not intended to be a Dockerfile-derived application image.

## Contents

The package selection is maintained in [`packages.txt`](packages.txt). It includes:

- GCC/G++, CMake and Ninja;
- Qt 6 base, tools, QML/declarative, SVG, SQL and test development support;
- KDE Frameworks 6 development packages commonly required by desktop applications;
- SQLite and SQLCipher development libraries;
- DBus, Xvfb and X authentication utilities for headless GUI tests.

All transitive Debian dependencies are included by APT at build time.

## Repository checks

Run the fast repository checks with:

```bash
make check
```

This validates shell syntax, Python syntax and the package list without building a rootfs.

## Build locally

The full build requires a Debian or Ubuntu-like host with `sudo` and `apt-get`.

```bash
make build
```

Equivalently:

```bash
bash scripts/build-rootfs.sh
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
bash scripts/build-rootfs.sh
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

For reproducible use, prefer an immutable semantic tag such as:

```bash
oras pull ghcr.io/arran4/kde-dev-rootfs:v1.2.3
```

## Release metadata

Every rootfs contains:

```text
/usr/share/kde-dev-rootfs/package-manifest.txt
/usr/share/kde-dev-rootfs/versions.md
/usr/share/kde-dev-rootfs/release-info
```

`package-manifest.txt` records every installed Debian package and exact version. A published GitHub Release also contains a human-readable summary of important Qt, KDE Frameworks, compiler and build-tool versions and a package-level diff from the previous release.

Pull-request and other build-only runs place the same version and package-diff information in the GitHub Actions job summary, but do not publish the resulting rootfs.

## Security model

The output is designed to be public. The build starts with an empty directory populated by `debootstrap`; it does not archive the GitHub Actions runner or a developer home directory.

Before publication, [`scripts/validate-rootfs.sh`](scripts/validate-rootfs.sh) rejects common credential locations, verifies required packages, checks that machine identity is not persisted, and configures a small CMake project against the installed Qt/KF6 development files.

The build intentionally does not copy repository credentials, user configuration or CI environment files into the rootfs.

## Updating dependencies

Edit `packages.txt`. Pull requests perform a complete build and validation without publishing. Once merged to `main`, the merge-triggered build creates the next patch release if validation succeeds.

The workflow also rebuilds and publishes weekly so dependency updates from Debian testing are captured even when the repository itself has not changed.

## Redistribution

The rootfs is an aggregation of Debian packages. Package-specific copyright and licence information is retained under `/usr/share/doc/*/copyright`. Consumers and redistributors remain responsible for complying with the licences of the included packages.
