#!/usr/bin/env python3
"""Copies the film overlay textures from the owner's texture pack into the app bundle folder.

    python3 scripts/install_overlays.py /path/to/texture/pack

The pack's license allows the textures inside the app but forbids redistributing the files, so the
destination `RENN/Resources/Overlays/` is git-ignored: run this on each Mac that builds the app.
`scripts/overlay_sources.json` maps each bundle name (`renn_dust_1.jpg`, ...) to its file in the pack.
Without the textures the app still builds and renders every Look, just without overlays.
Works on macOS, Linux and Windows; needs only Python 3.
"""
import json
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "scripts" / "overlay_sources.json"
DEST = ROOT / "RENN" / "Resources" / "Overlays"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    pack = pathlib.Path(sys.argv[1]).expanduser()
    mapping = json.loads(SOURCES.read_text())["textures"]
    DEST.mkdir(parents=True, exist_ok=True)
    failures = []
    for name, file_name in sorted(mapping.items()):
        source = pack / file_name
        if not source.is_file():
            failures.append(f"{name}: not found at {source}")
            continue
        if source.read_bytes()[:3] != b"\xff\xd8\xff":
            failures.append(f"{name}: {file_name} is not a JPEG")
            continue
        shutil.copyfile(source, DEST / f"{name}.jpg")
        print(f"ok  {name}.jpg  <-  {file_name}")
    if failures:
        print("\nNot installed:", *failures, sep="\n  ")
        sys.exit(1)
    print(f"\nInstalled {len(mapping)} textures into {DEST.relative_to(ROOT)} (git-ignored).")


if __name__ == "__main__":
    main()
