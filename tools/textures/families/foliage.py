"""Transparent clusters of stylized leaves."""
import math
from PIL import Image, ImageDraw
from tex_kit import rng_for, save_texture


def build(out_dir):
    entries=[]
    for name, palette in [('leaf_cluster_green',[(79,157,69,255),(143,203,94,255),(47,107,58,255)]),('leaf_cluster_autumn',[(201,143,74,255),(186,83,41,255),(217,174,77,255)])]:
        rng=rng_for(name)
        img=Image.new('RGBA',(512,512),(0,0,0,0)); d=ImageDraw.Draw(img)
        d.line((256,475,256,125),fill=(81,63,40,255),width=8)
        for i in range(34):
            a=rng.uniform(0,math.tau); radius=rng.uniform(15,170)
            x=256+math.cos(a)*radius; y=250+math.sin(a)*radius
            d.line((256,280,x,y),fill=(81,63,40,255),width=3)
            w=rng.randrange(22,43); h=rng.randrange(32,57)
            d.ellipse((x-w,y-h,x+w,y+h),fill=rng.choice(palette))
        entries.append(save_texture(out_dir,'foliage',name,img,'Transparent %s foliage card.' % name.replace('_',' '),tileable=False,alpha=True))
    return entries
