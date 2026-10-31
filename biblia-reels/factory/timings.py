"""Word timings from a spoken waveform.

Piper does not return word boundaries. The verse is one short utterance, so the
words are laid across the voiced region in proportion to their letter weight.
Highlighting stays in order with the subtitle tokens (\\S+).
"""

from __future__ import annotations

import re


def _samples(pcm) -> list[float]:
    if hasattr(pcm, "tolist"):
        return [float(sample) for sample in pcm.tolist()]
    return [float(sample) for sample in pcm]


def word_timings(pcm, sample_rate: int, text: str) -> list[dict]:
    words = re.findall(r"\S+", text.strip())
    if not words:
        return []
    samples = _samples(pcm)
    duration = (len(samples) / float(sample_rate)) if sample_rate and samples else 0.0
    if duration <= 0:
        return [{"t": word, "s": 0.0, "e": 0.01} for word in words]

    frame = max(1, int(sample_rate * 0.02))
    hop = frame
    rms: list[float] = []
    if len(samples) >= frame:
        for start in range(0, len(samples) - frame + 1, hop):
            chunk = samples[start : start + frame]
            rms.append((sum(sample * sample for sample in chunk) / frame) ** 0.5)
    peak = max(rms) if rms else 0.0
    threshold = max(80.0, peak * 0.18)
    voiced = [index for index, value in enumerate(rms) if value >= threshold]
    if voiced:
        start_s = voiced[0] * hop / float(sample_rate)
        end_s = min(duration, (voiced[-1] * hop + frame) / float(sample_rate))
    else:
        start_s, end_s = 0.0, duration
    if end_s - start_s < 0.05:
        start_s, end_s = 0.0, duration

    weights = [max(1, sum(ch.isalpha() or ch.isdigit() for ch in word)) for word in words]
    total = float(sum(weights))
    span = end_s - start_s
    cursor = start_s
    rows = []
    for word, weight in zip(words, weights):
        piece = span * (weight / total)
        rows.append({"t": word, "s": round(cursor, 3), "e": round(cursor + piece, 3)})
        cursor += piece
    return rows
