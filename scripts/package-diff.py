#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys


def read_manifest(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}

    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        package, version = line.split("\t", 1)
        result[package] = version
    return result


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} PREVIOUS_MANIFEST CURRENT_MANIFEST", file=sys.stderr)
        return 2

    old = read_manifest(Path(sys.argv[1]))
    new = read_manifest(Path(sys.argv[2]))

    if not old:
        print("First published snapshot; there is no previous package manifest.")
        return 0

    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    changed = sorted(
        package
        for package in set(old) & set(new)
        if old[package] != new[package]
    )

    print(
        f"**{len(changed)} upgraded/changed**, "
        f"**{len(added)} added**, "
        f"**{len(removed)} removed**."
    )

    rows: list[tuple[str, str, str]] = []
    rows.extend((package, old[package], new[package]) for package in changed)
    rows.extend((package, "—", new[package]) for package in added)
    rows.extend((package, old[package], "—") for package in removed)

    if not rows:
        print("\nNo package changes from the previous snapshot.")
        return 0

    print("\n| Package | Previous | Current |")
    print("|---|---|---|")

    limit = 100
    for package, previous, current in rows[:limit]:
        print(f"| `{package}` | `{previous}` | `{current}` |")

    if len(rows) > limit:
        print(
            f"\n_Showing the first {limit} of {len(rows)} package changes. "
            "See `package-manifest.txt` for the complete snapshot._"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
