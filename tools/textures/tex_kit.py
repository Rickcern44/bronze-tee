"""Shared helpers for the procedural texture library (Phase 0).

Pillow only: numpy is not installed for the system python3, so every field is a
plain list of floats. All textures are SIZE x SIZE RGB and tile seamlessly:

- noise comes from periodic value lattices (tiled 3x3, resampled, centre crop);
- strokes, cracks and pebbles are drawn with wrap-around copies at the edges;
- rng is random.Random seeded from a hash of the texture id, so the output is
  byte-identical on every run.
"""
import hashlib
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageStat

SIZE = 512
TWO_PI = 2.0 * math.pi


def seed_for(texture_id):
    """Stable 48-bit seed derived from the texture id (hash of the id, not Python's hash())."""
    digest = hashlib.sha256(texture_id.encode("utf-8")).hexdigest()
    return int(digest[:12], 16)


def rng_for(texture_id):
    return random.Random(seed_for(texture_id))


def clamp_byte(value):
    value = int(round(value))
    return 0 if value < 0 else (255 if value > 255 else value)


def average_hex(img):
    """Mean colour of an RGB image as #RRGGBB. validate.py uses the same rounding."""
    mean = ImageStat.Stat(img).mean
    return "#%02X%02X%02X" % tuple(clamp_byte(c) for c in mean)


