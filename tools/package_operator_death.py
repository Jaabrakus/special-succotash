"""Package actual canonical-game death capture frames as a review GIF."""
from pathlib import Path
from PIL import Image

folder = Path(__file__).resolve().parents[1] / "art_source/operator_death"
frames = []
for index in range(0, 120, 2):
    with Image.open(folder / f"{index:03}.png") as frame:
        frames.append(frame.resize((640, 400)).quantize(colors=128))
frames[0].save(folder / "death_preview.gif", save_all=True,
               append_images=frames[1:], loop=0,
               duration=[67] * 59 + [900], disposal=2)
print(folder / "death_preview.gif")
