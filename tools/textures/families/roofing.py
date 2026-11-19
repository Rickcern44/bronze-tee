"""Tileable roof and siding surfaces."""
from PIL import ImageDraw
from tex_kit import fbm, make_lut, paint, rng_for, save_texture


def build(out_dir):
    entries=[]
    for name, dark, light, gap in [('roof_shingle',(67,62,59),(124,117,105),64),('siding_white',(168,167,152),(232,228,211),64),('metal_green',(44,87,65),(97,150,103),64)]:
        rng=rng_for(name)
        img=paint(make_lut([(0,dark),(1,light)]), fbm(rng,[(4,1),(16,.3)]),rng,.025)
        d=ImageDraw.Draw(img)
        if name == 'metal_green':
            for x in range(32,512,gap):
                d.line((x,0,x,511),fill=dark,width=3)
        else:
            for y in range(32,512,gap):
                d.line((0,y,511,y),fill=dark,width=3)
                if name == 'roof_shingle':
                    for x in range(32+(64 if (y//gap)%2 else 0),512,128):
                        d.line((x,y,x,y+gap),fill=dark,width=2)
        entries.append(save_texture(out_dir,'roofing',name,img,'Stylized %s.' % name.replace('_',' ')))
    return entries
