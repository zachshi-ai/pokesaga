"""Play an Alola release from a fresh shared save, walking, talking, using items and battling normally."""
import argparse
from collections import deque
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from campaign_route import ROOT,Field,Routes,read
from test_kalos_journey import KalosPlayer
from test_unova_journey import UnovaRoutes
from test_kanto_journey import league_heal

class AlolaRoutes(UnovaRoutes):
    def __init__(self,version):
        Routes.__init__(self,())
        self.regions=('alola',)
        self.flags=set(); self.components={}; self.avoid=set()
        self.version=version
        self.access=read(ROOT/'content/alola_map_access.json')
        self.book=read(ROOT/'content/alola_campaign.json')[version]
        for p in (ROOT/'content/regions/alola/maps').glob('*.json'):
            d=read(p)
            if not d.get('alola_native'):continue
            f=Field(d,d['physics']);f.holes=set();self.fields[d['id']]=f

    def projection(self,dest):
        mid=dest.get('map')
        rule=self.access.get(mid,{})
        if ('versions' in rule and self.version not in rule['versions']) or ('require' in rule and rule['require'] not in self.flags):return None
        req=self.book['gates'].get(mid,{}).get('require')
        if req and req not in self.flags:return None
        if mid in ['alola_altar','alola_moone'] and (mid=='alola_altar')!=self.version.endswith('sun'):return None
        return Routes.projection(self,dest)

