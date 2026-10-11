#!/usr/bin/env python3
"""Tient le catalogue de traductions de Pingouin à jour, sans compilateur.

Dans le code, un texte à traduire s'écrit L("…") ou L(count: n, one: "…", other: "…").
Sa clé dans Resources/Localizable.xcstrings est le texte français, « %@ » à la place de chaque
valeur insérée et « % » doublé.

    python3 Scripts/traductions.py verifier   # ce qui manque, ce qui ne sert plus
    python3 Scripts/traductions.py ajouter    # ajoute au catalogue les clés absentes, à traduire

À lancer depuis la racine du dépôt.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = ["App", "DesignSystem", "Features", "Shared", "PingouinMobile", "Packages/PingouinKit/Sources"]
CATALOG = os.path.join(ROOT, "Resources", "Localizable.xcstrings")
LANGUAGES = ["en", "es", "de", "it"]
ESCAPES = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0", "r": "\r"}


def literals(source):
    """Chaînes littérales du fichier : (position, clé). Les chaînes nichées dans une insertion comptent."""
    found = []
    size = len(source)

    def parse(start):
        index = start + 1
        key = []
        while index < size:
            char = source[index]
            if char == "\\":
                following = source[index + 1]
                if following == "(":
                    cursor = index + 2
                    depth = 1
                    while cursor < size and depth > 0:
                        inner = source[cursor]
                        if inner == '"':
                            cursor = parse(cursor)
                            continue
                        depth += inner == "("
                        depth -= inner == ")"
                        cursor += 1
                    key.append("%@")
                    index = cursor
                    continue
                if following == "u":
                    match = re.match(r"u\{([0-9a-fA-F]+)\}", source[index + 1:])
                    key.append(chr(int(match.group(1), 16)))
                    index += 1 + len(match.group(0))
                    continue
                key.append(ESCAPES[following])
                index += 2
                continue
            if char == '"':
                index += 1
                break
            key.append("%%" if char == "%" else char)
            index += 1
        found.append((start, "".join(key)))
        return index

    index = 0
    while index < size:
        if source.startswith("//", index):
            end = source.find("\n", index)
            index = size if end < 0 else end
        elif source.startswith("/*", index):
            end = source.find("*/", index)
            index = size if end < 0 else end + 2
        elif source.startswith('"""', index):
            end = source.find('"""', index + 3)
            index = size if end < 0 else end + 3
        elif source[index] == '"':
            index = parse(index)
        else:
            index += 1
    return found


def keys_in_code():
    """Clés des textes passés à L(…), avec le premier fichier où chacune apparaît."""
    keys = {}
    for folder in SOURCES:
        for base, _, names in os.walk(os.path.join(ROOT, folder)):
            for name in sorted(names):
                if not name.endswith(".swift"):
                    continue
                path = os.path.join(base, name)
                with open(path, encoding="utf-8") as handle:
                    source = handle.read()
                for position, key in literals(source):
                    line_start = source.rfind("\n", 0, position) + 1
                    before = source[line_start:position]
                    direct = re.search(r"\bL\($", before)
                    counted = (
                        re.search(r"(^|[\s,(])(one|other):\s*$", before)
                        and "case" not in before
                        and "L(" in source[max(0, position - 400):position]
                    )
                    if direct or counted:
                        keys.setdefault(key, os.path.relpath(path, ROOT))
    return keys


def holes(text):
    return len(re.findall(r"%(\d+\$)?@", text))


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "verifier"
    with open(CATALOG, encoding="utf-8") as handle:
        catalog = json.load(handle)
    strings = catalog["strings"]
    code = keys_in_code()

    missing = [key for key in code if key not in strings]
    unused = [key for key in strings if key not in code]
    problems = 0

    if command == "ajouter":
        for key in missing:
            strings[key] = {"extractionState": "manual"}
        catalog["strings"] = dict(sorted(strings.items()))
        with open(CATALOG, "w", encoding="utf-8") as handle:
            json.dump(catalog, handle, ensure_ascii=False, indent=2, separators=(",", " : "))
        print(f"{len(missing)} clé(s) ajoutée(s) au catalogue, à traduire dans Xcode.")
        return 0

    for key in missing:
        print(f"ABSENTE du catalogue ({code[key]}) : {key!r}")
    for key in unused:
        print(f"INUTILISÉE dans le code : {key!r}")
    for key, entry in strings.items():
        localizations = entry.get("localizations", {})
        for language in LANGUAGES:
            value = localizations.get(language, {}).get("stringUnit", {}).get("value")
            if value is not None and holes(value) != holes(key):
                problems += 1
                print(f"INSERTIONS différentes en {language} : {key!r} → {value!r}")
    untranslated = [key for key, entry in strings.items() if not entry.get("localizations")]
    print(
        f"{len(code)} textes dans le code, {len(strings)} clés au catalogue, "
        f"{len(missing)} absente(s), {len(unused)} inutilisée(s), "
        f"{len(untranslated)} sans traduction (affichées en français), {problems} erreur(s) d'insertion."
    )
    return 1 if missing or problems else 0


if __name__ == "__main__":
    sys.exit(main())
