#!/usr/bin/env python3
"""Tiny brand mark and a short fallback tone. The feed itself draws its own stills."""

from __future__ import annotations

import math
import struct
import wave
import zlib
from pathlib import Path


def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path: Path, size: int = 64) -> None:
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            dx = x - (size / 2)
            dy = y - (size / 2)
            dist = math.sqrt(dx * dx + dy * dy)
            if dist < size * 0.46:
                # gold disc
                shade = 180 + int(40 * (1 - dist / (size * 0.46)))
                row += bytes((min(255, shade + 30), shade, 70, 255))
            else:
                row += bytes((12, 12, 14, 255))
            # a simple open-book notch in the middle
            if abs(dx) < size * 0.22 and abs(dy) < size * 0.16 and abs(dx) > size * 0.03:
                row[-4:] = bytes((28, 22, 16, 255))
        rows.append(bytes(row))
    raw = b"".join(rows)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def write_wav(path: Path) -> None:
    rate = 8000
    seconds = 0.18
    count = int(rate * seconds)
    frames = bytearray()
    for i in range(count):
        t = i / rate
        env = min(1.0, 40 * t) * math.exp(-10 * t)
        sample = int(env * 4000 * math.sin(2 * math.pi * 523.25 * t))
        frames += struct.pack("<h", sample)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(frames)


def main() -> None:
    assets = Path(__file__).resolve().parents[1] / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    write_png(assets / "placeholder.png")
    write_wav(assets / "placeholder.wav")
    print(f"placeholder.png {(assets / 'placeholder.png').stat().st_size} bytes")
    print(f"placeholder.wav {(assets / 'placeholder.wav').stat().st_size} bytes")


if __name__ == "__main__":
    main()
