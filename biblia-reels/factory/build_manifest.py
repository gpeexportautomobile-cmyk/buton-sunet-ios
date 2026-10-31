#!/usr/bin/env python3
"""Assemble manifest.json from whatever the factory has finished.

A verse is published only when its image, audio, and word timings all exist.
Characters are always published, so bios and new people show up before every
portrait is ready. Re-running the script is safe.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from textutil import flatten_bible


def load_json(path: Path, fallback):
    if not path.exists():
        return fallback
    return json.loads(path.read_text(encoding="utf-8"))


def build(verses_path: Path, aliases_path: Path, output: Path) -> dict:
    from extract_characters import extract

    bible = json.loads(verses_path.read_text(encoding="utf-8"))
    alias_doc = json.loads(aliases_path.read_text(encoding="utf-8"))
    extracted = extract(bible, alias_doc)
    mentions = {verse["id"]: verse["characters"] for verse in extracted["verses"]}
    bios = load_json(output / "state" / "bios.json", {})
    flat = flatten_bible(bible)
    for verse in flat:
        verse["characters"] = mentions.get(verse["id"], [])
    published = []
    for verse in flat:
        image = output / "images" / f"{verse['id']}.webp"
        audio = output / "audio" / f"{verse['id']}.m4a"
        timing_path = output / "state" / "timings" / f"{verse['id']}.json"
        if not (image.exists() and audio.exists() and timing_path.exists()):
            continue
        timing = json.loads(timing_path.read_text(encoding="utf-8"))
        published.append(
            {
                "id": verse["id"],
                "bookId": verse["bookId"],
                "book": verse["book"],
                "bookOrder": verse["bookOrder"],
                "chapter": verse["chapter"],
                "verse": verse["verse"],
                "text": verse["text"],
                "image": f"images/{verse['id']}.webp",
                "audio": f"audio/{verse['id']}.m4a",
                "words": timing.get("words") or [],
                "characters": verse.get("characters") or timing.get("characters") or [],
            }
        )

    # Mentions for published verses come from the timing sidecar when the
    # flattener did not run attach. Prefer characters stored next to timings.
    characters = []
    for character in alias_doc["characters"]:
        cid = character["id"]
        verse_ids = [
            verse["id"]
            for verse in published
            if cid in (verse.get("characters") or [])
        ]
        avatar = output / "avatars" / f"{cid}.webp"
        characters.append(
            {
                "id": cid,
                "name": character["name"],
                "order": character.get("order", 99),
                "color": character.get("color", "#E6C36A"),
                "aliases": character.get("aliases") or [],
                "related": character.get("related") or [],
                "bio": bios.get(cid) or character.get("bio") or "",
                "avatar": f"avatars/{cid}.webp" if avatar.exists() else "",
                "verseIds": verse_ids,
            }
        )

    books = []
    seen = set()
    for book in bible.get("books") or []:
        if book["id"] in seen:
            continue
        seen.add(book["id"])
        books.append({"id": book["id"], "name": book["name"], "order": book.get("order", 99)})

    updated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "version": 1,
        "updated": updated,
        "generator": "biblia-reels-factory",
        "books": books,
        "verses": published,
        "characters": characters,
    }


def write_manifest(verses_path: Path, aliases_path: Path, output: Path) -> dict:
    manifest = build(verses_path, aliases_path, output)
    output.mkdir(parents=True, exist_ok=True)
    path = output / "manifest.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Manifest: {len(manifest['verses'])} versete cu media, {len(manifest['characters'])} personaje → {path}")
    return manifest


def main_with(verses_path: Path, aliases_path: Path, output: Path) -> dict:
    return write_manifest(verses_path, aliases_path, output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verses", required=True)
    parser.add_argument("--aliases", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    write_manifest(Path(args.verses), Path(args.aliases), Path(args.out))


if __name__ == "__main__":
    main()
