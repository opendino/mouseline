#!/usr/bin/env python3
"""Translations: numbered source tables → Support/<lang>.lproj/*.strings.

English text is the localization key in the code (see Sources/MouseLine/Localization.swift).
The translations live in scripts/strings/ as tab-separated tables, so each English sentence
is written once and every language refers to it by number:

    scripts/strings/keys.tsv     <id> TAB <English text>
    scripts/strings/<lang>.tsv   <id> TAB <translation>  or  <id>: <translation>
                                 (lang: tr, de, zh-Hans, …)

Ids are stable: new texts get the next free number, removed texts keep theirs (unused).
Ids starting with "plist." are Info.plist values and go to InfoPlist.strings, e.g.
plist.NSAppleEventsUsageDescription. Newlines are written as \\n.

    python3 -I scripts/strings.py sync     # add new English texts from the sources to keys.tsv
    python3 -I scripts/strings.py build    # write Support/*.lproj, report missing translations
    python3 -I scripts/strings.py missing  # list untranslated ids per language
"""
import importlib.util
import pathlib
import plistlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TABLES = ROOT / "scripts" / "strings"
SUPPORT = ROOT / "Support"
KEYS = TABLES / "keys.tsv"

# Languages offered by the app: table name → .lproj folder name.
LANGUAGES = {
    "tr": "tr", "es": "es", "hi": "hi", "pt-BR": "pt-BR", "de": "de", "ja": "ja", "fr": "fr",
    "it": "it", "ru": "ru", "uk": "uk", "pl": "pl", "nl": "nl", "id": "id", "vi": "vi",
    "th": "th", "ko": "ko", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant", "ar": "ar",
}
PLIST_KEYS = ["NSAppleEventsUsageDescription"]


def check_strings_module():
    spec = importlib.util.spec_from_file_location("check_strings", ROOT / "scripts" / "check-strings.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def unescape(s: str) -> str:
    return s.replace("\\n", "\n")


def escape_tsv(s: str) -> str:
    return s.replace("\n", "\\n")


def read_table(path: pathlib.Path) -> dict:
    table = {}
    if not path.exists():
        return table
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        # "<id> TAB <text>" or "<id>: <text>" (ids never contain a colon).
        if "\t" in line:
            key, text = line.split("\t", 1)
        elif ": " in line:
            key, text = line.split(": ", 1)
        else:
            sys.exit(f"{path.name}:{number}: expected <id> TAB <text> or <id>: <text>")
        table[key.strip()] = unescape(text)
    return table


def write_keys(keys: dict) -> None:
    def order(item):
        key = item[0]
        return (0, int(key)) if key.isdigit() else (1, key)
    lines = ["# id\tEnglish text — managed by scripts/strings.py sync; do not renumber."]
    lines += [f"{k}\t{escape_tsv(v)}" for k, v in sorted(keys.items(), key=order)]
    KEYS.write_text("\n".join(lines) + "\n", encoding="utf-8")


def sync() -> None:
    keys = read_table(KEYS)
    by_text = {v: k for k, v in keys.items() if k.isdigit()}
    used = check_strings_module().source_keys()
    next_id = max([int(k) for k in keys if k.isdigit()] + [0]) + 1
    added = []
    for text in sorted(used, key=str.lower):
        if text not in by_text:
            keys[str(next_id)] = text
            by_text[text] = str(next_id)
            added.append((next_id, text))
            next_id += 1
    info = plistlib.loads((SUPPORT / "Info.plist").read_bytes())
    for name in PLIST_KEYS:
        keys[f"plist.{name}"] = info[name]
    write_keys(keys)
    unused = sorted(int(k) for k, v in keys.items() if k.isdigit() and v not in used)
    print(f"keys.tsv: {len(keys)} entries, {len(added)} added, {len(unused)} no longer used")
    for number, text in added:
        print(f"  added {number}: {text!r}")
    if unused:
        print(f"  unused ids (kept, safe to ignore): {unused}")


def strings_line(key: str, value: str) -> str:
    def esc(s: str) -> str:
        return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{esc(key)}" = "{esc(value)}";'


def build() -> int:
    keys = read_table(KEYS)
    used = check_strings_module().source_keys()
    status = 0
    for lang, folder in LANGUAGES.items():
        if not (TABLES / f"{lang}.tsv").exists():
            print(f"{lang}: no table yet (skipped)")
            status = 1
            continue
        table = read_table(TABLES / f"{lang}.tsv")
        missing = [k for k, v in keys.items() if k.isdigit() and v in used and k not in table]
        missing += [k for k in keys if k.startswith("plist.") and k not in table]
        localizable = sorted(
            ((keys[k], v) for k, v in table.items() if k.isdigit() and k in keys and keys[k] in used),
            key=lambda kv: kv[0].lower(),
        )
        out = SUPPORT / f"{folder}.lproj"
        out.mkdir(parents=True, exist_ok=True)
        header = f"/* {lang}. Generated by scripts/strings.py from scripts/strings/{lang}.tsv — edit that file. */"
        (out / "Localizable.strings").write_text(
            "\n".join([header, ""] + [strings_line(k, v) for k, v in localizable]) + "\n", encoding="utf-8")
        plist_lines = [strings_line(k.split(".", 1)[1], v) for k, v in sorted(table.items()) if k.startswith("plist.")]
        (out / "InfoPlist.strings").write_text("\n".join([header, ""] + plist_lines) + "\n", encoding="utf-8")
        flag = "" if not missing else f", {len(missing)} missing"
        print(f"{lang}: {len(localizable)} strings{flag}")
        if missing:
            status = 1
    return status


def missing() -> None:
    keys = read_table(KEYS)
    used = check_strings_module().source_keys()
    for lang in LANGUAGES:
        table = read_table(TABLES / f"{lang}.tsv")
        ids = [k for k, v in keys.items() if (k.startswith("plist.") or v in used) and k not in table]
        if ids:
            print(f"{lang}: {' '.join(ids)}")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "build"
    if command == "sync":
        sync()
    elif command == "build":
        sys.exit(build())
    elif command == "missing":
        missing()
    else:
        sys.exit(__doc__)
