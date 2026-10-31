#!/usr/bin/env python3
"""Romanian narration with Piper (ro_RO mihai, CC0 dataset) plus word timings.

Audio is stored as AAC in an .m4a file so AVAudioPlayer on iOS can play it.
Finished verses are skipped.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import urllib.request
import wave
from pathlib import Path

import numpy as np

from extract_characters import extract
from timings import word_timings

VOICE_ONNX = (
    "https://huggingface.co/rhasspy/piper-voices/resolve/main/"
    "ro/ro_RO/mihai/medium/ro_RO-mihai-medium.onnx"
)
VOICE_JSON = VOICE_ONNX + ".json"


def download(url: str, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size > 0:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"Descarc {dest.name}")
    urllib.request.urlretrieve(url, dest)


def synthesize(voice, text: str, wav_path: Path) -> None:
    wav_path.parent.mkdir(parents=True, exist_ok=True)
    if hasattr(voice, "synthesize_wav"):
        with wave.open(str(wav_path), "wb") as handle:
            voice.synthesize_wav(text, handle)
        return
    chunks = list(voice.synthesize(text))
    if not chunks:
        raise RuntimeError("Piper nu a întors audio")
    sample_rate = chunks[0].sample_rate
    width = chunks[0].sample_width
    channels = chunks[0].sample_channels
    with wave.open(str(wav_path), "wb") as handle:
        handle.setnchannels(channels)
        handle.setsampwidth(width)
        handle.setframerate(sample_rate)
        for chunk in chunks:
            handle.writeframes(chunk.audio_int16_bytes)


def read_pcm(wav_path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(wav_path), "rb") as handle:
        sample_rate = handle.getframerate()
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        frames = handle.readframes(handle.getnframes())
    if width != 2:
        raise RuntimeError(f"WAV neașteptat ({width} bytes/eșantion) în {wav_path}")
    pcm = np.frombuffer(frames, dtype=np.int16)
    if channels > 1:
        pcm = pcm[::channels]
    return pcm, sample_rate


def to_m4a(wav_path: Path, m4a_path: Path) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise SystemExit("Lipsește ffmpeg. În notebook: apt-get install -y ffmpeg")
    m4a_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.check_call(
        [ffmpeg, "-y", "-i", str(wav_path), "-c:a", "aac", "-b:a", "64k", str(m4a_path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def run(verses_path: Path, aliases_path: Path, output: Path, limit: int) -> None:
    bible = json.loads(verses_path.read_text(encoding="utf-8"))
    aliases = json.loads(aliases_path.read_text(encoding="utf-8"))
    verses = extract(bible, aliases)["verses"]
    if limit > 0:
        verses = verses[:limit]
    audio_dir = output / "audio"
    timing_dir = output / "state" / "timings"
    pending = []
    for verse in verses:
        m4a = audio_dir / f"{verse['id']}.m4a"
        timing = timing_dir / f"{verse['id']}.json"
        if m4a.exists() and timing.exists():
            continue
        pending.append(verse)
    if not pending:
        print("Narațiunile există deja.")
        return
    voice_dir = output / "voices"
    onnx = voice_dir / "ro_RO-mihai-medium.onnx"
    download(VOICE_ONNX, onnx)
    download(VOICE_JSON, Path(str(onnx) + ".json"))
    from piper import PiperVoice

    voice = PiperVoice.load(str(onnx))
    for verse in pending:
        print(f"Voce {verse['id']}")
        wav_path = audio_dir / f"{verse['id']}.wav"
        m4a_path = audio_dir / f"{verse['id']}.m4a"
        synthesize(voice, verse["text"], wav_path)
        pcm, sample_rate = read_pcm(wav_path)
        rows = word_timings(pcm, sample_rate, verse["text"])
        to_m4a(wav_path, m4a_path)
        wav_path.unlink(missing_ok=True)
        timing_dir.mkdir(parents=True, exist_ok=True)
        (timing_dir / f"{verse['id']}.json").write_text(
            json.dumps(
                {"words": rows, "characters": verse.get("characters") or []},
                ensure_ascii=False,
            )
            + "\n",
            encoding="utf-8",
        )


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
