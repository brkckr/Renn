#!/usr/bin/env python3
"""Release-readiness audit (07 M09 production configuration audit).

Lists what still blocks a shippable build: development fixtures, missing owner assets and
provider configuration. It reads only the repository (never Config/Secrets.xcconfig values) and
prints a Markdown report. Exit code is 0 by default so CI shows the report without failing;
pass --strict to fail when any blocker remains (for a future release pipeline).
"""
import json
import pathlib
import plistlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES = ROOT / "RENN" / "Resources"


def check_catalog(blockers, ok):
    # The app loads LookCatalog.json; DevelopmentLookCatalog.json is a test fixture only.
    catalogs = [p for p in [RES / "Looks" / "LookCatalog.json"] if p.exists()]
    for path in catalogs:
        data = json.loads(path.read_text())
        looks = data.get("looks", [])
        dev = [l["id"] for l in looks if l.get("isDevelopmentFixture")]
        if data.get("isDevelopmentFixture") or dev:
            blockers.append(f"Look catalog `{path.name}` is a development fixture ({len(looks)} Look(s); DEV: {', '.join(dev) or 'catalog flag'}). Twelve reviewed Looks required (08, M08).")
        elif len(looks) != 12:
            blockers.append(f"Look catalog `{path.name}` has {len(looks)} Looks; the release catalog has twelve.")
        else:
            ok.append(f"Look catalog `{path.name}`: twelve non-fixture Looks.")
            missing = sorted(l["lut"] for l in looks if l.get("lut") and not (RES / "Looks" / f"{l['lut']}.cube").exists())
            if missing:
                blockers.append(f"{len(missing)} Look LUT file(s) missing from RENN/Resources/Looks ({', '.join(missing)}); run scripts/install_look_luts.py.")
            else:
                ok.append("All catalog Look LUT files are bundled.")
            if (RES / "Licenses" / "LookLicenses.txt").exists():
                ok.append("Look LUT license notice bundled.")
            else:
                blockers.append("Look LUT license notice (RENN/Resources/Licenses/LookLicenses.txt) missing; add the pack's copyright and license text.")
            blockers.append("Look parameters are starting values: visual review of the twelve Looks on real footage/device is still needed (M08).")
            overlay_dir = RES / "Overlays"
            wanted = sorted(json.loads((ROOT / "scripts" / "overlay_sources.json").read_text())["textures"])
            missing_overlays = [n for n in wanted if not (overlay_dir / f"{n}.jpg").exists()]
            if missing_overlays:
                blockers.append(f"{len(missing_overlays)} film overlay texture(s) not installed locally ({', '.join(missing_overlays)}); add them to RENN/Resources/Overlays (scripts/install_overlays.py).")
            else:
                ok.append("Film overlay textures installed locally.")
    if not catalogs:
        blockers.append("No Look catalog manifest found.")


def check_fonts(blockers, ok):
    fonts = [p for p in RES.rglob("*") if p.suffix.lower() in (".ttf", ".otf")]
    names = " ".join(p.name.lower() for p in fonts)
    for family in ("monoton", "pressstart2p", "roboto"):
        if family.replace("2p", "") in names.replace("-", "").replace("_", ""):
            ok.append(f"Font family `{family}` bundled.")
        else:
            blockers.append(f"Font `{family}` not bundled (system fallback in use); licensed files + notices needed (08).")


def check_app_icon(blockers, ok):
    contents = json.loads((RES / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json").read_text())
    if any("filename" in image for image in contents.get("images", [])):
        ok.append("App icon image present.")
    else:
        blockers.append("App icon has no 1024 px image (08).")


def check_providers(blockers, ok):
    if list((ROOT / "RENN").rglob("GoogleService-Info.plist")):
        ok.append("Firebase GoogleService-Info.plist bundled.")
    else:
        blockers.append("Firebase GoogleService-Info.plist missing (docs/OWNER_SETUP_M06.md).")
    # Owner values live in Config/Secrets.xcconfig (git-ignored), so they cannot be read here.
    blockers.append(
        "Verify owner values in Config/Secrets.xcconfig: RevenueCat public key (with App Store products "
        "and the `pro` entitlement), RENN_SUPPORT_URL, RENN_PRIVACY_URL, RENN_TERMS_URL (08 I04).")


def check_privacy_and_packages(blockers, ok):
    manifest = RES / "PrivacyInfo.xcprivacy"
    if manifest.exists():
        data = plistlib.loads(manifest.read_bytes())
        if data.get("NSPrivacyTracking") is False:
            ok.append("Privacy manifest present, tracking off.")
        else:
            blockers.append("Privacy manifest declares tracking.")
    else:
        blockers.append("Privacy manifest missing.")
    resolved = ROOT / "RENN.xcodeproj" / "project.xcworkspace" / "xcshareddata" / "swiftpm" / "Package.resolved"
    if resolved.exists():
        pins = json.loads(resolved.read_text()).get("pins", [])
        ok.append(f"Package.resolved committed ({len(pins)} pins).")
    else:
        blockers.append("Package.resolved not committed (06 C01).")
    blockers.append("App Store privacy details, Crashlytics dSYM upload phase and sandbox purchase evidence: owner/device tasks (docs/OWNER_SETUP_M06.md).")


def main():
    blockers, ok = [], []
    for check in (check_catalog, check_fonts, check_app_icon, check_providers, check_privacy_and_packages):
        check(blockers, ok)
    print("# RENN release audit\n")
    print(f"## Blockers ({len(blockers)})\n")
    for item in blockers:
        print(f"- {item}")
    print(f"\n## In place ({len(ok)})\n")
    for item in ok:
        print(f"- {item}")
    if "--strict" in sys.argv and blockers:
        sys.exit(1)


if __name__ == "__main__":
    main()
