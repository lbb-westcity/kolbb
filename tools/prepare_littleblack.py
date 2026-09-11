"""Pack reviewed ImageGen action grids into KOLBB's existing SpriteFrames format.

Uses the generate2dsprite processor for cleanup/QC; production resampling is
nearest-neighbor from its cleaned source so the arcade pixels stay sharp.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path
from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'design/littleblack'
CELL = (384, 224)
ANCHOR = (192, 208)
GROUPS = ['core','normals','specials','air','locomotion','reaction','performance','normals2','specials2','wardrobe']

def seq(name, indices=None):
    if indices is None:
        indices=[0,1,2,2,3,5] if name in ['heavykick','airpunch','airkick','crouchkick','shoulder'] else range(6)
    return [(name, i) for i in indices]

LAYOUT = {
 'wardrobe': seq('undress')+seq('shortskick')+seq('dress')+seq('idle'),
 'core': seq('idle')+seq('walk')+seq('crouch',[3,4,5])+seq('jump',[1,2,4])+seq('guard',[0,2,3])+seq('hurt',[0,1,2]),
 'locomotion': seq('backwalk')+seq('run')+seq('backstep',[0,2,3,5])+seq('crouch',[3,4,5])+seq('jump',[1,2,4,5])+seq('idle',[0]),
 'reaction': seq('guard',[2,3])+seq('crouchguard',[2,3])+seq('hurt',[0,1,2,2,3])+seq('knockdown',[1,2,3,3,4,5])+seq('roll',[0,1,2,3,4,4,5])+seq('hurt',[0,1]),
 'performance': seq('intro')+seq('victory')+seq('max',[1,2,3,4])+seq('eat',[2,3])+seq('poop',[1,2,3])+seq('laugh',[1,2,3]),
 'normals': seq('punch')+seq('kick')+seq('crouchpunch')+seq('crouchkick'),
 'normals2': seq('heavypunch')+seq('heavykick')+seq('crouchpunch')+seq('crouchkick'),
 'air': seq('airpunch')+seq('airkick')+seq('airpunch')+seq('airkick'),
 'specials': seq('basketball')+seq('shoulder')+seq('throw')+seq('sonic'),
 'specials2': seq('dance',[0,0,1,2,3,4,5,5])+seq('throw')+seq('sonic')+seq('idle',[0,1,2,3]),
}

def process(name, processor):
    source=ART/'raw-held'/f'{name}.png'
    dest=ART/'processed'/name
    if (dest/'pipeline-meta.json').exists() and (dest/'pipeline-meta.json').stat().st_mtime >= source.stat().st_mtime and not json.loads((dest/'pipeline-meta.json').read_text()).get('edge_touch_frames'):
        return
    dest.mkdir(parents=True,exist_ok=True)
    regrid(source,dest/'aligned-input.png')
    subprocess.run([sys.executable,str(processor),'process','--input',str(dest/'aligned-input.png'),
        '--target','asset' if name.endswith('_fx') else 'player','--mode','custom_grid',
        '--rows','2','--cols','3','--cell-size','224','--fit-scale','.75',
        '--align','center' if name.endswith('_fx') else 'feet','--shared-scale',
        '--component-mode','all' if name.endswith('_fx') else 'largest',
        '--trim-border','0','--edge-clean-depth','0','--edge-touch-margin','2',
        '--reject-edge-touch','--output-dir',str(dest)],check=True,stdout=subprocess.DEVNULL)

def regrid(source, output):
    # As in prepare_art.gd, find real empty gutters before fixed-grid slicing.
    raw=Image.open(source).convert('RGBA')
    raw.putalpha(raw.getchannel('A').point(lambda value: 255 if value>=128 else 0))
    a=np.array(raw);rgb=a[:,:,:3].astype(float)
    background=(rgb[:,:,0]>120)&(rgb[:,:,2]>110)&(rgb[:,:,1]<np.minimum(rgb[:,:,0],rgb[:,:,2])*.63)
    occupied=(~background)&(a[:,:,3]>0)
    def boundaries(mask,count):
        length=len(mask);empty=np.where(~mask)[0];gaps=[]
        for values in np.split(empty,np.where(np.diff(empty)>1)[0]+1):
            if len(values)>=4: gaps.append((int(values[0])+int(values[-1]))//2)
        result=[0]
        for i in range(1,count):
            ideal=length*i/count
            candidates=[g for g in gaps if abs(g-ideal)<length/count*.42]
            assert candidates, ('No safe gutter',source,i)
            result.append(min(candidates,key=lambda g:abs(g-ideal)))
        return result+[length]
    ys=boundaries(occupied.any(axis=1),2)
    frames=[]
    for row in range(2):
        xs=boundaries(occupied[ys[row]:ys[row+1]].any(axis=0),3)
        for col in range(3):
            tile=raw.crop((xs[col],ys[row],xs[col+1],ys[row+1]))
            mask=occupied[ys[row]:ys[row+1],xs[col]:xs[col+1]]
            yy,xx=np.where(mask)
            assert len(xx), ('Empty pose',source,row,col)
            assert xx.min()>0 and yy.min()>0 and xx.max()<tile.width-1 and yy.max()<tile.height-1, ('Clipped source',source,row,col)
            frames.append(tile.crop((int(xx.min()),int(yy.min()),int(xx.max())+1,int(yy.max())+1)))
    # Same cell geometry across every action, without resizing or drawing artwork.
    w=raw.width//3;h=raw.height//2
    sheet=Image.new('RGBA',(w*3,h*2),(255,0,255,255))
    for i,tile in enumerate(frames):
        assert tile.width<=w-4 and tile.height<=h-4, ('Pose needs wider source grid',source,i)
        sheet.paste(tile,((i%3)*w+(w-tile.width)//2,(i//3)*h+h-8-tile.height))
    sheet.save(output)

def source_frames(name):
    raw=Image.open(ART/'processed'/name/'raw-sheet-clean.png').convert('RGBA')
    w,h=raw.width//3,raw.height//2
    return [raw.crop(((i%3)*w,(i//3)*h,(i%3+1)*w,(i//3+1)*h)) for i in range(6)]

def pack_body(frames, normalized_scale):
    result=[]
    for frame in frames:
        box=frame.getbbox()
        assert box and box[0]>=2 and box[1]>=2 and box[2]<=frame.width-2 and box[3]<=frame.height-2, ('raw cell boundary',box)
        scale=normalized_scale/frame.height
        cut=frame.crop(box)
        foot=frame.crop((0,box[3]-12,frame.width,box[3])).getbbox()
        foot_x=(foot[0]+foot[2])/2
        cut=cut.resize((max(1,round(cut.width*scale)),max(1,round(cut.height*scale))),Image.Resampling.NEAREST)
        x=ANCHOR[0]+round((box[0]-foot_x)*scale);y=ANCHOR[1]-cut.height
        assert x>=2 and x+cut.width<=CELL[0]-2 and y>=2, ('packed cell boundary',x,y,cut.size)
        out=Image.new('RGBA',CELL)
        out.paste(cut,(x,y))
        result.append(out)
    return result

def build(processor):
    names=['idle']+[item[0] for item in json.loads((ART/'prompts.json').read_text())['actions']]
    missing=[n for n in names if not (ART/'raw-held'/f'{n}.png').exists()]
    for name in names:
        if name not in missing: process(name,processor)
    if missing:
        print('Awaiting action sheets: '+', '.join(missing));return False
    idle=source_frames('idle')
    normalized_scale=148*idle[0].height/(idle[0].getbbox()[3]-idle[0].getbbox()[1])
    bodies={n:pack_body(source_frames(n),normalized_scale) for n in names if not n.endswith('_fx')}
    fighters=ROOT/'assets/fighters'
    for group,layout in LAYOUT.items():
        assert len(layout)==24,(group,len(layout))
        atlas=Image.new('RGBA',(CELL[0]*4,CELL[1]*6))
        for i,(name,frame) in enumerate(layout): atlas.paste(bodies[name][frame],((i%4)*CELL[0],(i//4)*CELL[1]))
        atlas.save(fighters/f'littleblack_{group}.png')
        # Mirror costume: neutral gray cloth becomes muted steel blue; skin/racket stay unchanged.
        a=np.array(atlas);rgb=a[:,:,:3].astype(float)
        mask=(rgb.max(2)-rgb.min(2)<15)&(rgb.mean(2)>35)&(rgb.mean(2)<190)&(a[:,:,3]>0)
        rgb[mask]*=np.array([.72,.94,1.25]);a[:,:,:3]=np.clip(rgb,0,255).astype('uint8')
        Image.fromarray(a).save(fighters/f'littleblack_{group}_alt.png')
    portrait=bodies['idle'][0]
    box=portrait.getbbox()
    portrait=portrait.crop((ANCHOR[0]-25,box[1],ANCHOR[0]+25,box[1]+50)).resize((48,48),Image.Resampling.NEAREST)
    portrait.save(ROOT/'assets/ui/littleblack_portrait.png')
    for name,size in [('ball',32),('sonic',192),('shoulder',96),('trousers',48)]:
        frames=source_frames(name+'_fx');boxes=[f.getbbox() for f in frames]
        max_dim=max(max(b[2]-b[0],b[3]-b[1]) for b in boxes)
        scale=(size-4)/max_dim
        sheet=Image.new('RGBA',(size*3,size*2))
        for i,(f,b) in enumerate(zip(frames,boxes)):
            cut=f.crop(b);cut=cut.resize((max(1,round(cut.width*scale)),max(1,round(cut.height*scale))),Image.Resampling.NEAREST)
            sheet.paste(cut,((i%3)*size+(size-cut.width)//2,(i//3)*size+(size-cut.height)//2))
        sheet.save(ROOT/f'assets/props/littleblack_{name}.png')
    text='[gd_resource type="SpriteFrames" format=3]\n\n'
    keys=[g+s for g in GROUPS for s in ['', '_alt']]
    for key in keys: text+=f'[ext_resource type="Texture2D" path="res://assets/fighters/littleblack_{key}.png" id="{key}"]\n'
    for key in keys:
        for i in range(24): text+=f'\n[sub_resource type="AtlasTexture" id="{key}_{i}"]\natlas = ExtResource("{key}")\nregion = Rect2({i%4*384}, {i//4*224}, 384, 224)\n'
    text+='\n[resource]\nanimations = [\n'
    for key in keys:
        text+='{ "name": &"'+key+'", "speed": 60.0, "loop": true, "frames": ['
        text+=','.join('{ "duration": 1.0, "texture": SubResource("'+key+'_'+str(i)+'") }' for i in range(24))+'] },\n'
    text+=']\nmetadata/foot_anchor = Vector2(192, 208)\n'
    (fighters/'littleblack_frames.tres').write_text(text)
    (ART/'layout.json').write_text(json.dumps(LAYOUT,indent=2)+'\n')
    # Native-size contact sheet is a review artifact, not source art.
    contact=Image.new('RGBA',(384*3,224*((len(bodies)+2)//3)),(30,38,48,255))
    for i,(name,frames) in enumerate(bodies.items()): contact.alpha_composite(frames[3],((i%3)*384,(i//3)*224))
    contact.save(ART/'contact.png')
    print('Packed little black: 10 atlases + alternate colors, portrait, 4 FX, SpriteFrames.')
    return True

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--processor',type=Path,default=Path.home()/'.codex/skills/generate2dsprite/scripts/generate2dsprite.py')
    args=parser.parse_args()
    sys.exit(0 if build(args.processor) else 1)
