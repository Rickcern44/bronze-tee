"""Transparent course detail decals, kept inside the image boundary."""
from PIL import Image, ImageDraw, ImageFilter
from tex_kit import rng_for, save_texture


def build(out_dir):
    entries=[]
    for name in ('divot','ball_mark','tire_tracks','mow_stripe','tee_box_edge'):
        rng=rng_for(name)
        img=Image.new('RGBA',(512,512),(0,0,0,0)); d=ImageDraw.Draw(img)
        if name == 'divot':
            d.ellipse((93,157,419,354),fill=(81,58,34,175))
            for _ in range(100):
                x=rng.randrange(110,400); y=rng.randrange(180,335)
                d.line((x,y,x+rng.randrange(-10,11),y-rng.randrange(8,28)), fill=(105,135,61,190),width=3)
        elif name == 'ball_mark':
            d.ellipse((173,180,339,330),fill=(72,96,42,160),outline=(126,148,76,190),width=9)
            d.ellipse((222,228,285,290),fill=(93,71,43,190))
        elif name == 'tire_tracks':
            for x in (165,315):
                for y in range(60,450,24):
                    d.line((x-24,y,x+24,y+15),fill=(69,65,45,155),width=9)
                    d.line((x+24,y,x-24,y+15),fill=(69,65,45,155),width=9)
        elif name == 'mow_stripe':
            d.rounded_rectangle((118,30,394,482),radius=65,fill=(154,192,105,80))
            img=img.filter(ImageFilter.GaussianBlur(24))
        else:
            d.line([(42,351),(114,315),(194,309),(274,281),(358,284),(468,230)], fill=(110,147,71,175),width=24)
            d.line([(42,370),(114,334),(194,328),(274,300),(358,303),(468,249)], fill=(67,105,49,135),width=11)
        entries.append(save_texture(out_dir,'decals',name,img,'Transparent %s decal.' % name.replace('_',' '),tileable=False,alpha=True))
    return entries
