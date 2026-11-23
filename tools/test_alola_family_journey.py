"""Walk the family Meowth and Alolan Vulpix quests in a real Ultra champion save."""
import argparse
from datetime import date, timedelta
import json
import os
from pathlib import Path
import shutil
import tempfile

from campaign_route import ROOT, read
from test_alola_journey import AlolaRoutes
from test_alola_side_journey import SidePlayer


def first_day(p):
    before=p.state['bag'].get('PP 提升剂',0)
    p.stage('mom_meowth',['聚宝功','报恩'])
    assert p.state['bag']['PP 提升剂']==before+1
    p.do('key_item',item='PP 提升剂')
    assert p.select(p.state['party'][0][0])
    choice=next(b for b in p.state['buttons'] if '/' in b and '已加满' not in b)
    p.do('click',label=choice)
    assert p.state['bag'].get('PP 提升剂',0)==before
    assert p.saved()['party'][0]['pp_bonus']
    while '‹ 返回' in p.state['buttons']:p.do('back')
    assert p.find('vulpix_cornered') and p.find('vulpix_recovered') is None
    p.stage('vulpix_rescue')
    assert p.find('vulpix_cornered') is None
    before=p.state['bag'].get('银色王冠',0)
    p.talk('vulpix_cap')
    assert p.state['bag'].get('银色王冠',0)==before and 'as_vulpix_cap' not in p.state['flags']
    p.talk('malasada_hauoli')
    before=p.saved()['money']
    n=p.state['bag'].get('大马拉萨达',0)
    assert p.select('买一份')
    assert p.state['bag']['大马拉萨达']==n+1 and p.saved()['money']==before-350
    p.talk('vulpix_care')
    assert p.select('先收起来') and p.state['bag']['大马拉萨达']==n+1
    p.talk('vulpix_care')
    assert p.select('喂给六尾')
    assert p.state['bag'].get('大马拉萨达',0)==n and p.saved()['flags']['as_vulpix_visits']==1
    p.talk('vulpix_care')
    assert p.saved()['flags']['as_vulpix_visits']==1
    print('MEOWTH PP UP RECEIVED AND USED; PANIOLA RESCUE, PURCHASE, FEED AND SAME-DAY LOCK PASS',flush=True)


def second_day(p):
    n=p.state['bag'].get('银色王冠',0)
    p.stage('vulpix_cap')
    assert p.state['bag']['银色王冠']==n+1 and p.find('vulpix_cap') is None
    p.talk('vulpix_care')
    assert p.saved()['flags']['as_vulpix_visits']==2
    p.talk('vulpix_care')
    assert 'as_vulpix_care' not in p.state['flags'] and p.find('vulpix_recovered') is None
    print('NEXT DAY SILVER CAP AND SECOND CARE VISIT PASS',flush=True)


def third_day(p):
    p.stage('vulpix_care')
    assert p.find('vulpix_care') is None
    p.talk('vulpix_recovered')
    assert p.select('摸摸它')
    p.talk('vulpix_recovered')
    assert p.select('跟它玩')
    print('RECOVERED VULPIX AT MOUNT LANAKILA PASS',p.pos,flush=True)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--resume',required=True,type=Path)
    ap.add_argument('--godot',default='godot')
    ap.add_argument('--pack',type=Path)
    ap.add_argument('--result-save',type=Path)
    a=ap.parse_args()
    version=read(a.resume)['flags']['a_version']
    assert version.startswith('ultra')
    rows={r['id']:r for r in read(ROOT/'content/alola_side.json')['events']}
    cmd=[a.godot,'--headless','--fixed-fps','60']
    cmd+=['--main-pack',str(a.pack.resolve())] if a.pack else ['--path',str(ROOT)]
    with tempfile.TemporaryDirectory(prefix='alola-family-') as tmp:
        follow=Path(tmp)/'follow.json'
        shutil.copyfile(a.resume,follow)
        for number,day in enumerate((first_day,second_day,third_day)):
            with tempfile.TemporaryDirectory(prefix='alola-family-day-') as episode:
                folder=Path(episode)
                slot=folder/'save.json'
                archive=read(follow)
                if number:
                    # Age only the two in-game date stamps to simulate a night's wait.
                    yesterday=(date.today()-timedelta(days=1)).isoformat()
                    for key in ('as_vulpix_last_day','as_vulpix_rescue_day'):
                        if key in archive['flags']:archive['flags'][key]=yesterday
                slot.write_text(json.dumps(archive,ensure_ascii=False))
                p=SidePlayer(AlolaRoutes(version),cmd,dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=episode),folder)
                p.save_slot=slot;p.result_save=follow;p.rows=rows;p.version=version
                try:day(p);p.saved()
                finally:p.finish()
        if a.result_save:shutil.copyfile(follow,a.result_save)
        print('ALOLA FAMILY SIDE JOURNEY PASS',version,flush=True)


if __name__=='__main__':main()
