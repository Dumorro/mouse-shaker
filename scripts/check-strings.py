#!/usr/bin/env python3
"""Fails (exit 1) when a user-facing literal in Sources/MouseShaker has no translation in one of
the Resources/*.lproj tables, or when a table has a key the code no longer uses.

English is the development language: the keys are the English text, so en.lproj is skipped.

Interpolations are normalised: every `\\(...)` in code and every %@ / %lld in a strings file
compare as one placeholder, so this checks coverage, not format-specifier types.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources" / "MouseShaker"
RESOURCES = ROOT / "Resources"

LITERAL = r'"((?:[^"\\]|\\.)*)"'
CALLS = re.compile(
    r'\b(?:Text|Toggle|Button|Picker|Section|Label|LabeledContent|Menu|DatePicker|Caption|DurationPicker)'
    r'\(\s*(?:title:\s*)?' + LITERAL
)
LOCALIZED = re.compile(r'String\(localized:\s*' + LITERAL)
# `case .x: "..."` inside computed properties returning LocalizedStringKey (Labels.swift).
CASE_VALUE = re.compile(r'case [^:]+:\s*' + LITERAL + r'\s*$', re.M)
PLACEHOLDER = "\u0000"


def interpolation_to_placeholder(s: str) -> str:
    out, i = [], 0
    while i < len(s):
        if s.startswith("\\(", i):
            depth, i = 1, i + 2
            while i < len(s) and depth:
                depth += {"(": 1, ")": -1}.get(s[i], 0)
                i += 1
            out.append(PLACEHOLDER)
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def code_keys() -> set[str]:
    keys = set()
    for path in SOURCES.rglob("*.swift"):
        text = path.read_text()
        for rx in (CALLS, LOCALIZED):
            keys.update(m.group(1) for m in rx.finditer(text))
        if path.name == "Labels.swift":
            keys.update(m.group(1) for m in CASE_VALUE.finditer(text))
    # Symbol names returned from IconStyle.symbol(for:) are not UI text.
    keys = {k for k in keys if not re.fullmatch(r"[a-z0-9.]+", k)}
    return {interpolation_to_placeholder(k) for k in keys if k}


def table_keys(path: pathlib.Path) -> set[str]:
    raw = re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', path.read_text(), re.M)
    return {re.sub(r"%(?:@|lld|d)", PLACEHOLDER, k) for k in raw}


def show(keys):
    return "\n  ".join(sorted(k.replace(PLACEHOLDER, "%@") for k in keys))


code = code_keys()
failed = False
tables = sorted(p for p in RESOURCES.glob("*.lproj/Localizable.strings") if p.parent.name != "en.lproj")
if not tables:
    print("No translation tables found")
    sys.exit(1)
for table in tables:
    language = table.parent.stem
    translated = table_keys(table)
    missing, unused = code - translated, translated - code
    if missing:
        print(f"[{language}] missing ({len(missing)}):\n  {show(missing)}")
    if unused:
        print(f"[{language}] unused ({len(unused)}):\n  {show(unused)}")
    print(f"[{language}] code keys: {len(code)}, translated: {len(translated)}")
    failed |= bool(missing or unused)
sys.exit(1 if failed else 0)
