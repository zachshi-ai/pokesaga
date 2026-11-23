"""Use normal controls in an earned regional save to play Alola side quests."""
import argparse
import os
from pathlib import Path
import shutil
import tempfile

from campaign_route import ROOT, read
from test_alola_journey import AlolaRoutes, Player


class SidePlayer(Player):
    def find(self, key):
        row = self.rows[key]
        self.enter(row['map'])
        return next((n for n in self.state['actors'] if n[1]=='alola_side_'+key),None)

    def talk(self,key):
        row=self.rows[key]
        actor=self.find(key)
        assert actor,(key,self.pos,self.state['actors'])
        self.use_at(row['map'],actor[0])
        print('SIDE',key,self.pos,self.state['buttons'][:4],flush=True)

    def saved(self):
        self.do('save')
        if self.result_save:shutil.copyfile(self.save_slot,self.result_save)
        return read(self.save_slot)

    def stage(self,key,choices=()):
        if 'as_'+key in self.state['flags']:return
        if self.rows[key]['action']=='battle' and not self.rows[key].get('rental'):
            self.nurse('alola_center_seafolk')
        self.talk(key)
        for label in choices:assert self.select(label), (key,label,self.state['buttons'])
        if 'as_'+key not in self.state['flags'] and self.rows[key]['action']=='battle':
            self.nurse('alola_center_lanakila')
            current=int(self.state['party'][0][2])
            self.train_at('alola_lanakila', min(100,current+4),'alola_center_lanakila')
            self.nurse('alola_center_lanakila')
            self.talk(key)
        assert 'as_'+key in self.state['flags'], (key,self.state['dialog'],self.state['fights'])
        self.saved()

    def collect(self):
        if self.version.startswith('ultra'):
            self.stage('sticker6')
            assert self.find('sticker6') is None
            assert int(self.saved()['flags']['as_stickers'])>=1
            if 'a_rotom' in self.state['flags']:
                self.do('key_item',item='洛托姆图鉴')
                assert self.select('触碰洛托姆的眼睛')
                label=next(i for i in self.state['bag'] if i.endswith('碰碰'))
                self.do('key_item',item=label)
                assert self.select('使用')
                assert self.saved()['alola_roto']['next']>0
                print('ROTO LOTTO AND ITEM PASS',label,flush=True)
        else:
            self.stage('cube')
            self.stage('core0')
            self.do('key_item',item='基格尔德多面体')
            assert any('传授' in c for c in self.state['buttons'])
            self.do('back')
            assert self.saved()['flags']['as_stock']>=1 and self.find('core0') is None
        print('ALOLA COLLECT JOURNEY PASS',self.version,self.state['steps'],flush=True)

    def hunt(self,key):
        row=self.rows[key]
        flag='as_'+row['group']
        for _ in range(int(row['quota'])*8):
            if flag in self.state['flags']:return
            if self.state['bag'].get('究极球',0)==0:
                if self.version.startswith('ultra'):
                    self.talk('beastshop');assert self.select('购买１０个')
                else:self.talk('spareball')
            if not self.find(key):
                if flag in self.state['flags']:return
                raise AssertionError(key)
            self.do('throw_with',item='究极球',species=row['species'])
            self.talk(key)
            if '靠近' in self.state['buttons']:
                assert self.select('靠近')
            self.do('mode',value='travel')
            self.saved()
        assert flag in self.state['flags'],key

    def hauoli_events(self):
        is_ultra=self.version.startswith('ultra')
        if is_ultra:
            self.stage('hypno_open')
            self.enter('alola_hauoli_police')
            assert all(self.find('hypno'+str(i)) for i in range(3))
            who='hypno0' if self.version.endswith('sun') else 'hypno2'
            self.do('mode',value='train')
            self.talk(who)
            assert self.select('调查这只')
            self.do('mode',value='travel')
            assert 'as_hypno_solved' in self.state['flags']
            assert all(self.find('hypno'+str(i)) is None for i in range(3))
            before=self.state['bag'].get('巨大金珠',0)
            self.stage('hypno_reward')
            assert self.state['bag'].get('巨大金珠',0)==before+1
            if self.find('bear_show'):
                self.stage('bear_show',['观看'])
                self.do('mode',value='train')
                self.stage('bewear',['上前迎战'])
                self.do('mode',value='travel')
                before=self.state['bag'].get('全满药',0)
                self.stage('bear_med')
                assert self.state['bag']['全满药']==before+1
                assert self.find('bear_actor0') is None
                print('HAUOLI BEWEAR SHOW PASS',flush=True)
        version='usum' if is_ultra else 'sm'
        self.stage('ilima_invite'+version,['接受挑战'])
        self.nurse('alola_center_hauoli')
        self.stage('ilima_test'+version)
        assert self.state['bag']['不变之石']>0
        if is_ultra:
            self.stage('ilima_crystal')
            assert self.state['bag']['伊利马的一般Ｚ']==1
            self.do('key_item',item='伊利马的一般Ｚ')
            while self.state['buttons']:self.do('back')
            self.nurse('alola_center_2')
            self.stage('ilima_pedestal',['放回一般Ｚ'])
            saved=self.saved()
            assert saved['flags']['a_trial_guide_outfit'] and self.state['bag'].get('伊利马的一般Ｚ',0)==0
        print('HAUOLI SIDE JOURNEY PASS',self.version,self.state['steps'],self.state['turns'],flush=True)

    def all_collectibles(self):
        ultra=self.version.startswith('ultra')
        if not ultra:self.stage('cube')
        rows=[r for r in self.rows.values() if r['action']=='collect' and (r['kind']=='sticker')==ultra]
        rows.sort(key=lambda r:(r['map'],int(r.get('slot',1))))
        for attempt in range(3):
            pending=[]
            for row in rows:
                key=row['id']
                if 'as_'+key in self.state['flags']:continue
                actor=self.find(key)
                if actor is None:
                    pending.append(key);continue
                self.stage(key)
            if not pending:break
            if ultra:raise AssertionError(pending)
            self.talk('reverse_'+self.version)
            assert self.select('穿过裂隙'),(pending,self.state['dialog'])
        saved=self.saved()
        assert saved['flags']['as_stickers' if ultra else 'as_cells']==100,pending
        if ultra:
            for _ in range(6):self.talk('sticker_gifts')
            assert self.saved()['flags']['as_oak_100']
        else:
            self.talk('machine')
            assert self.select('合成１０％形态')
            assert self.saved()['flags']['as_stock']==90
        print('ALOLA 100 COLLECTIBLES JOURNEY PASS',self.version,self.state['steps'],flush=True)

    def tree(self):
        self.talk('tree_gate')
        assert self.select('青绿')
        assert 'as_tree_gate' in self.state['flags']
        self.nurse('alola_center_seafolk')
        self.talk('tree_desk')
        assert self.select('单打')
        for _ in range(3):
            pick=next(b for b in self.state['buttons'] if 'Lv.' in b)
            self.do('click',label=pick)
        assert self.select('开始下一场')
        assert self.select('暂时休息')
        saved=self.saved()
        assert int(saved['bp'])>=1 and int(saved['alola_tree']['wins'])==1
        print('ALOLA TREE JOURNEY PASS',self.version,self.state['turns'],flush=True)

    def postgame(self):
        assert 'a_credits' in self.state['flags']
        self.nurse('alola_center_seafolk')
        if self.version.startswith('ultra'):
            self.stage('ultra_balls')
            self.hunt('groves0' if self.version.endswith('sun') else 'grovem0')
            for k in ['rr_help','rr_agency','rr_tv','rr_faba','rr_guzma']:self.stage(k)
            self.stage('rr_warp',['月牙','星'])
            self.stage('rr_color',['红','蓝','绿'])
            self.stage('rr_archie')
            self.nurse('alola_center_seafolk')
            self.stage('rr_maxie')
            self.stage('rr_arrows',['北侧','朝楼梯'])
            self.stage('rr_statues',['让它看墙','右侧'])
            for k in ['rr_cyrus','rr_mirror','rr_lysandre']:self.stage(k)
            self.stage('rr_button',['红色按钮'])
            self.nurse('alola_center_seafolk')
            for k in ['rr_ghetsis','rr_colress','rr_giovanni','rr_end']:self.stage(k)
            old=self.saved()['money']
            self.talk('nuggets');assert self.select('卖出')
            assert self.saved()['money']==old+1100000
        else:
            self.stage('card');self.do('key_item',item='谜之卡片')
            while self.state['buttons']:self.do('back')
            for k in ['anabel','ball_lab','ub1']:self.stage(k)
            self.hunt('ub010');self.stage('report1');self.stage('ub2')
            self.hunt('ub02s0' if self.version=='sun' else 'ub02m0');self.stage('report2'+self.version)
            self.nurse('alola_center_8');self.stage('ub3');self.hunt('ub030');self.stage('report3');self.stage('ub4')
            self.hunt('ub04s0' if self.version=='sun' else 'ub04m0');self.stage('report4'+self.version)
            self.nurse('alola_center_seafolk');self.stage('ub5');self.hunt('ub050');self.stage('report5')
            old=self.saved()['money'];self.stage('ub_complete')
            assert self.saved()['money']>=old+1000000
            assert self.find('necrozma')
        saved=self.saved()
        expected={'sun':{793:1,794:2,796:2,798:4,799:1},'moon':{793:1,795:4,796:2,797:2,799:1},'ultra_sun':{806:2},'ultra_moon':{805:2}}[self.version]
        members=list(saved['party'])
        for box in saved.get('boxes',[]):members.extend(box.get('mons',[]) if isinstance(box,dict) else box)
        counts={sid:sum(int(m.get('species_id',0))==sid for m in members if m) for sid in expected}
        assert counts==expected,(counts,expected)
        print('ALOLA POSTGAME JOURNEY PASS',self.version,self.state['steps'],self.state['turns'],flush=True)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--resume',required=True,type=Path)
    ap.add_argument('--result-save',type=Path)
    ap.add_argument('--pack',type=Path)
    ap.add_argument('--godot',default='godot')
    ap.add_argument('--postgame',action='store_true')
    ap.add_argument('--tree',action='store_true')
    ap.add_argument('--hauoli',action='store_true')
    ap.add_argument('--all-collectibles',action='store_true')
    args=ap.parse_args()
    version=read(args.resume)['flags']['a_version']
    with tempfile.TemporaryDirectory(prefix='alola-side-') as tmp:
        folder=Path(tmp)
        save_slot=folder/'save.json'
        shutil.copyfile(args.resume,save_slot)
        game=[args.godot,'--headless','--fixed-fps','60']
        game+=['--main-pack',str(args.pack.resolve())] if args.pack else ['--path',str(ROOT)]
        p=SidePlayer(AlolaRoutes(version),game,dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=tmp),folder)
        try:
            p.save_slot=save_slot;p.result_save=args.result_save
            p.rows={r['id']:r for r in read(ROOT/'content/alola_side.json')['events']}
            p.version=version
            if args.hauoli:p.hauoli_events()
            elif args.all_collectibles:p.all_collectibles()
            elif args.tree:p.tree()
            elif args.postgame:p.postgame()
            else:p.collect()
        finally:p.finish()


if __name__=='__main__':main()
