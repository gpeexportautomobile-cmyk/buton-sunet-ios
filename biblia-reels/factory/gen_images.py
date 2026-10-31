#!/usr/bin/env python3
"""9:16 stills with FLUX.1-schnell (Apache-2.0). Existing WebP files are skipped."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from extract_characters import extract

SAFETY = (
    "Modest linen clothing, no nudity, no gore, no horror, no text, no letters, "
    "no watermark, no logo, respectful biblical illustration, natural light."
)
GOD_LOCK = "God, if present, is only warm divine light, with no face and no body."


def seed_for(verse_id: str) -> int:
    value = 0
    for ch in verse_id:
        value = (value * 33 + ord(ch)) & 0x7FFFFFFF
    return value or 1


def load_pipe():
    import torch
    from diffusers import FluxPipeline

    if not torch.cuda.is_available():
        raise SystemExit(
            "Nu există GPU pentru imagini. Activează T4 în Colab sau Kaggle și reia; "
            "versetele deja scrise rămân pe disc."
        )
    pipe = FluxPipeline.from_pretrained("black-forest-labs/FLUX.1-schnell", torch_dtype=torch.bfloat16)
    pipe.set_progress_bar_config(disable=True)
    try:
        pipe.to("cuda")
    except RuntimeError:
        pipe.enable_model_cpu_offload()
    return pipe


def render(pipe, prompt: str, path: Path, width: int, height: int, seed: int) -> None:
    import torch

    image = pipe(
        prompt=prompt,
        guidance_scale=0.0,
        num_inference_steps=4,
        max_sequence_length=256,
        height=height,
        width=width,
        generator=torch.Generator(device="cpu").manual_seed(seed),
    ).images[0]
    image = image.convert("RGB")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "WEBP", quality=74, method=4)


def final_prompt(scene: str) -> str:
    return f"{scene.strip()} {GOD_LOCK} {SAFETY}"


def run(verses_path: Path, aliases_path: Path, output: Path, limit: int) -> None:
    bible = json.loads(verses_path.read_text(encoding="utf-8"))
    aliases = json.loads(aliases_path.read_text(encoding="utf-8"))
    verses = extract(bible, aliases)["verses"]
    if limit > 0:
        verses = verses[:limit]
    images = output / "images"
    prompts = output / "state" / "prompts"
    pending = []
    for verse in verses:
        dest = images / f"{verse['id']}.webp"
        if dest.exists():
            continue
        prompt_path = prompts / f"{verse['id']}.json"
        if not prompt_path.exists():
            print(f"Lipsește promptul pentru {verse['id']}; sar imaginea.")
            continue
        pending.append((verse, dest, prompt_path))
    avatars = output / "avatars"
    style_path = output / "state" / "style_bible.json"
    style = json.loads(style_path.read_text(encoding="utf-8")) if style_path.exists() else {}
    locks = style.get("characters") or {}
    avatar_jobs = []
    for character in aliases["characters"]:
        dest = avatars / f"{character['id']}.webp"
        if dest.exists():
            continue
        lock = locks.get(character["id"]) or character["name"]
        avatar_jobs.append((character, dest, lock))
    if not pending and not avatar_jobs:
        print("Imaginile există deja.")
        return
    pipe = load_pipe()
    try:
        for verse, dest, prompt_path in pending:
            scene = json.loads(prompt_path.read_text(encoding="utf-8")).get("scene") or ""
            print(f"Imagine {verse['id']}")
            render(pipe, final_prompt(scene), dest, 432, 768, seed_for(verse["id"]))
        for character, dest, lock in avatar_jobs:
            print(f"Portret {character['id']}")
            prompt = (
                f"Square portrait, {lock}. Neutral warm background, shoulders up, "
                f"looking slightly aside. {GOD_LOCK} {SAFETY}"
            )
            render(pipe, prompt, dest, 768, 768, seed_for(character["id"]))
    finally:
        del pipe
        import torch

        if torch.cuda.is_available():
            torch.cuda.empty_cache()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verses", required=True)
    parser.add_argument("--aliases", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()
    run(Path(args.verses), Path(args.aliases), Path(args.out), args.limit)


if __name__ == "__main__":
    main()
