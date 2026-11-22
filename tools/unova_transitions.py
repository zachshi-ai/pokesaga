"""Field-script transitions which are not represented by an ordinary zone warp."""
import struct
import numpy as np
from scipy import ndimage
from unova_source import archive

def scripted_fields(src,data,append):
    def nearest(a,pos):
        pos=np.array(pos,dtype=int)-a['origin'];cells=a['coords']
        return cells[np.argmin(abs(cells-pos).sum(axis=1))]
    def add(a,pa,b,pb,name,reciprocal=False):
        x=nearest(a,pa);y=nearest(b,pb);append(a,x,b,y,source=name)
        if reciprocal:append(b,y,a,x,source=name)
    for i,a in data.items():
        for k,(pos,row) in enumerate(zip(a['entries'],a['z']['warps'])):
            if pos is None or row['zone']!=65535:continue
            # Dynamic exits are explicitly named by the opposite doorway.
            for b in data.values():
                for j,r in enumerate(b['z']['warps']):
                    if r['zone']==i and r['warp']==k and b['entries'][j] is not None:
                        p=nearest(b,b['origin']+b['entries'][j])
                        q=nearest(a,a['origin']+pos)
                        append(a,q,b,p,source='native_return_'+str(k))
    if src.era=='bw':
        headers=list(struct.iter_unpack('<BBHHHHH4HHHHHHHHHiii',archive(src.bw,'0/1/2')[0]))
        scripts=archive(src.bw,'0/5/7')
        for i in range(160,165):
            a=data[i];b=scripts[headers[i][4]]
            for event in a['z']['triggers']:
                grid=event['grid']
                if (grid['width'],grid['height'])!=(5,5):continue
                ptr=(event['script']-1)*4
                start=ptr+4+struct.unpack_from('<I',b,ptr)[0]
                match=b.find(struct.pack('<HH',193,i+1),start,start+100)
                if match<0:continue
                dest,x,y=struct.unpack_from('<3H',b,match+2)
                add(a,(grid['x']+2,grid['z']+2),data[dest],(x,y),'quicksand_'+str(event['script']))
        # Each chamber's floor event (script 2) runs its staircase / lift animation;
        # the other end is a return sigil next to the Elite Four trainer (script 3).
        for i in range(140,144):
            a=data[i];trigs={e['script']:e['grid'] for e in a['z']['triggers']}
            if 2 in trigs and 3 in trigs:
                p,q=trigs[2],trigs[3]
                add(a,(p['x'],p['z']),a,(q['x'],q['z']),'elite_lift',True)
    else:
        a,b=data[29],data[488]
        # Both cocoon passages and their two return exits, as named by MapChangeCore.
        add(a,(4,13),b,(15,20),'cocoon',True);add(a,(8,4),b,(9,13),'cocoon',True)
        # At the Giant Chasm the same cave doorway changes to the iced clearing
        # while the frigate is present. It returns to the original clearing later.
        a=data[231];frozen=data[233]['z']['mid']
        a['warps'].sort(key=lambda w: 0 if w['to']['map']==frozen else 1)
        # The game's script moves the player between the icy deck, the stored
        # Pokemon and the surface after the Shadow Triad's three battles.

        # Scripted gangplank and ice staircase on the frozen clearing.
        a=data[233]
        outer=next((p for p,w in zip(a['entries'],a['z']['warps']) if w['zone']==562 and p),None)
        inner=next((p for p,w in zip(a['entries'],a['z']['warps']) if w['zone']==557 and p),None)
        if inner and outer:
            labels,_=ndimage.label(~(a['collision']|a['water']))
            c1,c2=[nearest(a,np.array(p)+a['origin']) for p in (outer,inner)]
            g1=labels[c1[1],c1[0]];g2=labels[c2[1],c2[0]]
            if g1!=g2:
                from scipy.spatial import cKDTree
                first=np.argwhere(labels==g1)[:,::-1];second=np.argwhere(labels==g2)[:,::-1]
                distance,idx=cKDTree(second).query(first,p=1);j=np.argmin(distance)
                add(a,first[j]+a['origin'],a,second[idx[j]]+a['origin'],'ice_stairs',True)
