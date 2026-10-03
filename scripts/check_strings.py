#!/usr/bin/env python3
"""Checks the app's translations.

- Finds user-facing string literals in Sources/ (Text("…"), Button("…"), String(localized: "…"), …)
  and converts interpolations to format specifiers the way SwiftUI does.
- Fails if a key is missing from a Localizable.strings file, or if the files disagree.

Usage: scripts/check_strings.py [--print]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Sources/LibertyLoader", ROOT / "Sources/LibertyCore"]
LANGS = ["en", "de"]

# Calls whose first string literal argument is a localized key.
POSITIONAL = r"(?:Text|Button|Label|Toggle|Picker|TextField|SecureField|Menu|LocalizedStringKey|HDSectionHeader|HDTag|section|\.help|\.navigationTitle|\.alert|\.confirmationDialog)"
# Labeled arguments that take a LocalizedStringKey.
LABELED = r"(?:title|subtitle|label|text|detail|localized|name|summary)"
LITERAL = r'"((?:[^"\\\n]|\\.)*)"'

INT_HINTS = ("count", "installed", "updates", "modID", "code", "Int(")


def interpolations(literal: str) -> list[str]:
    """Finds \\( ... ) groups, allowing nested parentheses."""
    out, i = [], 0
    while (i := literal.find("\\(", i)) != -1:
        depth, j = 1, i + 2
        while j < len(literal) and depth:
            depth += {"(": 1, ")": -1}.get(literal[j], 0)
            j += 1
        out.append((i, j, literal[i + 2:j - 1]))
        i = j
    return out


def literal_to_key(literal: str) -> str:
    parts, last = [], 0
    for start, end, expr in interpolations(literal):
        parts.append(literal[last:start])
        parts.append("%lld" if any(h in expr for h in INT_HINTS) else "%@")
        last = end
    parts.append(literal[last:])
    return "".join(parts).replace('\\"', '"')


def source_keys() -> set[str]:
    keys = set()
    patterns = [
        re.compile(POSITIONAL + r"\(\s*" + LITERAL),
        re.compile(r"\b" + LABELED + r":\s*" + LITERAL),
        # `? "a" : "b"` passed to a LocalizedStringKey parameter (labeled call on the line above).
        re.compile(r"^\s*[?:]\s*" + LITERAL, re.M),
        # `return "…"` inside `var title: LocalizedStringKey` switches.
        re.compile(r"case \.\w+: return " + LITERAL),
    ]
    for folder in SOURCES:
        for file in folder.rglob("*.swift"):
            text = file.read_text()
            for pattern in patterns:
                for match in pattern.finditer(text):
                    literal = match.group(1)
                    # Skip URLs, paths and SF Symbol names ("play.fill", "speedometer").
                    if not literal or literal.startswith(("http", "/")) or re.fullmatch(r"[a-z0-9.]+", literal) or ("." in literal and " " not in literal):
                        continue
                    keys.add(literal_to_key(literal))
    return keys


def strings_file(lang: str) -> dict[str, str]:
    path = ROOT / f"Localization/{lang}.lproj/Localizable.strings"
    text = path.read_text(encoding="utf-8")
    pairs = re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$', text, re.M)
    entries = {k.replace('\\"', '"'): v for k, v in pairs}
    body_lines = [l for l in text.splitlines() if l.strip() and not l.strip().startswith(("/*", "*", "//"))]
    if len(body_lines) != len(pairs):
        sys.exit(f"{path}: {len(body_lines) - len(pairs)} malformed line(s)")
    return entries


def main() -> None:
    keys = source_keys()
    if "--print" in sys.argv:
        for key in sorted(keys):
            print(key)
        return
    files = {lang: strings_file(lang) for lang in LANGS}
    ok = True
    for lang, entries in files.items():
        missing = sorted(keys - entries.keys())
        if missing:
            ok = False
            print(f"{lang}: {len(missing)} missing key(s):")
            for key in missing:
                print(f"  {key}")
    if files["en"].keys() != files["de"].keys():
        ok = False
        print("en and de have different keys:", sorted(files["en"].keys() ^ files["de"].keys()))
    for lang, entries in files.items():
        for key, value in entries.items():
            if sorted(re.findall(r"%(?:lld|@)", key)) != sorted(re.findall(r"%(?:lld|@)", value)):
                ok = False
                print(f"{lang}: format specifiers differ for {key!r}")
    print("Translations OK" if ok else "Translations incomplete")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
