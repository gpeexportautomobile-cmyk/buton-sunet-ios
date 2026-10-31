"""Shared text helpers for the seed, the factory, and the tests."""

from __future__ import annotations

import re
import unicodedata
from typing import Iterable


def norm(text: str) -> str:
    text = text.lower()
    text = unicodedata.normalize("NFD", text)
    return "".join(ch for ch in text if unicodedata.category(ch) != "Mn")


def tokens(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", norm(text))


def whitespace_words(text: str) -> list[str]:
    return re.findall(r"\S+", text.strip())


def load_alias_table(characters: Iterable[dict]) -> list[tuple[str, tuple[str, ...]]]:
    rows: list[tuple[str, tuple[str, ...]]] = []
    for character in characters:
        cid = character["id"]
        for alias in character.get("aliases") or []:
            parts = tuple(tokens(alias))
            if parts:
                rows.append((cid, parts))
    rows.sort(key=lambda row: len(row[1]), reverse=True)
    return rows


def mentions_in_tokens(toks: list[str], table: list[tuple[str, tuple[str, ...]]]) -> list[str]:
    found: list[str] = []
    seen: set[str] = set()
    for cid, alias in table:
        if cid in seen or not alias:
            continue
        width = len(alias)
        for index in range(0, len(toks) - width + 1):
            if tuple(toks[index : index + width]) == alias:
                seen.add(cid)
                found.append(cid)
                break
    return found


def flatten_bible(bible: dict) -> list[dict]:
    verses: list[dict] = []
    for book in bible.get("books") or []:
        book_id = book["id"]
        book_name = book["name"]
        order = int(book.get("order") or 0)
        for chapter in book.get("chapters") or []:
            chapter_n = int(chapter["n"])
            for verse in chapter.get("verses") or []:
                number = int(verse["n"])
                verses.append(
                    {
                        "id": f"{book_id}.{chapter_n}.{number}",
                        "bookId": book_id,
                        "book": book_name,
                        "bookOrder": order,
                        "chapter": chapter_n,
                        "verse": number,
                        "text": verse["text"],
                    }
                )
    return verses


def attach_mentions(verses: list[dict], characters: list[dict]) -> dict[str, list[str]]:
    table = load_alias_table(characters)
    by_id = {character["id"]: [] for character in characters}
    for verse in verses:
        hits = mentions_in_tokens(tokens(verse["text"]), table)
        verse["characters"] = hits
        for cid in hits:
            by_id.setdefault(cid, []).append(verse["id"])
    return by_id
