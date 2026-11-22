"""Bind story appearances to the original actors of the generated Black and Black 2 event banks."""
from pathlib import Path
import json

ROOT=Path(__file__).resolve().parents[1]
COMMON={"红豆杉博士":105,"阿戴克":97,"N":103,"黑暗铁三角":182,"婉龙":93,"越橘":94,"连武":95,"嘉德丽雅":96}
BW={**COMMON,"白露":134,"黑连":7,"妈妈":147,"魁奇思":100,"亚堤":87,"哈奇库":91,"芦荟":86,
    "夏卡":180,"艾莉丝":92,"风露":90,"菊老大":89,"小菊儿":88,"维奥":192,"阿苏拉":191,
    "等离子队队员":[98,99],"真菰":74,"天桐":85,"伯特":178,"寇恩":179,"白露的爸爸":24,"松露":16,
    "联盟向导":32,"培育家":14,"培育屋爷爷":28,"木立":73}
B2={**COMMON,"白露":249,"黑连":223,"妈妈":251,"魁奇思":301,"亚堤":225,"哈奇库":91,
    "夏卡":229,"艾莉丝":[298,355],"风露":228,"菊老大":227,"小菊儿":226,"阿修":291,
    "霍米加":224,"阿克罗玛":250,"维奥":302,"罗德":191,"西子伊":230,"查尔斯":51,
    "等离子队队员":[293,294],"船长":[358,359],"阿修的妹妹":9,"男学生":12,"女学生":16,
    "模特":303,"岩殿居蟹":326,"酷豹":308,"鸣依":162,"北尚":207,"南厦":107,"哈约克":307,"牧场主人":34,"联盟向导":32}
# Dynamic graphics slots and multiple appearances of one model in a single event bank.
LOCAL={
    "u1_fossil_theft":{"木立":2},"u1_badge_8":{"夏卡":4},"u1_light_stone":{"芦荟":13},
    "u1_castle_rises":{"阿戴克":1},"u1_alder":{"阿戴克":2},"u1_alder_repeat":{"阿戴克":2},
    "u1_reshiram":{"雷希拉姆":4},"u1_n_final":{"捷克罗姆":5},"u1_n_zekrom":{"捷克罗姆":3},
    "u2_card":{"等离子队队员":0},"u2_charles":{"查尔斯":8},"u2_maps":{"妈妈":1,"阿修的妹妹":3},"u2_herdier":{"哈约克":10},
    "u2_ranch_rival":{"牧场主人":1},"u2_studio":{"哈奇库":0},"u2_fusion":{"酋雷姆":1},
    "u2_kyurem":{"暗黑酋雷姆":1},"u2_subway":{"鸣依":5},"u1_bianca_home":{"白露的爸爸":0},
}
# Spawned rather than permanently listed: commands ActorNew/ActorWalkRoute from the original field script.
SOURCE_AT={"u2_password":{"控制面板":[12,18]},"u2_first_battle":{"阿修":[36,720]},"u2_grotto":{"白露":[377,438]},"u2_zinzolin":{"维奥":[645,186],"等离子队队员":[645,185],"阿修":[647,186]},"u2_shadow":{"黑暗铁三角":[442,175]},"u2_fusion":{"魁奇思":[17,16]},"u2_kyurem":{"暗黑酋雷姆":[15,18],"魁奇思":[17,16],"N":[17,19]},"u2_rival_road":{"阿修":[14,7]},"u2_waterfall":{"N":[80,47]}}
def compile_cast(book):
    cast={}
    for e in book["events"]:
        era='bw' if e['era']==1 else 'b2'
        p=ROOT/'content/unova_native'/era/(e['map']+'.json')
        if not p.exists():continue
        raw=json.loads(p.read_text());actors=raw.get('unova_cast',[])
        if e['id']=='u2_first_battle' and not actors:
            continue
        names=[e['who'],*e.get('guests',[])]
        if e['who']=='三曜道馆馆主':names=['伯特','寇恩','天桐']
        result={}
        for name in names:
            models=(BW if era=='bw' else B2).get(name,[])
            if isinstance(models,int):models=[models]
            candidates=[n for n in actors if n['model'] in models and n['at']]
            bound=LOCAL.get(e['id'],{}).get(name)
            if bound is not None:
                candidates=[n for n in actors if n['local_id']==bound and n['at']]
            loc=SOURCE_AT.get(e['id'],{}).get(name)
            if loc:
                result[name]={'source_at':loc,'model':models[0] if models else (143 if name=='暗黑酋雷姆' else 0),'source':'field_script'}
            elif candidates:
                result[name]={'local_id':candidates[0]['local_id'],'model':candidates[0]['model'],'source':'event_bank'}
            elif models:result[name]={'model':models[0]}
        if result:cast[e['id']]=result
    return cast

if __name__=='__main__':
    book=json.loads((ROOT/'content/unova_campaign.json').read_text())
    cast=compile_cast(book)
    out=ROOT/'content/unova_campaign_cast.json'
    out.write_text(json.dumps(cast,ensure_ascii=False,indent=1)+'\n')
    from collections import Counter
    print(Counter(b.get('source','adapted') for e in cast.values() for b in e.values()))
