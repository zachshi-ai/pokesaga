#!/usr/bin/env python3
"""Play Kalos X or Y, starting on the title screen and using ordinary field, bag and battle controls."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from campaign_route import ROOT, Field, Routes, read
from test_hoenn_journey import EmeraldPlayer
from test_kanto_journey import league_heal
from test_unova_journey import UnovaPlayer, UnovaRoutes


class KalosRoutes(UnovaRoutes):
    """Route across the native zone grid, including disjoint rooms and local story gates."""
    def __init__(self):
        Routes.__init__(self, ())
        self.regions = ('kalos',)
        self.flags = set()
        self.components = {}
        self.town_states = read(ROOT/'content/kalos_geosenge.json')
        self.town_phase = None
        self.avoid = set()
        self.rules = read(ROOT/'content/kalos_campaign.json')['gates']
        for p in (ROOT/'content/regions/kalos/maps').glob('*.json'):
            d=read(p)
            if not d.get('kalos_native'):continue
            field=Field(d,d['physics'])
            field.holes=set()
            self.fields[d['id']]=field
            self.avoid.update((d['id'],*o['at']) for o in d.get('objects',[]) if o.get('kind')=='kalos_ice_switch')

    def set_flags(self, flags):
        self.flags = flags
        if 'k_last_lysandre' in flags or 'k_weapon' in flags:
            phase = 'crater'
        elif 'k_two_buttons' in flags:
            phase = 'weapon'
        else:
            phase = 'stones'
        if phase == self.town_phase:
            return
        field = self.fields['kalos_geosenge']
        field.grid['collision'] = [int(cell) for row in self.town_states[phase]['collision'] for cell in row]
        self.town_phase = phase
        self.edges.cache_clear()
        self.components.clear()

    def projection(self, dest):
        keys = self.rules.get(dest.get('map'),{}).get('require',[])
        if not set(keys)<=self.flags or not set(dest.get('kalos_requires',[]))<=self.flags:return None
        return Routes.projection(self,dest)


class KalosPlayer(EmeraldPlayer):
    train_at=UnovaPlayer.train_at
    teach=UnovaPlayer.teach

    def do(self, action, **opts):
        state=super().do(action,**opts)
        if action=='walk':
            for answer in ('皮卡丘','小箭雀','冷水猴','二号剪影'):
                if answer in state['buttons']:
                    state=super().do('click',label=answer)
                    print('PRISM QUIZ',answer,state['pos'],flush=True)
                    break
        return state

    def field_moves(self):
        flags=set(self.state['flags'])
        self.routes.set_flags(flags)
        machines={15:(1,1),19:(2,4),57:(3,3),70:(4,2),127:(5,8)}
        return frozenset(mid for mon in self.state['party'] for mid in mon[5] if mid in machines
                         and {f'k_hm_{machines[mid][0]}',f'k_badge_{machines[mid][1]}'}<=flags)

    def nurse(self, mid):
        self.enter(mid)
        npc=next((row for row in self.state['actors'] if row[6]),None)
        assert npc,('no nurse',mid)
        self.use_at(mid,npc[0])
        assert all(mon[3]==mon[4] for mon in self.state['party']),('healing',mid,self.state['dialog'])

    def gym_guard(self,mid,number):
        flag=f'k_trainer_{number}'
        if flag in self.state['flags']:return
        row=next(r for r in self.state['actors'] if r[10]==flag)
        self.use_at(mid,row[0])
        assert flag in self.state['flags'],(flag,self.state['dialog'])

    def snowbelle(self):
        mid='kalos_gym_snowbelle'
        self.enter(mid)
        objects={o['color']:o['at'] for o in self.routes.fields[mid].data['objects'] if o['kind']=='kalos_ice_switch'}
        self.gym_guard(mid,169)
        for color,angle,guardian in [('pink',2,169),('blue',3,32),('pink',1,169),('yellow',1,31),('green',3,168)]:
            self.gym_guard(mid,guardian)
            for _ in range(5):
                if self.state.get('ice',{}).get('k_ice_turn_'+color,0)==angle:break
                self.use_at(mid,objects[color])
            assert self.state.get('ice',{}).get('k_ice_turn_'+color,0)==angle,color
            print('ICE SWITCH',color,angle,self.state['ice'],[f for f in self.state['flags'] if 'ice_bridge' in f],flush=True)
        assert 'k_ice_bridge_last' in self.state['flags']
        print('SNOWBELLE ICE BRIDGES PASS',flush=True)

    def prepare(self, event):
        key=event['id']
        # Gain battle experience in each currently accessible area before the major fights.
        training={'k_skates':('3',11,'santalune'),'k_badge_1':('3',15,'santalune'),
            'k_route7_tag':('7_west',21,'camphrier'),'k_badge_2':('8',29,'cyllage'),
            'k_ring_rival':('11',34,'shalour'),'k_badge_4':('12',39,'coumarine'),
            'k_plant':('12',43,'coumarine'),'k_badge_6':('14',47,'laverre'),
            'k_anistar_rival':('15',51,'dendemille'),'k_lysandre_lab':('15',55,'anistar'),
            'k_lysandre_hq':('15',57,'anistar'),'k_badge_8':('20',63,'snowbelle'),
            'k_road_rival':('20',69,'snowbelle'),'k_league':('20',73,'snowbelle')}
        if key=='k_skates':self.nurse('kalos_center_santalune')
        if key in training:
            road,level,center=training[key]
            self.train_at('kalos_'+road,level,'kalos_center_'+center)
        if key=='k_league':
            self.nurse('kalos_center_snowbelle')
            counter=next(row for row in self.state['actors'] if row[3])
            self.use_at('kalos_center_snowbelle',counter[0])
            if '购买道具' in self.state['buttons']:self.select('购买道具')
            for item,count in [('活力碎片',10),('全满药',15)]:
                self.do('shop',item=item,amount=max(0,count-self.state['bag'].get(item,0)))
            self.do('back')
        if key=='k_badge_3':
            mid='kalos_gym_shalour'
            self.enter(mid)
            for trainer in (83,84,146,147):
                flag=f'k_trainer_{trainer}'
                if flag in self.state['flags']:continue
                npc=next(row for row in self.state['actors'] if row[10]==flag)
                self.use_at(mid,npc[0])
                assert flag in self.state['flags'],(flag,self.state['dialog'])
        if key=='k_badge_8':self.snowbelle()
        if key=='k_monorail':self.teach(3)
        if key=='k_league_gate':self.teach(5)
        if key=='k_legend':
            assert self.state['bag'].get('大师球',0)>0,('master ball from factory',self.state['bag'])
            self.do('throw_with',item='大师球',species=717 if self.version=='y' else 716)
        else:self.do('mode',value='travel')
        if any('battle' in act for act in event['steps']):league_heal(self)

    def scene(self, event):
        key=event['id'];mid=event['map']
        for attempt in range(6):
            self.enter(mid)
            if key in self.state['flags']:break
            npc=next((r for r in self.state['actors'] if r[1]==key),None)
            assert npc,('missing actor',key,mid,[(r[1],r[2]) for r in self.state['actors']])
            self.use_at(mid,npc[0])
            options={'k_starter_gift':'呱呱泡蛙','k_sycamore':'小火龙','k_fossil':'颚之化石',
                     'k_legend':'换下' if self.legend_party else '留在电脑','k_two_buttons':'蓝色按钮' if self.version=='x' else '红色按钮','k_lucario':'一起旅行'}
            if self.state['buttons']:
                label=options.get(key)
                assert label and self.select(label),(key,self.state['buttons'])
            if key in self.state['flags']:break
            if any(r[3]=='b' for r in self.state['fights']):
                print('WHITEOUT',key,self.pos,flush=True)
                if key.startswith('k_elite_') or key=='k_diantha':return False
                if key=='k_factory':
                    # The second Grunt's Manectric can sweep a Greninja-led team.
                    self.train_at('kalos_14',self.state['party'][0][2]+2,'kalos_center_laverre')
                self.prepare(event)
                continue
            raise RuntimeError((key,self.pos,self.state['dialog'],self.state['buttons']))
        assert key in self.state['flags'],key
        self.do('save')
        if self.result_save:shutil.copyfile(self.save_slot,self.result_save)
        if self.checkpoints:shutil.copyfile(self.save_slot,self.checkpoints/(key+'.json'))
        print('PROGRESS',key,self.pos,'steps',self.state['steps'],'turns',self.state['turns'],flush=True)
        return True

    def opowers(self):
        locations=['zone_71','zone_18','zone_52','zone_162','zone_26','center_shalour','center_coumarine',
                   'center_laverre','center_dendemille','center_anistar','zone_42','center_snowbelle','hotel']
        def talk_to(mid,name):
            self.enter(mid)
            at=next(r[0] for r in self.state['actors'] if r[2]==name)
            self.use_at(mid,at)
        for place in locations:
            talk_to('kalos_'+place,'欧斯先生')
            assert not any(r[2]=='欧斯先生' for r in self.state['actors'])
            print('O-POWER',place,self.state['dialog'][-1],flush=True)
        self.do('start')
        for name in ['工具','Ｏ力量','恢复与收获','经验值力','Lv.1']:
            assert self.select(name),(name,self.state['buttons'])
        self.do('save')
        memory=read(self.save_slot)
        assert memory['flags']['k_o_practice']['exp'][0]==1 and memory['kalos_o_energy']['units']==6
        while memory.get('kalos_style',0)<190:
            talk_to('kalos_lumiose_museum','美术馆导览员')
            assert self.select('听导览')
            self.do('save')
            memory=read(self.save_slot)
        talk_to('kalos_zone_125','欧斯先生')
        self.do('save')
        final=read(self.save_slot)
        assert len([key for key,value in final['flags'].items() if key.startswith('k_o_got_') and value])==15
        if self.result_save:shutil.copyfile(self.save_slot,self.result_save)
        if self.checkpoints:shutil.copyfile(self.save_slot,self.checkpoints/'o_powers_complete.json')
        print('O-POWER TOUR PASS 17 powers, style',final['kalos_style'],flush=True)

    def run(self,args,folder):
        self.result_save=args.result_save
        self.checkpoints=args.checkpoints
        self.save_slot=folder/'save.json'
        self.version=args.version
        self.legend_party=args.legend_party
        self.events=read(ROOT/'content/kalos_campaign.json')['events']
        targets=[e for e in self.events if e['route'] or e['id'].startswith('k_elite_')]
        for retry in range(6):
            for event in targets:
                key=event['id']
                if key in self.state['flags']:continue
                print('NEXT',key,self.pos,flush=True)
                self.prepare(event)
                if not self.scene(event):break
                if key==args.stop_at:break
            if args.stop_at in self.state['flags']:break
        assert args.stop_at in self.state['flags'],('last stage',self.pos,self.state['flags'][-5:])
        d=read(self.save_slot)
        if args.stop_at=='k_parade':
            assert d['map']=='kalos_home_2f' and d['flags']['k_champion'] and d['flags']['k_last_lysandre']
            assert d['flags']['k_legend_caught']==(717 if self.version=='y' else 716)
            assert len(d['regional_badges']['kalos'])==8 and d['hall_of_fame']['kalos']
            assert d['chapters']['kalos']==args.transfer and d['flags']['k_version']==args.version and d['flags']['k_mega_trial_used']
            if args.opowers:self.opowers()
            if args.legend_party:
                assert any(int(mon.get('species_id',0))==d['flags']['k_legend_caught'] for mon in d['party'])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',default='godot')
    parser.add_argument('--pack',type=Path)
    parser.add_argument('--resume',type=Path)
    parser.add_argument('--legacy',type=Path,help='arrive for the first time with a pre-existing save and party')
    parser.add_argument('--foreign-starter',action='store_true',help='first play a new Kanto save through its first badge')
    parser.add_argument('--opowers',action='store_true',help='after the League collect all O-Powers via normal hotel, center and café visits')
    parser.add_argument('--legend-party',action='store_true',help='when all twelve slots are occupied, swap the legendary into the party')
    parser.add_argument('--result-save',type=Path)
    parser.add_argument('--checkpoints',type=Path)
    parser.add_argument('--transfer',choices=('boxed','carried'),default='boxed')
    parser.add_argument('--version',choices=('x','y'),default='x')
    parser.add_argument('--stop-at',default='k_parade')
    args=parser.parse_args()
    if args.checkpoints:args.checkpoints.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='pokesaga-kalos-walk-') as tmp:
        folder=Path(tmp)
        env=dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=tmp,GODOT_SILENCE_ROOT_WARNING='1')
        source=['--main-pack',str(args.pack.resolve())] if args.pack else ['--path',str(ROOT)]
        godot=[args.godot,'--headless','--fixed-fps','60',*source]
        if args.resume or args.legacy:shutil.copyfile(args.resume or args.legacy,folder/'save.json')
        if args.foreign_starter:
            if args.resume or args.legacy:parser.error('--foreign-starter requires a new save')
            subprocess.run([*godot,'--script',str(ROOT/'tools/test_first_chapter.gd'),'--','play'],cwd=folder,env=env,check=True)
        startup=[] if args.resume else ['--',*(() if args.legacy or args.foreign_starter else ('new-kalos',)),
            'kalos-'+args.transfer,args.version]
        p=KalosPlayer(KalosRoutes(),godot,env,folder,startup)
        try:
            p.run(args,folder)
            print('KALOS JOURNEY PASS',args.version,args.transfer,args.stop_at,flush=True)
        finally:
            p.do('quit')
            if p.process.wait(timeout=10)!=0:raise RuntimeError('Godot exited unsuccessfully')


if __name__=='__main__':main()
