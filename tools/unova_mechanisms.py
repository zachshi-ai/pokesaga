"""Stations and switches for Unova's field gimmicks, projected onto their original islands."""
from collections import defaultdict
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree

KINDS={'striaton':'curtain','nacrene':'bookshelf','castelia':'honey','nimbasa':'coaster','driftveil':'lift','mistralton':'cannon','icirrus':'ice','opelucid':'dragon','humilau':'lily','virbank':'stage','aspertia':'court'}
def platforms(a):
    mid=a['z']['mid']
    if '_gym_' not in mid and mid!='unova_nimbasa_old_gym':return []
    era='bw' if '_bw_' in mid else 'b2'
    town=mid.split('_gym_')[-1] if '_gym_' in mid else 'nimbasa'
    kind=KINDS.get(town,'lift')
    if era=='b2':kind={'castelia':'cocoon','mistralton':'wind','nimbasa':'runway'}.get(town,kind)
    z=a['z'];grid,n=ndimage.label(~(a['collision']|a['water']));origin=a['origin']
    def coord(p):return tuple(np.array(p,dtype=int)-origin)
    def label(p):
        x,y=p;return int(grid[y,x]) if 0<=x<grid.shape[1] and 0<=y<grid.shape[0] else 0
    groups={i:np.argwhere(grid==i)[:,::-1] for i in range(1,n+1)}
    stops={label(p) for p in a['entries'] if p is not None};stops.add(label(a['spawn']))
    triggers=[]
    for event in z['triggers']:
        g=event.get('grid');pos=coord((g['x'],g['z'])) if g else ()
        if pos and label(pos):triggers.append((int(event['script']),label(pos),pos));stops.add(label(pos))
    for npc in z['npcs']:
        if 'grid' not in npc:continue
        g=npc['grid'];pos=coord([g['x'],g['z']])
        if label(pos):stops.add(label(pos))
    stops.update(k for k,q in groups.items() if len(q)>=15);stops.discard(0)
    if len(stops)<2:return []
    foyer=a['entries'][0] if a['entries'] else a['spawn'];start=label(foyer) if foyer is not None else 0
    if not start:start=label(a['spawn'])
    switches=defaultdict(list)
    for script,group,pos in sorted(triggers):switches[group].append(pos)
    used={tuple(p) for p in a['entries'] if p}
    used.update(tuple(p) for p in a['anchors'].values());used.add(tuple(a['spawn']))
    for npc in z['npcs']:
        g=npc.get('grid')
        if g:used.add(coord([g['x'],g['z']]))
    used.update(p for _,_,p in triggers)
    def station(i,hint):
        spots=groups[i]
        candidates=spots[[tuple(p) not in used for p in spots]]
        if not len(candidates):candidates=spots
        p=tuple(int(x) for x in candidates[np.argmin(np.sum(abs(candidates-hint),axis=1))])
        used.add(p);return list(p)
    routes=[]
    def link(i,j,pa,pb):
        first=station(i,pa);second=station(j,pb);entry={'from':first,'to':second,'kind':kind,'index':len(routes)}
        if switches[i]:
            entry['switch_at']=list(map(int,switches[i][0]))
        routes.append(entry)
    if kind=='coaster' and z['i']==63:
        # The four colored track switches carry original map scripts 3..6, in puzzle order.
        sequence=[start]+[g for s,g,p in sorted(triggers) if 3<=s<=6]
        for i,j in zip(sequence,sequence[1:]):
            if i==j:continue
            switched=switches[i][0] if switches[i] else foyer
            link(i,j,switched,switches[j][0])
        return routes
    visited={start}
    while stops-visited:
        best=None
        for i in sorted(visited):
            if i not in groups:continue
            for j in sorted(stops-visited):
                dist,idx=cKDTree(groups[i]).query(groups[j],p=1)
                m=int(np.argmin(dist));value=(float(dist[m]),i,j)
                if best is None or value<best[0]:best=(value,groups[i][idx[m]],groups[j][m])
        if best is None:break
        _,i,j=best[0];link(i,j,best[1],best[2]);visited.add(j)
    return routes
