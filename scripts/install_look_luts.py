#!/usr/bin/env python3
"""Copies the twelve launch Look LUTs from the owner's LUT pack into the app bundle.

    python3 scripts/install_look_luts.py /path/to/lut/pack

The pack folder is the one with the `bw/`, `colorslide/`, `instant_pro/`... subfolders.
`scripts/look_lut_sources.json` maps each bundle name (`renn_<look>.cube`, as referenced by
`RENN/Resources/Looks/LookCatalog.json`) to its file in the pack. Each file is checked before it is
copied: 3D `.cube`, LUT_3D_SIZE 2...128, domain 0...1 (what the app's LUT stage supports).
Works on macOS, Linux and Windows; needs only Python 3.
"""
import json
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "scripts" / "look_lut_sources.json"
CATALOG = ROOT / "RENN" / "Resources" / "Looks" / "LookCatalog.json"
DEST = ROOT / "RENN" / "Resources" / "Looks"


def check_cube(path):
    size, domain_min, domain_max, rows = None, [0.0] * 3, [1.0] * 3, 0
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split()
        if not parts or parts[0].startswith("#"):
            continue
        key = parts[0].upper()
        if key == "LUT_1D_SIZE":
            return "1D LUT (only 3D is supported)"
        if key == "LUT_3D_SIZE":
            size = int(parts[1])
        elif key == "DOMAIN_MIN":
            domain_min = [float(v) for v in parts[1:4]]
        elif key == "DOMAIN_MAX":
            domain_max = [float(v) for v in parts[1:4]]
        elif key == "TITLE":
            continue
        else:
            try:
                [float(v) for v in parts[:3]]
                rows += 1
            except ValueError:
                pass
    if size is None:
        return "no LUT_3D_SIZE"
    if not 2 <= size <= 128:
        return f"unsupported size {size}"
    if domain_min != [0.0] * 3 or domain_max != [1.0] * 3:
        return "domain is not 0...1"
    if rows != size ** 3:
        return f"expected {size ** 3} rows, found {rows}"
    return None


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    pack = pathlib.Path(sys.argv[1]).expanduser()
    mapping = json.loads(SOURCES.read_text())["luts"]
    needed = {look["lut"] for look in json.loads(CATALOG.read_text())["looks"]}
    missing_map = needed - mapping.keys()
    if missing_map:
        sys.exit(f"No source mapping for: {', '.join(sorted(missing_map))}")
    failures = []
    for name in sorted(needed):
        source = pack / mapping[name]
        if not source.is_file():
            failures.append(f"{name}: not found at {source}")
            continue
        problem = check_cube(source)
        if problem:
            failures.append(f"{name}: {mapping[name]}: {problem}")
            continue
        shutil.copyfile(source, DEST / f"{name}.cube")
        print(f"ok  {name}.cube  <-  {mapping[name]}")
    if failures:
        print("\nNot installed:", *failures, sep="\n  ")
        sys.exit(1)
    print(f"\nInstalled {len(needed)} LUTs into {DEST.relative_to(ROOT)}.")


if __name__ == "__main__":
    main()
