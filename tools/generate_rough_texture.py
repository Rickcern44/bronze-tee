"""Generate a repeatable, stylized rough-grass texture; requires Pillow."""
import math
import random
from pathlib import Path
from PIL import Image, ImageDraw

size = 512
rng = random.Random(314159)
image = Image.new("RGB", (size, size))
pixels = image.load()
for y in range(size):
    for x in range(size):
        variation = 7 * math.sin(math.tau * (2*x + 3*y) / size) + 5 * math.cos(math.tau * (5*x - 2*y) / size)
        v = round(177 + variation)
        pixels[x, y] = (v, v, v)
draw = ImageDraw.Draw(image)
for _ in range(14000):
    x, y = rng.randrange(size), rng.randrange(size)
    angle = rng.uniform(0, math.tau)
    length = rng.uniform(7, 24)
    dx, dy = math.cos(angle) * length, math.sin(angle) * length
    value = rng.randrange(72, 229)
    width = rng.choice((1, 2, 2, 3))
    for ox in (-size, 0, size):
        for oy in (-size, 0, size):
            if -26 <= x + ox < size + 26 and -26 <= y + oy < size + 26:
                draw.line((x+ox, y+oy, x+dx+ox, y+dy+oy), fill=(value, value, value), width=width)
out = Path(__file__).resolve().parents[1] / "assets/textures/rough_grass.png"
image.save(out, optimize=True)
print(out)
