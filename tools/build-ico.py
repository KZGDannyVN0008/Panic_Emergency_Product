#!/usr/bin/env python3
"""Package PNG images into a Windows ICO without third-party dependencies."""

import argparse
import struct
from pathlib import Path


def png_dimensions(data: bytes) -> tuple[int, int]:
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("Input is not a PNG")
    return struct.unpack(">II", data[16:24])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("images", nargs="+")
    args = parser.parse_args()
    payloads = []
    for value in args.images:
        data = Path(value).read_bytes()
        width, height = png_dimensions(data)
        if width != height or width > 256:
            raise ValueError("ICO inputs must be square PNGs up to 256px")
        payloads.append((width, height, data))

    header = struct.pack("<HHH", 0, 1, len(payloads))
    offset = 6 + 16 * len(payloads)
    entries = []
    for width, height, data in payloads:
        entries.append(
            struct.pack(
                "<BBBBHHII",
                0 if width == 256 else width,
                0 if height == 256 else height,
                0,
                0,
                1,
                32,
                len(data),
                offset,
            )
        )
        offset += len(data)
    Path(args.out).write_bytes(header + b"".join(entries) + b"".join(item[2] for item in payloads))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