def make_lut(stops, steps=256):
    """Colour ramp as a lookup table of RGB int tuples.

    stops: [(t, (r, g, b)), ...] with t ascending from 0.0 to 1.0.
    """
    lut = []
    for i in range(steps):
        t = i / (steps - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t <= t1:
                k = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
                k = max(0.0, min(1.0, k))
                lut.append(tuple(clamp_byte(a + (b - a) * k) for a, b in zip(c0, c1)))
                break
        else:
            lut.append(tuple(stops[-1][1]))
    return lut


def _value_lattice(rng, cells):
    """One periodic octave: a cells x cells random lattice, smoothly resampled to SIZE x SIZE.

    The lattice is tiled 3x3 before resampling and the centre copy is cropped, so the
    result has exact period SIZE in both directions.
    """
    grid = Image.new("F", (cells, cells))
    grid.putdata([rng.random() for _ in range(cells * cells)])
    tiled = Image.new("F", (cells * 3, cells * 3))
    for ox in range(3):
        for oy in range(3):
            tiled.paste(grid, (ox * cells, oy * cells))
    big = tiled.resize((SIZE * 3, SIZE * 3), Image.BICUBIC)
    return list(big.crop((SIZE, SIZE, SIZE * 2, SIZE * 2)).getdata())


def fbm(rng, octaves):
    """Seamless fractal noise. octaves: [(cells, weight), ...]. Returns SIZE*SIZE floats in [0, 1]."""
    acc = [0.0] * (SIZE * SIZE)
    for cells, weight in octaves:
        layer = _value_lattice(rng, cells)
        acc = [a + weight * v for a, v in zip(acc, layer)]
    lo, hi = min(acc), max(acc)
    span = (hi - lo) or 1.0
    return [(a - lo) / span for a in acc]


def wave_factor(x, y, wave):
    """Diagonal combing: wave = (m, n, amp) with integer m, n so the pattern wraps.

    Lines of constant phase run along (n, -m); the period is SIZE / hypot(m, n) pixels.
    """
    m, n, amp = wave
    return 1.0 + amp * math.sin(TWO_PI * (m * x + n * y) / SIZE)


def paint(lut, tone, rng=None, speckle=0.0, stripe_amp=0.0, stripe_cycles=8, wave=None):
    """Map a tone field (0..1) through a colour LUT into an RGB image.

    stripe_amp: soft mow-stripe brightness modulation that varies with x only
        (stripe_cycles must be an integer so the stripes wrap).
    speckle: per-pixel luma noise, +/- speckle/2 relative (needs rng).
    wave: optional (m, n, amp) diagonal combing modulation, see wave_factor.
    """
    top = len(lut) - 1
    column = [1.0 + stripe_amp * math.sin(TWO_PI * stripe_cycles * x / SIZE) for x in range(SIZE)]
    pixels = []
    append = pixels.append
    for i, t in enumerate(tone):
        r, g, b = lut[int(t * top + 0.5)]
        k = column[i % SIZE]
        if wave is not None:
            k *= wave_factor(i % SIZE, i // SIZE, wave)
        if speckle:
            k += (rng.random() - 0.5) * speckle
        append((clamp_byte(r * k), clamp_byte(g * k), clamp_byte(b * k)))
    img = Image.new("RGB", (SIZE, SIZE))
    img.putdata(pixels)
    return img


def stroke_colour(lut, tone_lo, tone_hi, stripe_amp=0.0, stripe_cycles=8, wave=None):
    """Colour function for draw_strokes: random tone in [tone_lo, tone_hi], stripe-modulated by x."""
    top = len(lut) - 1

    def colour(rng, x, y):
        r, g, b = lut[int(rng.uniform(tone_lo, tone_hi) * top + 0.5)]
        k = 1.0 + stripe_amp * math.sin(TWO_PI * stripe_cycles * x / SIZE)
        if wave is not None:
            k *= wave_factor(x, y, wave)
        return (clamp_byte(r * k), clamp_byte(g * k), clamp_byte(b * k))

    return colour


def pick_colour(colours):
    """Colour function for draw_strokes: random choice from a fixed palette."""
    def colour(rng, x, y):
        return rng.choice(colours)

    return colour


def _wrapped_line(draw, x, y, dx, dy, width, fill):
    for ox in (-SIZE, 0, SIZE):
        for oy in (-SIZE, 0, SIZE):
            x0, y0 = x + ox, y + oy
            x1, y1 = x0 + dx, y0 + dy
            if max(x0, x1) + width < 0 or min(x0, x1) - width >= SIZE:
                continue
            if max(y0, y1) + width < 0 or min(y0, y1) - width >= SIZE:
                continue
            draw.line((x0, y0, x1, y1), fill=fill, width=width)


def draw_strokes(img, rng, count, length, widths, angle, jitter, colour_fn):
    """Short blade-like strokes, wrapped at the edges. angle/jitter in radians."""
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        x = rng.randrange(SIZE)
        y = rng.randrange(SIZE)
        a = angle + rng.uniform(-jitter, jitter)
        n = rng.uniform(length[0], length[1])
        w = rng.choice(widths)
        fill = colour_fn(rng, x, y)
        _wrapped_line(draw, x, y, math.cos(a) * n, math.sin(a) * n, w, fill)


def draw_walks(img, rng, count, steps, step_len, fill, width=1):
    """Wandering polylines (cracks), wrapped at the edges."""
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        x = rng.randrange(SIZE)
        y = rng.randrange(SIZE)
        a = rng.uniform(0, TWO_PI)
        for _ in range(steps):
            a += rng.uniform(-0.7, 0.7)
            dx = math.cos(a) * step_len
            dy = math.sin(a) * step_len
            _wrapped_line(draw, x, y, dx, dy, width, fill)
            x = (x + int(round(dx))) % SIZE
            y = (y + int(round(dy))) % SIZE


def draw_dots(img, rng, count, radius, colours, outline_shade=0.75):
    """Filled discs (pebbles, stones, grit) with a darker rim, wrapped at the edges."""
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        x = rng.randrange(SIZE)
        y = rng.randrange(SIZE)
        r = rng.uniform(radius[0], radius[1])
        fill = rng.choice(colours)
        rim = tuple(clamp_byte(c * outline_shade) for c in fill)
        for ox in (-SIZE, 0, SIZE):
            for oy in (-SIZE, 0, SIZE):
                cx, cy = x + ox, y + oy
                if cx + r < 0 or cx - r >= SIZE or cy + r < 0 or cy - r >= SIZE:
                    continue
                draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill, outline=rim)


def shade(colour, k):
    """Scale an RGB colour by k (clamped to bytes)."""
    return tuple(clamp_byte(c * k) for c in colour)


def smoothstep(t):
    t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
    return t * t * (3.0 - 2.0 * t)


def caustic_field(field, power=4.0):
    """Bright ridge network from a noise field: 1 on the ridges, 0 in the troughs."""
    return [(1.0 - abs(2.0 * v - 1.0)) ** power for v in field]


def mask_from_field(field, gamma=1.0):
    """L-mode mask from a field in [0, 1]."""
    mask = Image.new("L", (SIZE, SIZE))
    mask.putdata([clamp_byte(255.0 * ((min(1.0, max(0.0, v))) ** gamma)) for v in field])
    return mask


def composite_field(base, overlay, field, gamma=1.0):
    """Blend overlay over base where field is high (soft patches, sheen, lichen)."""
    return Image.composite(overlay, base, mask_from_field(field, gamma))


def draw_shapes(img, rng, count, radius, sides, colours, aspect=1.0, irregular=0.0,
                outline_shade=0.8, shadow=None, centers=None, upright=False):
    """Irregular filled polygons (leaves, stones, chips, bark plates), wrapped at the edges.

    radius: (min, max) in px. aspect: squash factor on the local y axis (leaves: ~0.5).
    irregular: vertex radius jitter fraction. shadow: optional (dx, dy, shade) drawn
    under each shape. centers: optional fixed [(x, y), ...] (count is then ignored).
    """
    draw = ImageDraw.Draw(img)
    if centers is None:
        centers = [(rng.randrange(SIZE), rng.randrange(SIZE)) for _ in range(count)]
    for cx, cy in centers:
        r = rng.uniform(radius[0], radius[1])
        rot = rng.uniform(0, TWO_PI)  # always drawn, so the rng sequence is unchanged
        if upright:
            rot = 0.0  # keep the aspect ratio on the vertical axis
        cos_r, sin_r = math.cos(rot), math.sin(rot)
        verts = []
        for k in range(sides):
            a = TWO_PI * k / sides
            rr = r * (1.0 + irregular * rng.uniform(-1.0, 1.0))
            vx, vy = math.cos(a) * rr, math.sin(a) * rr * aspect
            verts.append((vx * cos_r - vy * sin_r, vx * sin_r + vy * cos_r))
        fill = rng.choice(colours)
        layers = []
        if shadow is not None:
            dark = shade(fill, shadow[2])
            layers.append((shadow[0], shadow[1], dark, dark))
        layers.append((0.0, 0.0, fill, shade(fill, outline_shade)))
        for dx, dy, colour, edge in layers:
            for ox in (-SIZE, 0, SIZE):
                for oy in (-SIZE, 0, SIZE):
                    poly = [(cx + ox + dx + vx, cy + oy + dy + vy) for vx, vy in verts]
                    xs = [p[0] for p in poly]
                    ys = [p[1] for p in poly]
                    if max(xs) < 0 or min(xs) >= SIZE or max(ys) < 0 or min(ys) >= SIZE:
                        continue
                    draw.polygon(poly, fill=colour, outline=edge)


def draw_wave_segments(img, rng, count, length, amp, period, colour_fn, width=1):
    """Irregular ripple lines: short wavy segments at random places, lengths, angles and brightness.

    length: (min, max) px along the segment. amp: wave height px (each segment gets a random
    fraction of it). period: wave length px (random per segment). colour_fn(rng) -> RGB.
    Segments wrap at the edges.
    """
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        x0 = rng.randrange(SIZE)
        y0 = rng.randrange(SIZE)
        seg_len = rng.uniform(length[0], length[1])
        angle = rng.uniform(-0.12, 0.12)
        height = rng.uniform(0.4, 1.0) * amp
        wave_len = rng.uniform(period[0], period[1])
        phase = rng.uniform(0, TWO_PI)
        colour = colour_fn(rng)
        steps = max(2, int(seg_len // 4))
        pts = []
        for i in range(steps + 1):
            s = seg_len * i / steps
            pts.append((s * math.cos(angle), s * math.sin(angle) + height * math.sin(TWO_PI * s / wave_len + phase)))
        for ox in (-SIZE, 0, SIZE):
            for oy in (-SIZE, 0, SIZE):
                line = [(x0 + ox + px, y0 + oy + py) for px, py in pts]
                xs = [p[0] for p in line]
                ys = [p[1] for p in line]
                if max(xs) < -width or min(xs) >= SIZE + width or max(ys) < -width or min(ys) >= SIZE + width:
                    continue
                draw.line(line, fill=colour, width=width)


def save_texture(out_dir, category, texture_id, img, use, tileable=True, alpha=False):
    """Write the PNG and return its manifest entry (avg_color is read back from the saved file)."""
    path = Path(out_dir) / category / (texture_id + ".png")
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format="PNG", optimize=True)
    with Image.open(path) as saved:
        avg = average_hex(saved.convert("RGB"))
    entry = {
        "id": texture_id,
        "category": category,
        "file": "res://assets/textures/library/%s/%s.png" % (category, texture_id),
        "size": [SIZE, SIZE],
        "tileable": tileable,
        "avg_color": avg,
        "seed": seed_for(texture_id),
        "use": use,
    }
    if alpha:
        entry["alpha"] = True
    return entry


def _font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def contact_sheet(entries, lib_dir, out_path, thumb=256, cols=5):
    """Grid of every texture with its id, category and average colour."""
    label_h = 38
    pad = 16
    rows = (len(entries) + cols - 1) // cols
    width = cols * (thumb + pad) + pad
    height = rows * (thumb + label_h + pad) + pad
    sheet = Image.new("RGB", (width, height), (34, 36, 40))
    draw = ImageDraw.Draw(sheet)
    font = _font(14)
    small = _font(11)
    for i, entry in enumerate(entries):
        x = pad + (i % cols) * (thumb + pad)
        y = pad + (i // cols) * (thumb + label_h + pad)
        path = Path(lib_dir) / entry["category"] / (entry["id"] + ".png")
        with Image.open(path) as tile:
            tile = tile.convert("RGBA").resize((thumb, thumb), Image.LANCZOS)
            sheet.paste(tile, (x, y), tile)
        draw.text((x, y + thumb + 4), entry["id"], fill=(235, 235, 235), font=font)
        draw.text((x, y + thumb + 22), "%s  %s" % (entry["category"], entry["avg_color"]),
                  fill=(160, 160, 160), font=small)
    sheet.save(out_path, format="PNG", optimize=True)
