"""Generate the project's small, repeatable stylized fairway texture.

Run with Python 3 and Pillow. Random seed, placement and edge wrapping are fixed
so the committed PNG can be regenerated consistently.
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 512
rng = random.Random(7423)
# Seamless periodic undertone, with no external image assets.
image = Image.new("RGB", (SIZE, SIZE))
pixels = image.load()
for y in range(SIZE):
    for x in range(SIZE):
        variation = (3.4 * math.sin(2 * math.pi * (3 * x + 2 * y) / SIZE)
                     + 2.5 * math.cos(2 * math.pi * (2 * x - 5 * y) / SIZE))
        value = round(191 + variation)
        pixels[x, y] = (value, value, value)

draw = ImageDraw.Draw(image)
# Short overlapping strokes read as mown blades without photorealistic noise.
# Wrap marks over the image edges, so the tile repeats without a visible seam.
for _ in range(18000):
    x, y = rng.randrange(SIZE), rng.randrange(SIZE)
    angle = rng.uniform(0, math.tau)
    length = rng.uniform(3.0, 11.0)
    dx, dy = math.cos(angle) * length, math.sin(angle) * length
    value = rng.randrange(105, 235)
    width = 1 if rng.random() < .82 else 2
    for ox in (-SIZE, 0, SIZE):
        for oy in (-SIZE, 0, SIZE):
            if -12 <= x + ox < SIZE + 12 and -12 <= y + oy < SIZE + 12:
                draw.line((x + ox, y + oy, x + dx + ox, y + dy + oy),
                          fill=(value, value, value), width=width)

output = Path(__file__).resolve().parents[1] / "assets/textures/fairway_grass.png"
output.parent.mkdir(parents=True, exist_ok=True)
image.save(output, optimize=True)
print(output)
