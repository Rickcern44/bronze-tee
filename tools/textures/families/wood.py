"""Tileable stylized timber surfaces."""
from PIL import ImageDraw
from tex_kit import fbm, make_lut, paint, rng_for, save_texture, draw_strokes, pick_colour


def build(out_dir):
    entries = []
    for name, colors, spacing in [
        ('boardwalk_planks', ((92,60,40),(163,118,76)), 64),
        ('bridge_planks', ((66,46,34),(128,91,59)), 85),
        ('fence_wood', ((112,81,56),(177,140,98)), 51),
    ]:
        rng = rng_for(name)
        img = paint(make_lut([(0, colors[0]), (1, colors[1])]), fbm(rng, [(4, 1), (16, .3)]), rng, .025)
        draw_strokes(img, rng, 4000, (15, 90), (1, 2), 0, .03, pick_colour([colors[0], colors[1]]))
        draw = ImageDraw.Draw(img)
        for y in range(spacing // 2, 512, spacing):
            draw.line((0,y,511,y), fill=colors[0], width=3)
            draw.line((0,y+3,511,y+3), fill=colors[1], width=1)
        entries.append(save_texture(out_dir, 'wood', name, img, 'Stylized %s.' % name.replace('_', ' ')))
    return entries
