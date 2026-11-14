#!/usr/bin/env python3
"""Checks that every user-facing string has a translation.

Extracts localization keys from the Swift sources and compares them with each
Support/<lang>.lproj/Localizable.strings (English is the key, so en.lproj may be empty).

    python3 -I scripts/check-strings.py            # check all languages, exit 1 on missing keys
    python3 -I scripts/check-strings.py --list     # print every key found in the sources

Keys come from:
  - string literals passed to SwiftUI views and modifiers (Text, Button, Toggle, Label,
    Section, TextField, Picker, Menu, ColorPicker, .help) and to L() / LF();
  - LocalizedStringKey parameters of our own views (title:, text:);
  - titles in MouseLineCore that the app shows through L(): ActionKind / TriggerButton /
    RequiredModifier titles, ActionCategory / GestureGroup raw values, built-in gesture ids.
String interpolations "\\(...)" inside SwiftUI literals become "%@" (all interpolated
values in this app's literals are strings).
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "Sources" / "MouseLine"
CORE = ROOT / "Sources" / "MouseLineCore"
SUPPORT = ROOT / "Support"

# A Swift string literal on one line (no multi-line literals are used for UI text).
LIT = r'"((?:[^"\\]|\\.)*)"'
CALLS = r'(?:Text|Button|Toggle|Label|LabeledContent|Section|TextField|Picker|Menu|ColorPicker|\.help|L|LF)'
PATTERNS = [
    re.compile(CALLS + r'\(\s*' + LIT),
    re.compile(r'\b(?:title|text):\s*' + LIT),
]
# Literals that are not UI text.
IGNORE_PREFIXES = ("x-apple.", "/", "app.mouseline", "--", "https://example.com")


def swift_key(literal: str) -> str:
    """Turns a Swift literal body into the localization key SwiftUI / L() would use."""
    key = re.sub(r'\\\((?:[^()]|\([^()]*\))*\)', '%@', literal)
    return (key.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\'))


def source_keys() -> set:
    keys = set()
    for path in APP.rglob("*.swift"):
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("//") or "verbatim:" in line or "Logger(" in line or "log." in line:
                continue
            for pattern in PATTERNS:
                for match in pattern.finditer(line):
                    key = swift_key(match.group(1))
                    if key and not key.startswith(IGNORE_PREFIXES):
                        keys.add(key)

    config = (CORE / "Config.swift").read_text(encoding="utf-8")
    keys.update(re.findall(r'case \.\w+: return "([^"]+)"', config))  # titles
    keys.update(re.findall(r'case \w+ = "([^"]+)"', config))           # ActionCategory raw values

    templates = (CORE / "GestureTemplate.swift").read_text(encoding="utf-8")
    keys.update(re.findall(r'case \w+ = "([^"]+)"', templates))        # GestureGroup raw values
    keys.update(re.findall(r'add\("([^"]+)"', templates))              # gesture ids
    keys.update(re.findall(r'reverse: "([^"]+)"', templates))          # reversed gesture ids
    return keys


def read_strings(path: pathlib.Path) -> dict:
    text = path.read_text(encoding="utf-8")
    pairs = re.findall(r'^\s*' + LIT + r'\s*=\s*' + LIT + r'\s*;', text, flags=re.M)

    def unescape(s: str) -> str:
        return s.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\')

    return {unescape(k): unescape(v) for k, v in pairs}


def placeholders(s: str) -> list:
    return re.findall(r'%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:ll|l)?[@dfsu]', s)


def main() -> int:
    keys = source_keys()
    if "--list" in sys.argv:
        for key in sorted(keys):
            print(repr(key))
        return 0

    status = 0
    for table in sorted(SUPPORT.glob("*.lproj/Localizable.strings")):
        lang = table.parent.stem
        entries = read_strings(table)
        if lang == "en":
            continue
        missing = sorted(keys - entries.keys())
        unused = sorted(entries.keys() - keys)
        bad = sorted(k for k, v in entries.items() if k in keys and sorted(placeholders(k)) != sorted(placeholders(v)))
        print(f"{lang}: {len(keys)} keys, {len(missing)} missing, {len(unused)} unused, {len(bad)} placeholder mismatches")
        for key in missing:
            print(f"  missing: {key!r}")
        for key in unused:
            print(f"  unused:  {key!r}")
        for key in bad:
            print(f"  placeholders differ: {key!r} -> {entries[key]!r}")
        if missing or bad:
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
