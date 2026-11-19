"""Tileable stone, brick and concrete surfaces."""
from PIL import ImageDraw
from tex_kit import fbm, make_lut, paint, rng_for, save_texture


def build(out_dir):
    entries = []
    for name, dark, light in [('stone_wall',(96,91,81),(177,168,149)), ('brick',(102,55,44),(175,101,76)), ('concrete',(129,128,120),(185,183,171))]:
        rng = rng_for(name)
        img = paint(make_lut([(0,dark),(1,light)]), fbm(rng, [(4,1),(20,.4),(64,.1)]), rng, .05)
        if name != 'concrete':
            d = ImageDraw.Draw(img)
            for y in range(31,512,64):
                d.line((0,y,511,y), fill=dark, width=4)
                offset = 32 if (y // 64) % 2 else 96
                for x in range(offset,512,128):
                    d.line((x,y,x,y+64), fill=dark, width=4)
        entries.append(save_texture(out_dir, 'masonry', name, img, 'Stylized %s.' % name.replace('_', ' ')))
    return entries
