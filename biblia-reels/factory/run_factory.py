#!/usr/bin/env python3
"""Run the whole free content factory. Safe to stop and start again."""

from __future__ import annotations

import argparse
from pathlib import Path

import build_manifest
import gen_audio
import gen_images
import llm_prompts


def main() -> None:
    parser = argparse.ArgumentParser(description="Fabrica Biblia Reels")
    parser.add_argument("--verses", default=str(Path(__file__).resolve().parents[1] / "data" / "bible.json"))
    parser.add_argument("--aliases", default=str(Path(__file__).resolve().parents[1] / "data" / "aliases.json"))
    parser.add_argument("--out", default=str(Path(__file__).resolve().parent / "output"))
    parser.add_argument("--model", default="Qwen/Qwen2.5-7B-Instruct")
    parser.add_argument("--limit", type=int, default=0, help="Doar primele N versete (0 = toate)")
    parser.add_argument(
        "--steps",
        default="prompts,images,audio,manifest",
        help="Lista: prompts,images,audio,manifest",
    )
    args = parser.parse_args()
    verses = Path(args.verses)
    aliases = Path(args.aliases)
    output = Path(args.out)
    output.mkdir(parents=True, exist_ok=True)
    steps = [step.strip() for step in args.steps.split(",") if step.strip()]
    if "prompts" in steps:
        llm_prompts.run(verses, aliases, output, args.model, args.limit)
        build_manifest.main_with(verses, aliases, output)
    if "images" in steps:
        gen_images.run(verses, aliases, output, args.limit)
        build_manifest.main_with(verses, aliases, output)
    if "audio" in steps:
        gen_audio.run(verses, aliases, output, args.limit)
        build_manifest.main_with(verses, aliases, output)
    if "manifest" in steps:
        build_manifest.main_with(verses, aliases, output)
    print(f"Gata. Publică folderul {output} (manifest.json, images, audio, avatars).")


if __name__ == "__main__":
    main()
