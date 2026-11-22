"""Bind playable Crystal side events to their original object, including displaced room actors."""
import argparse
import json
import re
from pathlib import Path
from gen_johto import camel_to_id, snap, nearest_free
from johto_warps import place_warps

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = {
    "cal_desk": ("TrainerHouseB1F","SPRITE_RECEPTIONIST","训练大厅接待员"),
    "cal": ("TrainerHouseB1F","SPRITE_CHRIS","卡尔"),
    "bargain": ("GoldenrodUnderground","BargainMerchantScript","廉价店老板"),
    "herbal": ("GoldenrodUnderground","BitterMerchantScript","草药婆婆"),
    "resale": ("GoldenrodDeptStore2F","GoldenrodDeptStore2FClerk1Script","百货店员"),
    "lake_elder": ("LakeOfRage","LakeOfRageGrampsScript","湖边的老人"),
    "lake_scholar": ("LakeOfRage","LakeOfRageSuperNerdScript","湖边的研究者"),
    "lake_visitor": ("LakeOfRage","LakeOfRageCooltrainerFScript","湖边的旅行者"),
    "karp": ("LakeOfRageMagikarpHouse","MagikarpLengthRaterScript","鲤鱼王测量大师"),
    "den_rival": ("DragonsDenB1F","DragonsDenB1FRivalScript","阿银"),
    "bill_sister": ("BillsFamilysHouse","BillsYoungerSisterScript","正辉的妹妹"),
    "game_tm": ("GoldenrodGameCorner","GoldenrodGameCornerTMVendorScript","招式奖品柜台"),
    "game_mon": ("GoldenrodGameCorner","GoldenrodGameCornerPrizeMonVendorScript","宝可梦奖品柜台"),
    "celadon_coins": ("CeladonGameCorner","CeladonGameCornerClerkScript","代币柜台"),
    "lottery": ("RadioTower1F", "RadioTower1FLuckyNumberManScript", "幸运号码主持人"),
    "roof_sale": ("GoldenrodDeptStoreRoof", "GoldenrodDeptStoreRoofClerkScript", "特卖会店员"),
    "bill_home": ("BillsFamilysHouse", "BillScript", "正辉"),
    "bill_visit": ("EcruteakPokecenter1F", "SPRITE_BILL", "正辉"),
    "shuckie": ("ManiasHouse", "ManiaScript", "壶壶的主人"),
    "kenya": ("Route35GoldenrodGate", "RandyScript", "送信的警卫"),
    "letter": ("Route31", "Route31MailRecipientScript", "等信的男子"),
    "kiyo": ("MountMortarB1F", "MountMortarB1FKiyoScript", "空手道王信彦"),
    "lapras": ("UnionCaveB2F", "UnionCaveLapras", "拉普拉斯"),
    "grandpa": ("BillsHouse", "BillsGrandpa", "正辉的爷爷"),
    "older": ("GoldenrodUnderground", "OlderHaircutBrotherScript", "理发师哥哥"),
    "younger": ("GoldenrodUnderground", "YoungerHaircutBrotherScript", "理发师弟弟"),
    "daisy": ("BluesHouse", "DaisyScript", "娜娜美"),
    "week_tm": ("GoldenrodDeptStore5F", "GoldenrodDeptStore5FReceptionistScript", "招式学习器接待员"),
    "moomoo": ("Route39Barn", "MoomooScript", "生病的大奶罐"),
    "dairy": ("Route39Farmhouse", "PokefanM_DairyFarmer", "牧场主人"),
    "snore": ("Route39Farmhouse", "PokefanF_SnoreFarmer", "牧场主的妻子"),
    "claw": ("NationalPark","NationalParkTeacher1Script","长椅旁的老师"),
    "king": ("SlowpokeWellB2F","SlowpokeWellB2FGymGuideScript","地下的研究员"),
    "glasses": ("DarkCaveBlackthornEntrance","DarkCaveBlackthornEntrancePharmacistScript","洞窟中的男子"),
    "curse": ("CeladonMansionRoofHouse","CeladonMansionRoofHousePharmacistScript","屋顶的说书人"),
    "steel_wing": ("Route28SteelWingHouse","Celebrity","隐居的艺人"),
    "roar": ("Route32","Route32RoarTMGuyScript","练习吼叫的男子"),
    "seed": ("Route32","Route32CooltrainerMScript","32号道路的训练家"),
    "headbutt": ("IlexForest","IlexForestHeadbuttGuyScript","撞树的男子"),
    "tutor": ("GoldenrodCity","MoveTutorScript","招式教学者"),
}
SIBLINGS = [
    ("Route37","Sunny","日曜日七弟","磁铁"), ("Route40","Monica","月曜日长女","锐利鸟嘴"),
    ("Route29","Tuscany","火曜日次女","粉红丝带"), ("LakeOfRage","Wesley","水曜日三哥","黑带"),
    ("Route36","Arthur","木曜日四弟","硬石头"), ("Route32","Frieda","金曜日五妹","毒针"),
    ("BlackthornCity","Santos","土曜日六弟","诅咒之符"),
]
for n,(room,script,name,item) in enumerate(SIBLINGS):
    SCRIPTS[f"sibling_{n}"]=(room,script+"Script",name)

