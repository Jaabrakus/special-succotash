#!/usr/bin/env python3
"""Compose four square proof frames into one labeled 2x2 PNG."""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw


def main() -> None:
    args = sys.argv[1:]
    if len(args) != 5:
        raise RuntimeError("Expected FRAME.png FRAME.png FRAME.png FRAME.png OUTPUT.png")
    inputs = [Path(value).resolve() for value in args[:4]]
    output = Path(args[4]).resolve()
    images = [Image.open(path).convert("RGB") for path in inputs]
    width, height = images[0].size
    sheet = Image.new("RGB", (width * 2, height * 2), (12, 18, 24))
    draw = ImageDraw.Draw(sheet)
    for index, (path, image) in enumerate(zip(inputs, images)):
        x = (index % 2) * width
        y = (index // 2) * height
        sheet.paste(image, (x, y))
        draw.rectangle((x + 15, y + 15, x + 145, y + 50), fill=(8, 14, 20))
        draw.text((x + 27, y + 24), path.stem.replace("_", " ").upper(), fill=(132, 238, 202))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)
    print(f"OPERATOR_ARP_CONTACT_SHEET_PASS output={output}")


if __name__ == "__main__":
    main()
