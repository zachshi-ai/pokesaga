"""Use a copy of an earned USUM save to revisit Seafolk and solve the three Sandy Cave item routes."""
import argparse,json,os,shutil,tempfile
from collections import deque
from pathlib import Path
from campaign_route import ROOT,VECTORS,read
from test_alola_journey import Player,AlolaRoutes

def cave(p):
    m=p.routes.fields['alola_sandy_cave'].data;mid=m['id'];phy=m['physics'];w,h=m['size']
    walls={(x,y)for y,row in enumerate(phy['collision']) for x,v in enumerate(row)if v}
    water={(x,y)for y,row in enumerate(phy['water']) for x,v in enumerate(row)if v}
    blocked={tuple(o['at']) for o in m['objects'] if o['kind'] in ['rock','boulder']}
    pit=next((x,y)for y,row in enumerate(phy['hole'])for x,v in enumerate(row)if v)
    blocked.add(pit);blocked.update(tuple(r['at'])for r in m['warps'])
    def reach(goal):
        start=p.pos[1:];q=deque([start]);via={start:None}
        while q:
            xy=q.popleft()
            if xy==goal:break
            for d,(dx,dy,*_) in VECTORS.items():
                nxt=xy[0]+dx,xy[1]+dy
                if not (0<=nxt[0]<w and 0<=nxt[1]<h) or nxt in walls|blocked or nxt in via:continue
                q.append(nxt);via[nxt]=xy,d
        assert goal in via,(start,goal)
        route=[];step=goal
        while step!=start:
            prev,d=via[step];route.append((d,step));step=prev
        last=start;batch=[]
        def flush():
            if batch:
                p.do('walk',legs=batch.copy());assert p.pos==tuple(batch[-1][1]),(p.pos,batch[-1],p.state['buttons']);batch.clear()
        for d,xy in reversed(route):
            if xy in water and last not in water:
                flush();p.do('face',dir=d)
                if '冲浪' in p.state['buttons']:p.select('冲浪')
                assert p.select('好'),p.state
                assert p.pos[1:]==xy,(p.pos,xy)
            else:batch.append([d,[mid,*xy]])
            last=xy
        flush()
    for goal in [(16,13),(16,8),(16,3),(28,14),(28,20)]:
        reach(goal)
        if goal==(16,8):
            p.do('face',dir='u');assert 'hole:alola_sandy_cave:16,6' in p.state['flags'],p.state['dialog']
            blocked.remove((16,7));blocked.remove(pit)
        elif goal==(28,14):
            p.do('face',dir='d');assert 'a_sandy_reef' in p.state['flags'],p.state['buttons'];blocked.remove((28,15))
        else:
            p.do('face',dir='u')
    assert all('a_sandy_'+item in p.state['flags'] for item in ['BIG_PEARL','TM24','LIGHT_CLAY'])
    assert any(n.startswith('阿罗拉招式学习器24') for n in p.state['bag'])
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('source',type=Path);ap.add_argument('--godot',default='godot');ap.add_argument('--pack',type=Path);args=ap.parse_args()
    d=read(args.source);v=d['flags']['a_version'];assert v.startswith('ultra') and d['flags']['a_ride_machamp']
    with tempfile.TemporaryDirectory(prefix='alola-cave-trip-') as temp:
        folder=Path(temp);shutil.copy2(args.source,folder/'save.json')
        cmd=[args.godot,'--headless','--fixed-fps','60']+(['--main-pack',str(args.pack.resolve())]if args.pack else ['--path',str(ROOT)])
        p=Player(AlolaRoutes(v),cmd,dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=temp),folder)
        try:
            p.enter('alola_seafolk')
            # Walk both directions over the original wooden pier, all the way to the eastern boat.
            mid='alola_seafolk'
            for x,y in [(10,12),(30,12),(46,13),(30,12),(10,12)]:p.go({(mid,x,y)})
            for place in ['center_seafolk','seafolk','seafolk_restaurant','seafolk','center_seafolk','seafolk','big_wave_beach','sandy_cave']:p.enter('alola_'+place)
            cave(p);p.do('save');reloaded=read(folder/'save.json')
            assert all(reloaded['flags']['a_sandy_'+k] for k in ['BIG_PEARL','TM24','LIGHT_CLAY'])
            print('ALOLA FIELD TRIP PASS',v,'steps',p.state['steps'],'machine, pearl and clay retained',flush=True)
        finally:
            if p.process.poll() is None:p.do('quit');p.process.wait(timeout=20)
if __name__=='__main__':main()
