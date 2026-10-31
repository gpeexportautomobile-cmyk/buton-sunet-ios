#!/usr/bin/env python3
"""Attach verse ids to characters using the manual alias list."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from textutil import attach_mentions, flatten_bible


def extract(bible: dict, alias_doc: dict) -> dict:
    characters = [dict(character) for character in alias_doc["characters"]]
    verses = flatten_bible(bible)
    by_id = attach_mentions(verses, characters)
    for character in characters:
        character["verseIds"] = by_id.get(character["id"], [])
    characters.sort(key=lambda character: (character.get("order", 99), character["name"]))
    return {"characters": characters, "verses": verses}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verses", required=True)
    parser.add_argument("--aliases", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    bible = json.loads(Path(args.verses).read_text(encoding="utf-8"))
    aliases = json.loads(Path(args.aliases).read_text(encoding="utf-8"))
    doc = extract(bible, aliases)
    public = {"characters": doc["characters"]}
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(public, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for character in public["characters"]:
        print(f"{character['name']}: {len(character['verseIds'])} versete")


if __name__ == "__main__":
    main()