class Player(KalosPlayer):
    def field_moves(self):
        self.routes.flags=set(self.state['flags'])
        return frozenset()  # The campaign walk prefers bridges and public ferries.

    def legends(self):
        mid='alola_center_lanakila'
        self.nurse(mid)
        shop=next(r for r in self.state['actors'] if r[3])
        self.use_at(mid,shop[0])
        if '购买道具' in self.state['buttons']:self.select('购买道具')
        self.do('shop',item='高级球',amount=max(0,25-self.state['bag'].get('高级球',0)))
        self.do('back')
        for key in ('a_mount_necrozma','a_nebby'):
            if key in self.state['flags']:continue
            scene=next(e for e in self.routes.book['events'] if e['id']==key)
            self.do('mode',value='travel')
            self.scene(scene)
        for sid in (800,791 if self.routes.version.endswith('sun') else 792):
            assert sid in self.state['dex']
        item='奈克洛索尔合体器' if self.routes.version.endswith('sun') else '奈克洛露奈合体器'
        self.do('key_item',item=item)
        assert self.select('合体 ·'),self.state['buttons']
        if self.state['buttons'] and '算了，不学' in self.state['buttons']:self.select('算了，不学')
        for _ in range(4):
            if not self.state['panels']:break
            self.do('back')
        self.do('save');saved=read(self.save_slot)
        nec=next(m for m in saved['party'] if m.get('species_id')==800)
        partner=nec['fused_part'];assert partner['species_id'] in (791,792)
        self.do('key_item',item=item)
        assert self.select('分离 ·')
        for _ in range(4):
            if not self.state['panels']:break
            self.do('back')
        self.do('save');after=read(self.save_slot)
        assert partner in after['party'] and all(not m.get('fused_part') for m in after['party'])
        if self.result_save:shutil.copyfile(self.save_slot,self.result_save)
        print('LEGEND CAPTURE AND REVERSIBLE FUSION PASS',item,flush=True)

    def defend(self):
        earlier=read(self.save_slot)['flags'].get('a_defenses',0)
        self.prepare_event('a_league')
        for tries in range(5):
            for room,name in [('league','enter'),('e4_ghost','ghost'),('e4_fighting','fighting'),('e4_flying','flying'),('e4_rock','rock'),('champion_room','challenger')]:
                key='a_title_'+name
                if key in self.state['flags'] or (name=='enter' and 'a_title_active' in self.state['flags']):continue
                mid='alola_'+room
                self.enter(mid)
                row=next(r for r in self.state['actors'] if r[1]==key)
                league_heal(self)
                self.use_at(mid,row[0])
                print('TITLE DEFENSE',key,row[2],self.state['fights'],flush=True)
                if any(f[3]=='b' for f in self.state['fights']):
                    self.recover(key)
                    break
            self.do('save')
            save=read(self.save_slot)
            if save['flags'].get('a_defenses',0)>earlier:
                assert save['flags']['a_title_last']=='哈乌' if not earlier else True
                assert save['flags']['a_credits'] and save['hall_of_fame']['alola'] and 'a_title_active' not in save['flags']
                if self.result_save:shutil.copyfile(self.save_slot,self.result_save)
                print('TITLE DEFENSE PASS',save['flags']['a_title_last'],save['flags']['a_defenses'],flush=True)
                return
        raise RuntimeError('Title Defense could not finish after recovery')

    def prepare_event(self,key):
        plan={'a_school_intro':('1',13,'hauoli'),'a_normal':('2',17,'2'),'a_hala':('2',20,'2'),'a_gladion':('4',24,'paniola'),
              'a_water':('5',27,'5'),'a_fire':('6',30,'royal'),'a_olivia':('8',35,'8'),'a_electric':('10',39,'malie'),
              'a_ghost':('12',43,'tapu'),'a_nanu':('16',49,'16'),'a_lusamine':('16',53,'16'),'a_hapu':('wilds',62,'seafolk'),'a_dragon':('wilds',62,'seafolk'),
              'a_ultra_necrozma':('wilds',70,'seafolk'),'a_gladion_last':('wilds',65,'seafolk'),'a_league':('lanakila',74,'lanakila')}
        if key in ('a_hapu','a_ultra_necrozma','a_league'):
            slot=next((i for i,m in enumerate(self.state['party']) if m[1] in (728,729,730)),None)
            if slot is not None:
                if slot:self.do('lead',slot=slot)
                if self.state['held'][0]!='WATERIUM_Z':self.do('equip',slot=0,item='水Ｚ')
        if key in plan:
            road,level,c=plan[key]
            self.nurse('alola_center_'+c)
            self.train_at('alola_'+road,level,'alola_center_'+c)
        if key=='a_z_lesson':
            self.do('equip',slot=0,item='一般Ｚ')
            assert self.state['held'][0]=='NORMALIUM_Z'
        if key=='a_league':
            c='alola_center_lanakila'
            self.nurse(c)
            counter=next((r for r in self.state['actors'] if r[3]),None)
            if counter:
                self.use_at(c,counter[0])
                if '购买道具' in self.state['buttons']:self.select('购买道具')
                for item,num in [('活力碎片',7),('全满药',12)]:
                    self.do('shop',item=item,amount=max(0,num-self.state['bag'].get(item,0)))
                self.do('back')
        self.do('mode',value='travel')

    def recover(self,key):
        flags=self.state['flags']
        course,clinic=next((road,center) for flag,road,center in [
            ('a_gladion_last','lanakila','lanakila'),('a_flute1','wilds','seafolk'),('a_ghost','16','16'),
            ('a_electric','12','tapu'),('a_nihilego','10','malie'),('a_fire','8','8'),('a_water','6','royal'),
            ('a_sail','4','paniola'),('a_school','2','2'),('a_started','1','hauoli')] if flag in flags)
        slot=next((i for i,m in enumerate(self.state['party']) if m[1] in (728,729,730)),None)
        if slot is not None and slot>0:self.do('lead',slot=slot)
        clinic='alola_center_'+clinic
        self.nurse(clinic)
        self.train_at('alola_'+course,min(100,int(self.state['party'][0][2])+4),clinic)
        print('RETRAINED AFTER LOSS',key,self.state['party'][0][:3],flush=True)

    def scene(self,e):
        key=e['id'];mid=e['map']
        if any('battle' in a for a in e['steps']):league_heal(self)
        self.enter(mid)
        row=next((r for r in self.state['actors'] if r[1]==key),None)
        assert row,(key,mid,self.state['actors'])
        capture=next((a for a in e['steps'] if 'alola_capture' in a),None)
        if capture:
            ball='大师球' if self.state['bag'].get('大师球',0) else '高级球'
            self.do('throw_with',item=ball,species=capture['alola_capture'])
        self.use_at(mid,row[0])
        picks=[]
        for a in e['steps']:
            if a.get('alola_starter'):picks.append('球球海狮')
            elif 'alola_quiz' in a:picks.append(a['alola_quiz']['choices'][a['alola_quiz']['correct']])
            elif 'alola_circuit' in a:picks.extend(circuit_inputs(a['alola_circuit']))
            elif 'alola_poipole' in a:picks.append('一起出发')
        for text in picks:
            if self.state['buttons']:assert self.select(text),(key,self.state['buttons'],text)
        if key=='a_royal':
            for _ in range(100):
                if key in self.state['flags']:break
                opts=[b for b in self.state['buttons'] if b!='返回']
                assert opts,(key,self.state['dialog'])
                self.select(opts[0])
        if key not in self.state['flags'] and capture:
            for retry in range(5):
                if not self.state['bag'].get('高级球',0):break
                print('CAPTURE RETRY',key,self.state['fights'],self.state['bag'].get('高级球',0),flush=True)
                self.enter(mid)
                row=next(r for r in self.state['actors'] if r[1]==key)
                self.do('throw_with',item='高级球',species=capture['alola_capture'])
                self.use_at(mid,row[0])
                if key in self.state['flags']:break
        if key not in self.state['flags']:
            if any(f[3]=='b' for f in self.state['fights']):return False
            raise RuntimeError((key,self.pos,self.state['dialog'],self.state['buttons']))
        if key=='a_route3_hau':
            assert self.state['z_inputs']>0 and 'a_z_practiced' in self.state['flags'],('no Z move selected in combat',self.state['held'])
            print('Z MOVE INPUTS',self.state['z_inputs'],flush=True)
        self.do('save')
        if self.result_save:shutil.copyfile(self.save_slot,self.result_save)
        if self.checkpoints:shutil.copyfile(self.save_slot,self.checkpoints/(key+'.json'))
        print('PROGRESS',key,self.pos,'steps',self.state['steps'],'turns', self.state['turns'],flush=True)
        return True

