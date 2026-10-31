#!/usr/bin/env python3
"""Offline checks for the seed, the mention extractor, timings, and the manifest."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

from build_manifest import build
from extract_characters import extract
from textutil import mentions_in_tokens, tokens
from timings import word_timings

DATA = ROOT.parent / "data"


class ExtractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bible = json.loads((DATA / "bible.json").read_text(encoding="utf-8"))
        cls.aliases = json.loads((DATA / "aliases.json").read_text(encoding="utf-8"))
        cls.doc = extract(cls.bible, cls.aliases)
        cls.by_id = {verse["id"]: verse for verse in cls.doc["verses"]}
        cls.chars = {character["id"]: character for character in cls.doc["characters"]}

    def test_verse_count(self):
        self.assertEqual(len(self.doc["verses"]), 80)
        self.assertEqual(self.doc["verses"][0]["id"], "gen.1.1")
        self.assertEqual(self.doc["verses"][-1]["id"], "gen.3.24")

    def test_opening_is_only_god(self):
        self.assertEqual(self.by_id["gen.1.1"]["characters"], ["dumnezeu"])

    def test_adam_alias_om_and_not_femeiasca(self):
        mentioned = self.by_id["gen.1.27"]["characters"]
        self.assertIn("dumnezeu", mentioned)
        self.assertIn("adam", mentioned)
        self.assertNotIn("eva", mentioned)

    def test_named_people(self):
        self.assertIn("adam", self.by_id["gen.2.7"]["characters"])
        self.assertIn("dumnezeu", self.by_id["gen.2.7"]["characters"])
        self.assertIn("eva", self.by_id["gen.2.22"]["characters"])
        self.assertIn("sarpele", self.by_id["gen.3.1"]["characters"])
        self.assertIn("eva", self.by_id["gen.3.1"]["characters"])
        self.assertIn("adam", self.by_id["gen.3.20"]["characters"])
        self.assertIn("eva", self.by_id["gen.3.20"]["characters"])
        self.assertIn("heruvimi", self.by_id["gen.3.24"]["characters"])
        self.assertIn("adam", self.by_id["gen.3.24"]["characters"])

    def test_seed_file_matches_extractor(self):
        committed = json.loads((DATA / "characters.json").read_text(encoding="utf-8"))
        for character in committed["characters"]:
            self.assertEqual(character["verseIds"], self.chars[character["id"]]["verseIds"])

    def test_phrase_beats_shorter_alias(self):
        hits = mentions_in_tokens(tokens("Duhul lui Dumnezeu se mișca"), [("dumnezeu", ("dumnezeu",)), ("dumnezeu", ("duhul", "lui", "dumnezeu"))])
        self.assertEqual(hits, ["dumnezeu"])


class TimingTests(unittest.TestCase):
    def test_words_are_ordered_across_the_voice(self):
        sample_rate = 16000
        pcm = [0] * sample_rate
        for index in range(1600, 12800):
            pcm[index] = 8000
        rows = word_timings(pcm, sample_rate, "La început Dumnezeu")
        self.assertEqual([row["t"] for row in rows], ["La", "început", "Dumnezeu"])
        starts = [row["s"] for row in rows]
        self.assertEqual(starts, sorted(starts))
        self.assertGreaterEqual(rows[0]["s"], 0.0)
        self.assertLessEqual(rows[-1]["e"], 1.01)
        self.assertGreater(rows[1]["s"], rows[0]["s"])


class ManifestTests(unittest.TestCase):
    def test_partial_publish(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            verse_id = "gen.1.1"
            (output / "images").mkdir()
            (output / "audio").mkdir()
            (output / "state" / "timings").mkdir(parents=True)
            (output / "images" / f"{verse_id}.webp").write_bytes(b"webp")
            (output / "audio" / f"{verse_id}.m4a").write_bytes(b"m4a")
            (output / "state" / "timings" / f"{verse_id}.json").write_text(
                json.dumps({"words": [{"t": "La", "s": 0.0, "e": 0.2}]}),
                encoding="utf-8",
            )
            (output / "state").mkdir(exist_ok=True)
            (output / "state" / "bios.json").write_text(
                json.dumps({"dumnezeu": "Bio din fabrică."}),
                encoding="utf-8",
            )
            manifest = build(DATA / "bible.json", DATA / "aliases.json", output)
            self.assertEqual([verse["id"] for verse in manifest["verses"]], [verse_id])
            self.assertEqual(manifest["verses"][0]["words"][0]["t"], "La")
            self.assertIn("dumnezeu", manifest["verses"][0]["characters"])
            god = next(character for character in manifest["characters"] if character["id"] == "dumnezeu")
            self.assertEqual(god["bio"], "Bio din fabrică.")
            self.assertEqual(god["verseIds"], [verse_id])
            self.assertEqual(manifest["characters"][1]["verseIds"], [])


if __name__ == "__main__":
    unittest.main()
