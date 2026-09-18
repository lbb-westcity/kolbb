"""Pack Linbin's reviewed ImageGen actions using the existing sprite processor."""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

import prepare_littleblack as art

art.ART = art.ROOT / 'design/linbin'
seq = art.seq
LAYOUT = dict(art.LAYOUT)
LAYOUT.pop('wardrobe')
LAYOUT['normals2'] = seq('heavypunch',[0,1,2,2,4,5]) + seq('heavykick') + seq('crouchpunch') + seq('crouchkick')
LAYOUT['reaction'] = seq('guard',[2,3])+seq('crouchguard',[2,3])+seq('hurt',[0,1,2,2,3])+seq('knockdown',[2,2,2,3,4,5])+seq('roll',[0,1,2,3,4,4,5])+seq('hurt',[0,1])
LAYOUT['specials'] = seq('pat',[0,1,2,2,4,5]) + seq('tea') + seq('throw') + seq('reflect')
LAYOUT['specials2'] = seq('deadline') + seq('throw') + seq('reflect') + seq('idle')


def build(processor):
    names = ['idle'] + [a[0] for a in json.loads((art.ART / 'prompts.json').read_text())['actions']]
    names += ['cup_fx', 'reflect_fx', 'clock_fx']
    missing = [n for n in names if not (art.ART / 'raw-held' / f'{n}.png').exists()]
    for name in names:
        if name not in missing:
            art.process(name, processor)
    if missing:
        print('Awaiting: ' + ', '.join(missing))
        return False
    idle = art.source_frames('idle')
    scale = 148 * idle[0].height / (idle[0].getbbox()[3] - idle[0].getbbox()[1])
    bodies = {n: art.pack_body(art.source_frames(n), scale) for n in names if not n.endswith('_fx')}
    fighters = art.ROOT / 'assets/fighters'
    for group, layout in LAYOUT.items():
        assert len(layout) == 24
        atlas = Image.new('RGBA', (art.CELL[0] * 4, art.CELL[1] * 6))
        for i, (name, frame) in enumerate(layout):
            atlas.paste(bodies[name][frame], (i % 4 * art.CELL[0], i // 4 * art.CELL[1]))
        atlas.save(fighters / f'linbin_{group}.png')
        # Sweater palette is darker than trousers: keep skin, hair and gray pants.
        pixels = np.array(atlas)
        rgb = pixels[:, :, :3].astype(float)
        cloth = (rgb.max(2) - rgb.min(2) < 12) & (rgb.mean(2) >= 24) & (rgb.mean(2) <= 57) & (pixels[:, :, 3] > 0)
        rgb[cloth] *= np.array([.65, 1.5, 1.55])
        pixels[:, :, :3] = np.clip(rgb, 0, 255).astype('uint8')
        Image.fromarray(pixels).save(fighters / f'linbin_{group}_alt.png')
    portrait = bodies['idle'][0]
    top = portrait.getbbox()[1]
    portrait.crop((art.ANCHOR[0]-25, top, art.ANCHOR[0]+25, top+50)).resize((48,48), Image.Resampling.NEAREST).save(art.ROOT / 'assets/ui/linbin_portrait.png')
    for name, size in [('cup',32), ('reflect',96), ('clock',64)]:
        frames = art.source_frames(name+'_fx')
        boxes = [f.getbbox() for f in frames]
        ratio = (size-4)/max(max(b[2]-b[0],b[3]-b[1]) for b in boxes)
        sheet = Image.new('RGBA',(size*3,size*2))
        for i,(frame,box) in enumerate(zip(frames,boxes)):
            cut=frame.crop(box)
            cut=cut.resize((max(1,round(cut.width*ratio)),max(1,round(cut.height*ratio))),Image.Resampling.NEAREST)
            sheet.paste(cut,(i%3*size+(size-cut.width)//2,i//3*size+(size-cut.height)//2))
        sheet.save(art.ROOT / f'assets/props/linbin_{name}.png')
    keys=[g+s for g in LAYOUT for s in ['', '_alt']]
    text='[gd_resource type="SpriteFrames" format=3]\n'
    for key in keys:
        text+=f'[ext_resource type="Texture2D" path="res://assets/fighters/linbin_{key}.png" id="{key}"]\n'
    for key in keys:
        for i in range(24):
            text+=f'\n[sub_resource type="AtlasTexture" id="{key}_{i}"]\natlas = ExtResource("{key}")\nregion = Rect2({i%4*384}, {i//4*224}, 384, 224)\n'
    text+='\n[resource]\nanimations = [\n'
    for key in keys:
        frames=','.join('{ "duration": 1.0, "texture": SubResource("'+key+'_'+str(i)+'") }' for i in range(24))
        text+='{ "name": &"'+key+'", "speed": 60.0, "loop": true, "frames": ['+frames+'] },\n'
    text+=']\nmetadata/foot_anchor = Vector2(192, 208)\n'
    (fighters/'linbin_frames.tres').write_text(text)
    (art.ART/'layout.json').write_text(json.dumps(LAYOUT,indent=2)+'\n')
    contact=Image.new('RGBA',(384*3,224*((len(bodies)+2)//3)),(30,38,48,255))
    for i,frames in enumerate(bodies.values()):
        contact.alpha_composite(frames[3],(i%3*384,i//3*224))
    contact.save(art.ART/'contact.png')
    print('Packed Linbin: 9 atlases + alternate colors, portrait, 3 FX and SpriteFrames.')
    return True


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--processor',type=Path,default=Path.home()/'.codex/skills/generate2dsprite/scripts/generate2dsprite.py')
    raise SystemExit(0 if build(parser.parse_args().processor) else 1)
