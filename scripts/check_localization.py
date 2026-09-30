#!/usr/bin/env python3
"""Checks the String Catalogs (all app languages) against the Swift sources (06 C07).

- Every localization key literal used in RENN/**/*.swift exists in Localizable.xcstrings.
- Every Look catalog manifest key (name, description, family) exists.
- Every catalog entry has a non-empty value in every language in LANGUAGES, with the same format
  arguments as the key (positional order may differ between languages).
- InfoPlist.xcstrings covers the usage descriptions declared in the xcconfig.

Runs with the Python standard library only, so it works in Linux CI without Xcode.
"""
import glob
import json
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
errors = []
# Must match AppLanguage.supportedLocalizations and knownRegions in scripts/generate_xcodeproj.py.
LANGUAGES = ("en", "tr", "es", "pt-BR", "de", "fr", "ja", "ko", "zh-Hans", "ru", "th", "vi", "id")

catalog = json.load(open(f"{ROOT}/RENN/Resources/Localizable.xcstrings", encoding="utf-8"))["strings"]
info_catalog = json.load(open(f"{ROOT}/RENN/Resources/InfoPlist.xcstrings", encoding="utf-8"))["strings"]

FORMAT = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f)")


def normalize(key):
    return FORMAT.sub("{}", key)


catalog_by_shape = {normalize(k): k for k in catalog}

# Dotted lowercase literals, optionally with SwiftUI interpolations.
# Dotted literals with optional interpolations (one level of nested parentheses allowed).
LITERAL = re.compile(r'"((?:[a-z][A-Za-z0-9]*)(?:\.[A-Za-z0-9]+)+)((?: \\\((?:[^()]|\([^()]*\))*\))*)"')
# Only these key namespaces are localization keys; other dotted literals (SF Symbols such as
# "heart.fill", defaults keys) are ignored.
NAMESPACES = {
    "common", "coach", "tab", "creation", "dual", "fixture", "flow", "home", "looks", "look", "onboarding",
    "projects", "project", "settings", "paywall", "export", "import", "preview", "camera", "indicators", "lookSelector",
}
IGNORED_FILES = {"RENNIcon.swift"}
IGNORED_PREFIXES = ("renn.",)

used = set()
for path in glob.glob(f"{ROOT}/RENN/**/*.swift", recursive=True):
    if path.split("/")[-1] in IGNORED_FILES:
        continue
    source = open(path, encoding="utf-8").read()
    # Accessibility identifiers are UI-test handles, not user-visible strings.
    source = re.sub(r'accessibilityIdentifier\("(?:[^"\\]|\\.)*"\)', "", source)
    for match in LITERAL.finditer(source):
        key = match.group(1)
        if key.startswith(IGNORED_PREFIXES) or key.split(".")[0] not in NAMESPACES:
            continue
        shape = key + " {}" * match.group(2).count("\\(")
        used.add(shape)
        if shape not in catalog_by_shape:
            errors.append(f"{path}: key '{key}' ({shape}) missing from Localizable.xcstrings")

for manifest in glob.glob(f"{ROOT}/RENN/Resources/Looks/*.json"):
    for look in json.load(open(manifest, encoding="utf-8"))["looks"]:
        for key in (look["nameKey"], look["descriptionKey"], "look.family." + look["family"]):
            used.add(key)
            if key not in catalog:
                errors.append(f"{manifest}: key '{key}' missing from Localizable.xcstrings")


def check_entries(name, entries):
    for key, entry in entries.items():
        localizations = entry.get("localizations", {})
        key_args = len(FORMAT.findall(key))
        english_args = None
        for language in LANGUAGES:
            value = localizations.get(language, {}).get("stringUnit", {}).get("value", "")
            if not value.strip():
                errors.append(f"{name}: '{key}' has no '{language}' value")
                continue
            args = sorted(FORMAT.findall(value))
            english_args = args if language == "en" else english_args
            if len(args) != key_args or (english_args is not None and args != english_args):
                errors.append(f"{name}: '{key}' format arguments differ in '{language}' (key {key_args}, {language} {args})")


check_entries("Localizable.xcstrings", catalog)
check_entries("InfoPlist.xcstrings", info_catalog)

xcconfig = open(f"{ROOT}/Config/RENN.shared.xcconfig", encoding="utf-8").read()
for key in re.findall(r"INFOPLIST_KEY_(NS\w+UsageDescription)", xcconfig):
    if key not in info_catalog:
        errors.append(f"InfoPlist.xcstrings: '{key}' missing")

unused = sorted(k for shape, k in catalog_by_shape.items() if shape not in used)
if unused:
    print("note: catalog keys not referenced by literal (may be dynamic):", ", ".join(unused))

if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"Localization OK: {len(used)} keys used, {len(catalog)} catalog entries, {len(LANGUAGES)} languages complete.")
