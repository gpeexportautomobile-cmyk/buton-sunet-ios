#!/usr/bin/env python3
"""Write a style bible, one image prompt per verse, and a Romanian bio per character.

Uses Qwen2.5-7B-Instruct in 4-bit on a free GPU. Finished files are skipped.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from extract_characters import extract


SYSTEM = (
    "You write production notes for a respectful illustrated Bible series. "
    "Return only JSON, no markdown. Keep every character's appearance identical "
    "across verses. No nudity, no gore, no letters, no watermark. "
    "God is never a human face or body, only warm divine light."
)


def extract_json(text: str) -> dict:
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end <= start:
        raise ValueError("răspunsul nu conține JSON")
    return json.loads(text[start : end + 1])


class Writer:
    def __init__(self, model_id: str):
        import torch
        from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig

        if not torch.cuda.is_available():
            raise SystemExit(
                "Nu există GPU. În Colab: Runtime → Change runtime type → T4. "
                "În Kaggle: Settings → Accelerator → GPU. Apoi rulează din nou; pașii gata sunt săriți."
            )
        quant = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_compute_dtype=torch.float16)
        self.tokenizer = AutoTokenizer.from_pretrained(model_id)
        self.model = AutoModelForCausalLM.from_pretrained(
            model_id,
            quantization_config=quant,
            device_map="auto",
        )
        self.model_id = model_id

    def ask(self, user: str, max_new_tokens: int = 700) -> dict:
        messages = [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": user},
        ]
        prompt = self.tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        import torch

        inputs = self.tokenizer(prompt, return_tensors="pt").to(self.model.device)
        last_error = None
        for _ in range(2):
            with torch.no_grad():
                output = self.model.generate(
                    **inputs,
                    max_new_tokens=max_new_tokens,
                    do_sample=False,
                )
            text = self.tokenizer.decode(output[0][inputs["input_ids"].shape[1] :], skip_special_tokens=True)
            try:
                return extract_json(text)
            except (ValueError, json.JSONDecodeError) as exc:
                last_error = exc
        raise RuntimeError(f"JSON invalid de la model: {last_error}")

    def close(self) -> None:
        import torch

        del self.model
        del self.tokenizer
        if torch.cuda.is_available():
            torch.cuda.empty_cache()


def style_request() -> str:
    return (
        "Create a style bible for Genesis 1-3 stills. JSON shape:\n"
        '{"style":"one English paragraph, cinematic, natural light, 9:16",'
        '"characters":{"dumnezeu":"appearance lock","adam":"...","eva":"...","sarpele":"...","heruvimi":"..."}}\n'
        "Adam is a young Middle-Eastern man in a plain linen tunic. "
        "Eva is a young Middle-Eastern woman in a plain linen dress. "
        "The serpent is a natural snake among branches, not a monster. "
        "Cherubim are distant solemn guardians, no horror. "
        "God is only light."
    )


def verse_request(verse: dict, style: dict) -> str:
    names = ", ".join(verse.get("characters") or []) or "none"
    locks = style.get("characters") or {}
    present = {cid: locks.get(cid, "") for cid in (verse.get("characters") or [])}
    return (
        f"Verse {verse['id']} ({verse['book']} {verse['chapter']}:{verse['verse']}).\n"
        f"Romanian text, for your understanding only, do not copy it into the prompt: {verse['text']}\n"
        f"Characters present: {names}\n"
        f"Style: {style.get('style','')}\n"
        f"Appearance locks: {json.dumps(present, ensure_ascii=False)}\n"
        'Return {"scene":"60-90 English words, a single vertical still, no text in the image"}'
    )


def bio_request(characters: list[dict], verses: list[dict]) -> str:
    blocks = []
    by_id = {verse["id"]: verse["text"] for verse in verses}
    for character in characters:
        ids = character.get("verseIds") or []
        sample = ids[:6] + ids[-2:] if len(ids) > 8 else ids
        lines = [f"{vid}: {by_id[vid]}" for vid in sample if vid in by_id]
        blocks.append(f"{character['id']} ({character['name']}):\n" + "\n".join(lines))
    return (
        "Write a Romanian bio of 2 short sentences for each character, using only the verses below. "
        "Do not add events from later books. JSON object whose keys are the ids and whose values are the bios.\n\n"
        + "\n\n".join(blocks)
    )


def run(verses_path: Path, aliases_path: Path, output: Path, model_id: str, limit: int) -> None:
    bible = json.loads(verses_path.read_text(encoding="utf-8"))
    aliases = json.loads(aliases_path.read_text(encoding="utf-8"))
    extracted = extract(bible, aliases)
    verses = extracted["verses"]
    if limit > 0:
        verses = verses[:limit]
    state = output / "state"
    prompts = state / "prompts"
    prompts.mkdir(parents=True, exist_ok=True)
    style_path = state / "style_bible.json"
    bio_path = state / "bios.json"
    missing_prompts = [verse for verse in verses if not (prompts / f"{verse['id']}.json").exists()]
    need_model = (not style_path.exists()) or (not bio_path.exists()) or bool(missing_prompts)
    if not need_model:
        print("Prompturile și biografiile există deja.")
        return
    writer = Writer(model_id)
    try:
        if style_path.exists():
            style = json.loads(style_path.read_text(encoding="utf-8"))
        else:
            print("Scriu stilul personajelor…")
            style = writer.ask(style_request())
            style_path.write_text(json.dumps(style, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        for verse in missing_prompts:
            print(f"Prompt {verse['id']}")
            data = writer.ask(verse_request(verse, style), max_new_tokens=400)
            scene = str(data.get("scene") or "").strip()
            if not scene:
                raise RuntimeError(f"prompt gol pentru {verse['id']}")
            (prompts / f"{verse['id']}.json").write_text(
                json.dumps({"scene": scene}, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
        if not bio_path.exists():
            print("Scriu biografiile…")
            bios = writer.ask(bio_request(extracted["characters"], extracted["verses"]), max_new_tokens=900)
            clean = {character["id"]: str(bios.get(character["id"]) or "").strip() for character in extracted["characters"]}
            bio_path.write_text(json.dumps(clean, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    finally:
        writer.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verses", required=True)
    parser.add_argument("--aliases", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--model", default="Qwen/Qwen2.5-7B-Instruct")
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()
    try:
        run(Path(args.verses), Path(args.aliases), Path(args.out), args.model, args.limit)
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 — surface a single Romanian line in the notebook
        print(f"Eroare la prompturi: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
