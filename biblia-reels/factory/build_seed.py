#!/usr/bin/env python3
"""Build the bundled verse JSON from a Cornilescu 1924 dump.

The dump is the public file ``ron-cornilescu-1924.json`` from
https://github.com/m0ty/bible-io-json (old orthography). Only the requested
chapters are written, so the app seed stays small.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


BOOKS = {
    "gn": ("gen", "Geneza", 1),
    "ex": ("exo", "Exodul", 2),
    "lv": ("lev", "Leviticul", 3),
    "nu": ("num", "Numeri", 4),
    "dt": ("deu", "Deuteronomul", 5),
}


def parse_chapters(spec: str, available: list[str]) -> list[str]:
    if spec == "all":
        return available
    chosen: list[str] = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            start, end = part.split("-", 1)
            for number in range(int(start), int(end) + 1):
                chosen.append(str(number))
        else:
            chosen.append(str(int(part)))
    missing = [number for number in chosen if number not in available]
    if missing:
        raise SystemExit(f"Capitole lipsă din sursă: {', '.join(missing)}")
    return chosen


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, help="JSON Cornilescu complet (m0ty ron-cornilescu-1924)")
    parser.add_argument("--book", default="gn")
    parser.add_argument("--chapters", default="1-3")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    dump = json.loads(Path(args.source).read_text(encoding="utf-8"))
    book = dump["books"][args.book]
    numbers = parse_chapters(args.chapters, list(book["chapters"].keys()))
    book_id, book_name, order = BOOKS.get(args.book, (args.book, args.book, 99))
    chapters = []
    for number in numbers:
        verses = book["chapters"][number]
        chapters.append(
            {
                "n": int(number),
                "verses": [{"n": int(key), "text": verses[key]} for key in sorted(verses, key=lambda item: int(item))],
            }
        )
    payload = {
        "translation": {
            "id": "cornilescu-1924",
            "name": "Cornilescu 1924",
            "language": "ro",
            "license": (
                "Textul Cornilescu publicat în 1924, ortografie veche. "
                "În Statele Unite este în domeniul public (publicat înainte de 1930). "
                "Copiat din m0ty/bible-io-json, fișierul Romanian/ron-cornilescu-1924.json."
            ),
            "source": "https://github.com/m0ty/bible-io-json/blob/main/Romanian/ron-cornilescu-1924.json",
        },
        "books": [{"id": book_id, "name": book_name, "order": order, "chapters": chapters}],
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    total = sum(len(chapter["verses"]) for chapter in chapters)
    print(f"Am scris {total} versete în {out}")


if __name__ == "__main__":
    main()
