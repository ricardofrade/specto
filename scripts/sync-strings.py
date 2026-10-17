#!/usr/bin/env python3
"""Keeps App/Shared/Localizable.xcstrings in step with the code.

Both apps (and every package) are built with SWIFT_EMIT_LOC_STRINGS=YES; the compiler writes the
localizable strings of each source file as .stringsdata, and this merges them into the one catalog
both apps ship. Packages need no bundle arguments: SwiftUI's Text and String(localized:) look up
the main bundle by default, which is where the catalog lives.

  scripts/sync-strings.py            build, then merge
  scripts/sync-strings.py --no-build merge what the last build emitted

New keys are added; keys no longer in the code are marked stale; translations are kept.
Translations in scripts/translations/<lang>.json are applied as "needs_review" unless a reviewed
translation already exists.
"""
import json, os, subprocess, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "App/Shared/Localizable.xcstrings")
BUILDS = [
    ("App/iOS", "Specto.xcodeproj", "Specto", "generic/platform=iOS Simulator", "build/dd-l10n"),
    ("App/tvOS", "SpectoTV.xcodeproj", "SpectoTV", "generic/platform=tvOS Simulator", "build/dd-l10n-tv"),
]


def build():
    for folder, project, scheme, destination, derived in BUILDS:
        subprocess.run(["xcodegen", "generate", "--spec", "project.yml", "--quiet"], cwd=os.path.join(ROOT, folder), check=True)
        result = subprocess.run(["xcodebuild", "build", "-project", project, "-scheme", scheme, "-destination", destination,
                                 "-derivedDataPath", os.path.join(ROOT, derived), "SWIFT_EMIT_LOC_STRINGS=YES"],
                                cwd=os.path.join(ROOT, folder), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode != 0:
            sys.exit(f"Build failed: {scheme}")


def extracted():
    keys = {}
    for _, _, _, _, derived in BUILDS:
        for path in glob.glob(os.path.join(ROOT, derived, "**/*.stringsdata"), recursive=True):
            data = json.load(open(path))
            source = data.get("source", "")
            # Our code only: not dependencies checked out under build/.
            if not source.startswith(ROOT) or "/build/" in source[len(ROOT):]:
                continue
            for entry in data.get("tables", {}).get("Localizable", []):
                key = entry["key"]
                comment = entry.get("comment") or ""
                if key not in keys or (comment and not keys[key]):
                    keys[key] = comment
    return keys


def merge(keys):
    catalog = json.load(open(CATALOG)) if os.path.exists(CATALOG) else {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
    strings = catalog["strings"]
    for key, comment in keys.items():
        entry = strings.setdefault(key, {})
        entry.pop("extractionState", None)
        if comment:
            entry["comment"] = comment
    for key, entry in strings.items():
        if key not in keys:
            entry["extractionState"] = "stale"
    for path in glob.glob(os.path.join(ROOT, "scripts/translations/*.json")):
        language = os.path.splitext(os.path.basename(path))[0]
        for key, value in json.load(open(path)).items():
            if key not in strings:
                continue
            localizations = strings[key].setdefault("localizations", {})
            current = localizations.get(language, {}).get("stringUnit", {})
            if current.get("state") == "translated" or "translated" in json.dumps(localizations.get(language, {}).get("variations", {})):
                continue  # Reviewed by a person: keep it.
            if isinstance(value, dict):  # Plural forms: {"one": ..., "other": ...}
                localizations[language] = {"variations": {"plural": {
                    form: {"stringUnit": {"state": "needs_review", "value": text}} for form, text in value.items()}}}
            else:
                localizations[language] = {"stringUnit": {"state": "needs_review", "value": value}}
    catalog["strings"] = dict(sorted(strings.items(), key=lambda item: item[0].lower()))
    with open(CATALOG, "w") as file:
        json.dump(catalog, file, ensure_ascii=False, indent=2, sort_keys=True)
        file.write("\n")
    stale = sum(1 for entry in strings.values() if entry.get("extractionState") == "stale")
    print(f"{len(keys)} strings in use, {stale} stale, catalog: {os.path.relpath(CATALOG, ROOT)}")


if __name__ == "__main__":
    if "--no-build" not in sys.argv:
        build()
    merge(extracted())
