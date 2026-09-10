"""Original deterministic arcade foley synthesis; no samples or external packages added."""
import math,wave
from pathlib import Path
import numpy as np
out=Path(__file__).resolve().parents[1]/'assets/audio';out.mkdir(exist_ok=True)
sr=44100;rng=np.random.default_rng(410)
def save(name,y,peak=.22):
    y=np.asarray(y,dtype=float); y=np.tanh(y)
    y*=peak/max(.0001,np.max(np.abs(y)))
    fade=min(128,len(y)//2);y[:fade]*=np.linspace(0,1,fade);y[-fade:]*=np.linspace(1,0,fade)
    with wave.open(str(out/(name+'.wav')),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(sr);f.writeframes((y*32767).astype('<i2').tobytes())
def tone(freq,duration,decay=10):
    t=np.arange(int(sr*duration))/sr
    return (np.sin(2*np.pi*freq*t)+.2*np.sin(2*np.pi*freq*2*t))*np.exp(-decay*t)
def noise(duration,decay=16):
    t=np.arange(int(sr*duration))/sr
    return rng.normal(0,.35,len(t))*np.exp(-decay*t)
def impact(freq,duration):
    t=np.arange(int(sr*duration))/sr
    return .8*np.sin(2*np.pi*(freq*t+freq*.018*(1-np.exp(-t*60))))*np.exp(-t*24)+noise(duration,45)
for name,f,d in [('light',145,.16),('block',450,.13),('land',64,.18),('hit',93,.2),('stamp',80,.27),('folder',210,.18),('poop',110,.25),('clash',540,.15)]: save(name,impact(f,d))
for name,f,d in [('move',650,.055),('confirm',880,.14),('back',330,.13),('coin',1320,.26),('stock',990,.36),('pickup',1100,.22),('burger',410,.16),('pizza',700,.16),('talk',270,.19),('denied',180,.12)]: save(name,tone(f,d,12))
for name,d in [('punch',.10),('kick',.16),('roll',.22),('papers',.32),('whip',.13)]:
    y=noise(d,8); y=np.convolve(y,np.ones(7)/7,'same');save(name,y)
for name,f,d in [('jump',220,.2),('max',170,.6),('super',85,.7),('summon',43,.7),('room',130,.42),('capture',120,.25),('break',560,.3),('slam',52,.4),('ko',65,.8),('round',660,.28),('fight',800,.25)]:
    t=np.arange(int(sr*d))/sr
    y=np.sin(2*np.pi*(f*t+90*t*t))*np.exp(-t*6)+noise(d,16)*.4;save(name,y)
# A composed D-minor victory cadence and an unobtrusive final-20s percussion layer.
notes=[62,65,69,74,72,69,77,74]
y=np.zeros(sr*5)
for i,midi in enumerate(notes):
    n=tone(440*2**((midi-69)/12),1.1,4);j=int(i*.38*sr);y[j:j+len(n)]+=n*.32
save('victory',y,.17)
y=np.zeros(sr*8)
for i in range(32):
    n=impact(72 if i%4==0 else 290,.11)*(.6 if i%4==0 else .14)
    j=int(i*.25*sr);y[j:j+len(n)]+=n
save('urgency',y,.12)
print('Generated',len(list(out.glob('*.wav'))),'original sound files')
