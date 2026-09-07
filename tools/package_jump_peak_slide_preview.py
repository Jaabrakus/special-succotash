"""Package Godot-rendered frames as a review GIF; does not generate artwork."""
from pathlib import Path
from PIL import Image

output = Path(__file__).resolve().parents[1] / "art_source" / "jump_peak_slide"
paths = sorted((output / "right_knee_frames").glob("[0-9][0-9][0-9].png"))
assert len(paths) == 66, f"Expected 66 rendered frames, found {len(paths)}"
frames = []
for path in paths:
    with Image.open(path) as frame:
        frames.append(frame.convert("RGB").quantize(colors=192))
frames[0].save(
    output / "right_knee_slide_preview.gif",
    save_all=True, append_images=frames[1:], loop=0,
    duration=[33] * 65 + [650], disposal=2,
)
print(output / "right_knee_slide_preview.gif")