def circuit_inputs(stage):
    blocks=[(0,1,4,3),(1,2,5,4),(3,4,7,6),(4,5,8,7)]
    labels=['左上磁铁','右上磁铁','左下磁铁','右下磁铁'];result=[];start=(0,3,6)
    goals=[(1,4,7),(3,4,5),(0,4,8)]
    for goal in goals[stage:stage+1]:
        if stage:start=goals[stage-1]
        todo=deque([(start,[])]); seen={start}
        while todo:
            state,path=todo.popleft()
            if state==goal:result+=path;break
            for i,b in enumerate(blocks):
                nxt=tuple(sorted(b[(b.index(c)+1)%4] if c in b else c for c in state))
                if nxt not in seen:todo.append((nxt,path+[labels[i]]));seen.add(nxt)
        start=goal
    return result

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--godot',default='godot');ap.add_argument('--pack',type=Path)
    ap.add_argument('--version',choices=['sun','moon','ultra_sun','ultra_moon'],default='sun')
    ap.add_argument('--transfer',choices=['boxed','carried'],default='boxed')
    ap.add_argument('--legends',action='store_true')
    ap.add_argument('--title-defense',action='store_true')
    ap.add_argument('--foreign-starter',action='store_true');ap.add_argument('--resume',type=Path)
    ap.add_argument('--result-save',type=Path);ap.add_argument('--checkpoints',type=Path)
    ap.add_argument('--stop-at',default='a_credits')
    args=ap.parse_args()
    if args.checkpoints:args.checkpoints.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='alola-journey-') as tmp:
        folder=Path(tmp);env=dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=tmp)
        cmd=[args.godot,'--headless','--fixed-fps','60']+(['--main-pack',str(args.pack.resolve())] if args.pack else ['--path',str(ROOT)])
        if args.resume:shutil.copyfile(args.resume,folder/'save.json')
        if args.foreign_starter and not args.resume:
            subprocess.run([*cmd,'--script',str(ROOT/'tools/test_first_chapter.gd'),'--','play'],cwd=folder,env=env,check=True)
        startup=[] if args.resume else ['--',*(() if args.foreign_starter else ('new-alola',)),'alola-'+args.transfer,args.version]
        p=Player(AlolaRoutes(args.version),cmd,env,folder,startup)
        p.result_save=args.result_save;p.checkpoints=args.checkpoints;p.save_slot=folder/'save.json'
        try:
            for _ in range(18):
                if args.stop_at in p.state['flags']:break
                for e in p.routes.book['events']:
                    k=e['id']
                    if e.get('optional') or k in p.state['flags']:continue
                    print('NEXT',k,p.pos,flush=True)
                    p.prepare_event(k)
                    if not p.scene(e):
                        p.recover(k)
                        break
                    if k==args.stop_at:break
                if args.stop_at in p.state['flags']:break
            assert args.stop_at in p.state['flags']
            d=read(p.save_slot);assert d['flags']['a_version']==args.version and d['chapters']['alola']==args.transfer
            if args.stop_at=='a_credits':
                assert len(d['regional_badges']['alola'])==4 and d['hall_of_fame']['alola']
                if not args.resume:assert d['map']=='alola_home'
                assert ('a_ultra_necrozma' in d['flags'])==args.version.startswith('ultra')
            if args.legends:p.legends()
            if args.title_defense:p.defend()
            print('ALOLA JOURNEY PASS',args.version,args.transfer,args.stop_at,flush=True)
        finally:
            if p.process.poll() is None:p.do('quit');p.process.wait(timeout=15)

if __name__=='__main__':main()
