"""Compile Crystal's reception areas and synthesize loopable Game Boy radio arrangements from score data."""
import argparse
from pathlib import Path
import json
import re
import subprocess
import tempfile
import wave
import numpy as np
from gen_johto import camel_to_id

ROOT=Path(__file__).resolve().parents[1]
TRACKS="profoakspokemontalk pokemonmarch pokemonlullaby buenaspassword ruinsofalphradio viridiancity bicycle pokeflutechannel lakeofragerocketradio rockettheme gamecorner pokemoncenter".split()
RATE=22050
NOTES=("C_","C#","D_","D#","E_","F_","F#","G_","G#","A_","A#","B_")

def sequence(text,channel,tempo):
    code=[];labels={};scope="";channels={}
    for line in text.splitlines():
        raw=line.split(';')[0].strip()
        if not raw:continue
        if raw.endswith(':'):
            lab=raw.rstrip(':')
            if not lab.startswith('.'):scope=lab
            labels[scope+lab if lab.startswith('.') else lab]=len(code)
        else:
            op,_,args=raw.partition(' ')
            fields=[s.strip() for s in args.split(',')];code.append((op,fields,scope))
            if op=='channel':channels.setdefault(int(fields[0]),fields[1])
    pc=labels[channels[channel]];speed=12;volume=9;envelope=0;octave=3;duty=2;stack=[];repeat={};events=[];panning=[1,1]
    for _ in range(24000):
        cmd,args,scope=code[pc];pc+=1
        def dest(name):return labels[scope+name if name.startswith('.') else name]
        if cmd=='sound_call':stack.append(pc);pc=dest(args[0])
        elif cmd=='sound_ret':
            if not stack:break
            pc=stack.pop()
        elif cmd=='sound_loop':
            times=int(args[0])
            if not times:break
            remaining=repeat.get(pc,times)-1
            if remaining:
                repeat[pc]=remaining;pc=dest(args[1])
            else:repeat.pop(pc,None)
        elif cmd=='tempo':tempo=int(args[0])
        elif cmd=='octave':octave=int(args[0])
        elif cmd=='duty_cycle':duty=int(args[0])
        elif cmd in ('note_type','volume_envelope'):
            if cmd=='note_type':speed=int(args[0])
            volume=int(args[-2]);envelope=int(args[-1])
        elif cmd=='drum_speed':speed=int(args[0])
        elif cmd=='stereo_panning':panning=[1 if x=='TRUE' else .28 for x in args]
        elif cmd in ('note','rest','drum_note'):
            length=speed*int(args[-1])*tempo/(256*59.7275)
            pitch=NOTES.index(args[0])+12*(octave+2) if cmd=='note' else 0
            events.append((cmd,length,pitch,volume,envelope,duty,panning))
    return events

def render(path,dest):
    text=path.read_text()
    if path.stem=="rockettheme":text+="\n"+(path.parent/"lookrocket.asm").read_text()
    tempo=int(re.search(r'\btempo (\d+)',text)[1])
    channels=int(re.search(r'\bchannel_count (\d+)',text)[1])
    seq=[sequence(text,i,tempo) for i in range(1,channels+1)]
    duration=max(sum(e[1] for e in channel) for channel in seq)
    mix=np.zeros((round(duration*RATE)+2,2));noise=np.random.default_rng(12)
    for index,events in enumerate(seq):
        now=0
        for kind,secs,pitch,volume,envelope,duty,pan in events:
            end=now+secs
            a,b=round(now*RATE),round(end*RATE);now=end
            if kind=='rest' or b<=a:continue
            t=np.arange(b-a)/RATE
            if kind=='drum_note':tone=noise.uniform(-1,1,len(t))*np.exp(-t*22)*.26
            else:
                phase=(t*440*2**((pitch-69)/12))%1
                tone=1-4*np.abs(phase-.5) if index==2 else np.where(phase<[.125,.25,.5,.75][duty],.5,-.5)
                if index<2:
                    gain=np.full(t.shape,float(volume)/15)
                    if envelope:
                        step=np.floor(t*64/abs(envelope))/15
                        gain=np.clip(gain-step if envelope>0 else gain+step,0,1)
                    tone=tone*gain
                else:tone=tone*.55
            tone*=np.minimum(1,t*1000)*np.minimum(1,(secs-t)*350)
            for c in range(2):mix[a:b,c]+=tone*pan[c]
    mix*=.93/max(.1,float(np.max(np.abs(mix))))
    with tempfile.TemporaryDirectory() as temp:
        wav=Path(temp)/'out.wav'
        with wave.open(str(wav),'wb') as out:
            out.setparams((2,2,RATE,0,'NONE','not compressed'));out.writeframes((mix*32767).astype('<i2').tobytes())
        subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(wav),'-c:a','vorbis','-strict','experimental','-q:a','2',str(dest)],check=True)

def import_data(source):
    header=(source/'constants/landmark_constants.asm').read_text().split('DEF KANTO_LANDMARK')[0]
    johto=set(re.findall(r'const (LANDMARK_\w+)',header))|{'LANDMARK_FAST_SHIP'}
    areas={}
    for line in (source/'data/maps/maps.asm').read_text().splitlines():
        if not line.lstrip().startswith('map '):continue
        fields=[x.strip() for x in line.strip()[4:].split(',')]
        key='johto_'+camel_to_id(fields[0]);land=fields[3];areas[key]=[land.removeprefix('LANDMARK_'),land in johto,fields[5]=='FALSE']
    path=ROOT/'content/regions/johto/radio.json';path.write_text(json.dumps(areas,separators=(',',':'))+'\n')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);args=p.parse_args()
    import_data(args.source)
    for name in TRACKS:render(args.source/'audio/music'/(name+'.asm'),ROOT/'assets/audio/bgm'/('crystal_'+name+'.ogg'))
