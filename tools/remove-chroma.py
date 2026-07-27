#!/usr/bin/env python3
"""Remove a magenta chroma background from an 8-bit RGB/RGBA PNG."""

import argparse
import binascii
import struct
import zlib
from pathlib import Path

SIGNATURE = b"\x89PNG\r\n\x1a\n"


def chunks(data: bytes):
    position = 8
    while position < len(data):
        length = struct.unpack(">I", data[position : position + 4])[0]
        kind = data[position + 4 : position + 8]
        payload = data[position + 8 : position + 8 + length]
        yield kind, payload
        position += 12 + length


def paeth(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    distances = (abs(estimate - left), abs(estimate - above), abs(estimate - upper_left))
    return (left, above, upper_left)[distances.index(min(distances))]


def decode(path: Path):
    data = path.read_bytes()
    if data[:8] != SIGNATURE:
        raise ValueError("input is not a PNG")
    items = list(chunks(data))
    ihdr = next(payload for kind, payload in items if kind == b"IHDR")
    width, height, depth, color_type, compression, filtering, interlace = struct.unpack(">IIBBBBB", ihdr)
    if depth != 8 or color_type not in (2, 6) or compression or filtering or interlace:
        raise ValueError("only non-interlaced 8-bit RGB/RGBA PNG files are supported")
    channels = 3 if color_type == 2 else 4
    raw = zlib.decompress(b"".join(payload for kind, payload in items if kind == b"IDAT"))
    stride = width * channels
    rows = []
    offset = 0
    previous = bytearray(stride)
    for _ in range(height):
        filter_type = raw[offset]
        offset += 1
        encoded = raw[offset : offset + stride]
        offset += stride
        row = bytearray(stride)
        for index, value in enumerate(encoded):
            left = row[index - channels] if index >= channels else 0
            above = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filter_type == 0:
                decoded = value
            elif filter_type == 1:
                decoded = value + left
            elif filter_type == 2:
                decoded = value + above
            elif filter_type == 3:
                decoded = value + ((left + above) // 2)
            elif filter_type == 4:
                decoded = value + paeth(left, above, upper_left)
            else:
                raise ValueError(f"unsupported PNG filter: {filter_type}")
            row[index] = decoded & 0xFF
        rows.append(row)
        previous = row
    return width, height, channels, rows


def make_chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)
    )


def encode(path: Path, width: int, height: int, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(
        SIGNATURE
        + make_chunk(b"IHDR", ihdr)
        + make_chunk(b"IDAT", zlib.compress(raw, 9))
        + make_chunk(b"IEND", b"")
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("output")
    args = parser.parse_args()
    width, height, channels, rows = decode(Path(args.input))
    output_rows = []
    for row in rows:
        output = bytearray()
        for index in range(0, len(row), channels):
            red, green, blue = row[index : index + 3]
            source_alpha = row[index + 3] if channels == 4 else 255
            distance = ((255 - red) ** 2 + green**2 + (255 - blue) ** 2) ** 0.5
            if distance <= 100:
                alpha = 0
            elif distance >= 180:
                alpha = 255
            else:
                alpha = round(((distance - 100) / 80) * 255)
            alpha = min(alpha, source_alpha)
            spill = (255 - alpha) / 255
            output.extend((round(red * (1 - spill)), green, round(blue * (1 - spill)), alpha))
        output_rows.append(output)
    encode(Path(args.output), width, height, output_rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
