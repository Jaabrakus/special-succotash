"""Assemble actual Godot capture frames; no generated artwork."""
from pathlib import Path
import sys
from PIL import Image

root = Path(__file__).resolve().parents[1] / "art_source/jump_direction_combos"
if "--gameplay" in sys.argv:
    root = root / "gameplay"
if "--crouched" in sys.argv:
    root = root / "crouched"
frames = []
bits = (8,) if "--back-only" in sys.argv else (1, 2, 4, 8)
for index in range(90):
    single = len(bits) == 1
    sheet = Image.new("RGB", (640, 400) if single else (960, 600))
    for slot, bit in enumerate(bits):
        with Image.open(root / str(bit) / f"{index:03}.png") as frame:
            sheet.paste(frame.convert("RGB").resize((640, 400) if single else (480, 300)), ((slot % 2) * 480, (slot // 2) * 300))
    frames.append(sheet.quantize(colors=192))
frames[0].save(root / "jump_direction_combos.gif", save_all=True, append_images=frames[1:],
               loop=0, duration=[33] * 89 + [700], disposal=2)
print(root / "jump_direction_combos.gif")