def build(source):
    maps={}
    species={r['key']:r['id'] for r in json.loads((ROOT/'content/species.json').read_text())}
    trades={}
    for row in (source/'data/events/npc_trades.asm').read_text().splitlines():
        if not row.lstrip().startswith('npctrade TRADE_'):continue
        _,want,offer,nick,dv1,dv2,item,otid,ot,gender=[w.strip().strip('"') for w in row.split(',')]
        ot=ot.lower()
        srcs=[p for p in (source/'maps').glob('*.asm') if 'trade NPC_TRADE_'+ot.upper()+'\n' in p.read_text()]
        assert len(srcs)==1
        p=srcs[0]
        before=p.read_text().split('trade NPC_TRADE_'+ot.upper())[0]
        script=re.findall(r'^(\w+):',before,re.M)[-1]
        key='trade_'+ot
        SCRIPTS[key]=(p.stem,script,ot.upper())
        trades[key]=[species[want],species[offer],nick,item,int(otid),ot.upper(),gender.endswith('FEMALE'),int(dv1[1:],16),int(dv2[1:],16)]
    for key,(label,script,name) in SCRIPTS.items():
        mid='johto_'+camel_to_id(label)
        orig=(source/'maps'/(label+'.asm')).read_text()
        rows=[line.split(';')[0].strip().split('object_event ',1)[1].strip().split(',') for line in orig.splitlines() if line.strip().startswith('object_event ')]
        index=next(i for i,r in enumerate(rows) if r[11].strip()==script or r[2].strip()==script)
        grid=json.loads((ROOT/'content/emerald_maps'/(mid+'.json')).read_text())
        warps=[{'at8':[int(x),int(y)], 'to':target,'idx':int(idx)} for x,y,target,idx in re.findall(r'^\s*warp_event\s+(\d+),\s*(\d+),\s*(\w+),\s*(-?\d+)',orig,re.M)]
        taken={tuple(p) for p in place_warps(grid,warps)}
        for row in rows[:index+1]:
            pos=snap(grid,list(map(int,row[:2])),want_door=False)
            if tuple(pos) in taken:pos=nearest_free(grid['collision'],pos,taken) or pos
            taken.add(tuple(pos))
        actor={'at':pos}
        maps.setdefault(mid,[]).append({'at':actor['at'],'actor':key,'name':name})
    tree_maps={m.lower():pool.lower() for m,pool in re.findall(r'^\s*treemon_map (\w+),\s*TREEMON_SET_(\w+)',(source/'data/wild/treemon_maps.asm').read_text(),re.M)}
    tree_sets={}
    raw=(source/'data/wild/treemons.asm').read_text()
    for name,body in re.findall(r'^TreeMonSet_(\w+):([^:]+?)(?=^TreeMonSet_|\Z)',raw,re.M|re.S):
        groups=[]
        for part in body.split('db -1'):
            rows=[[int(w),species[m],int(l)] for w,m,l in re.findall(r'db (\d+),\s*(\w+),\s*(\d+)',part)]
            if rows:groups.append(rows)
        if groups:tree_sets[name.lower()]=groups
    assert len(tree_sets)==7
    return {'maps':maps,'trades':trades,'siblings':[v[-1] for v in SIBLINGS], 'tree_maps':tree_maps,'tree_sets':tree_sets}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pokecrystal',type=Path)
    table=build(parser.parse_args().pokecrystal)
    (ROOT/'content/regions/johto/sidequests.json').write_text(json.dumps(table,ensure_ascii=False,indent=1)+'\n')
