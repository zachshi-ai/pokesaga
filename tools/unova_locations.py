"""Stable game IDs for shared Unova places and version-specific interiors."""
import re

SHARED={
    0:'black_city',6:'striaton',15:'striaton_school',10:'fennel_lab',16:'nacrene',17:'museum',
    28:'castelia',51:'castelia_gate_north',62:'nimbasa',96:'driftveil',107:'mistralton',113:'icirrus',
    120:'opelucid',123:'opelucid_house',136:'league',140:'e4_shauntal',141:'e4_grimsley',142:'e4_marshal',143:'e4_caitlin',
    144:'champion_room',152:'dreamyard',154:'pinwheel',157:'desert',160:'relic',194:'chargestone',198:'twist',
    205:'dragonspiral',214:'victory',230:'giant',234:'giant_chamber',249:'skyarrow_bridge',
    253:'driftveil_bridge',254:'tubeline_bridge',255:'village',264:'ns_castle_entry',278:'ns_castle',324:'wellspring',338:'celestial',
    389:'nuvema',390:'bw_home_1f',391:'bw_home_2f',392:'bw_bianca_home',396:'juniper_lab',
    397:'accumula',406:'lacunosa',412:'undella',424:'white_forest',
}
BW={
    7:'bw_gym_striaton',18:'bw_gym_nacrene',29:'bw_gym_castelia',63:'bw_gym_nimbasa',
    97:'bw_gym_driftveil',108:'bw_gym_mistralton',114:'bw_gym_icirrus',121:'bw_gym_opelucid',
    48:'castelia_plasma',193:'cold_storage',
}
B2={
    427:'aspertia',428:'b2_home',489:'b2_gym_aspertia',502:'b2_gym_virbank',
    97:'b2_gym_driftveil',108:'b2_gym_mistralton',121:'b2_gym_opelucid',473:'b2_gym_humilau',
    63:'b2_gym_nimbasa',439:'floccesy',444:'ranch',448:'virbank',458:'lentimas',465:'humilau',
    461:'reverse',566:'film',191:'pwt',495:'castelia_sewers',464:'marine_tube',515:'seaside_cave',
    552:'frigate_driftveil',562:'frigate_giant',555:'colress_lab',
}
LOCATIONS={
    'nuvema_town':'鹿子镇','aspertia_city':'桧扇市','accumula_town':'唐草镇','striaton_city':'三曜市','nacrene_city':'七宝市',
    'castelia_city':'飞云市','nimbasa_city':'雷文市','driftveil_city':'帆巴市','mistralton_city':'吹寄市','icirrus_city':'雪花市',
    'opelucid_city':'双龙市','pokemon_league':'合众联盟','undella_town':'涟漪镇','lacunosa_town':'笼目镇','anville_town':'金轮镇',
    'floccesy_town':'算木镇','floccesy_ranch':'算木牧场','virbank_city':'立涌市','virbank_complex':'立涌联合工业区','lentimas_town':'山路镇',
    'humilau_city':'青海波市','black_city':'黑色市','white_forest':'白色森林','dreamyard':'梦的遗址','pinwheel_forest':'矢车森林',
    'desert_resort':'沙漠地带','relic_castle':'古代城','chargestone_cave':'电气石洞穴','twist_mountain':'罗斯山',
    'royal_unova':'皇家合众号','medal_office':'奖牌事务所','battle_subway':'对战地铁',
    'none':'联机接待厅','underground_ruins':'地下遗迹','nature_preserve':'自然保护区',
    'rock_peak_chamber':'岩山之间','iceberg_chamber':'冰山之间','iron_chamber':'黑金之间','pledge_grove':'誓约之林',
    'dragonspiral_tower':'龙螺旋之塔','victory_road':'冠军之路','giant_chasm':'巨人洞窟','ns_castle':'Ｎ的城堡',
    'wellspring_cave':'地下水脉之穴','celestial_tower':'天堂之塔','liberty_garden':'自由庭园岛','p2_laboratory':'P2 实验室',
    'undella_bay':'涟漪湾','abyssal_ruins':'海底遗迹','skyarrow_bridge':'天箭桥','driftveil_drawbridge':'帆巴吊桥',
    'tubeline_bridge':'圆筒桥','village_bridge':'村庄桥','marvelous_bridge':'奇幻桥','pwt':'宝可梦世界锦标赛',
    'reversal_mountain':'反转山','plasma_frigate':'等离子驱逐舰','castelia_sewers':'飞云下水道','marine_tube':'海洋隧道',
    'seaside_cave':'海边洞穴','pokestar_studios':'宝可坞','cold_storage':'冷冻仓库','entree_forest':'连入之森','entralink':'连入',
    'moor_of_icirrus':'雪花湿地','abundant_shrine':'丰收之祠','lostlorn_forest':'迷幻森林','mistralton_cave':'吹寄洞穴',
    'join_avenue':'加盟大道','relic_passage':'古代秘道','clay_tunnel':'菊老大之路','hidden_grotto':'隐藏洞穴',
    'black_tower':'黑色摩天楼','white_treehollow':'白色树洞','gear_station':'对战地铁','big_stadium':'运动场','small_court':'小球场',
    'musical_theater':'音乐剧会馆','cave_of_being':'心之空洞','strange_house':'陌生人之家','rumination_field':'思索之原',
    'unity_tower':'联合塔','trial_chamber':'试炼之间','guidance_chamber':'引导之间','pokestar_studios':'宝可坞',
    'shopping_mall':'购物中心','challengers_cave':'修行岩屋','poke_transfer_lab':'宝可传送工厂','team_plasma':'等离子队',
}
LABELS={'bw_home_2f':'鹿子镇·小悠的卧室','bw_home_1f':'鹿子镇·小悠的家','b2_home':'桧扇市·小悠的家','aspertia_lookout':'桧扇市·展望台',
    'juniper_lab':'鹿子镇·红豆杉研究所','bw_bianca_home':'鹿子镇·白露的家','fennel_lab':'三曜市·真菰研究室','striaton_school':'三曜市·训练家学校',
    'museum':'七宝博物馆','cold_storage':'冷冻仓库','castelia_plasma':'飞云市·等离子队据点','castelia_gate_north':'飞云市·北关口',
    'e4_shauntal':'合众联盟·婉龙之间','e4_marshal':'合众联盟·连武之间','e4_caitlin':'合众联盟·嘉德丽雅之间','e4_grimsley':'合众联盟·越橘之间',
    'champion_room':'合众联盟·冠军之间','ns_castle':'Ｎ的城堡·王座','giant_chamber':'巨人洞窟·最深处','marine_tube':'海洋隧道',
    'nimbasa_old_gym':'雷文市·旧道馆','opelucid_house':'双龙市·夏卡的家','colress_lab':'等离子驱逐舰·阿克罗玛实验室',
    'frigate_p2':'等离子驱逐舰·P2 实验室停泊处','frigate_seaside':'等离子驱逐舰·海湾甲板','frigate_driftveil':'等离子驱逐舰·帆巴甲板','frigate_giant':'等离子驱逐舰·巨人洞窟停泊处'}
def assign(src):
    overrides={**SHARED,**(BW if src.era=='bw' else B2)}
    for z in src.zones:
        k=z['key']
        if re.fullmatch(r'route_\d+',k):overrides[z['i']]=k[6:]
        if src.era=='b2':
            if k=='castelia_city_gym_2':overrides[z['i']]='b2_gym_castelia'
            if k=='nimbasa_city_17':overrides[z['i']]='nimbasa_old_gym'
        mid=overrides.get(z['i'],src.era+'_zone_'+str(z['i']))
        z['mid']='unova_'+mid
        place=z['place'] if re.fullmatch(r'route_\d+',z['place']) else z['place'].removesuffix('_2')
        name=LOCATIONS.get(place)
        if not name and re.fullmatch(r'route_\d+',place): name=place[6:]+'号道路'
        if not name and 'gate' in place:name='合众关口'
        if not name:name='合众设施'
        if 'gym_' in mid:name=LOCATIONS.get(z['place'],name)+'道馆'
        elif mid in LABELS:name=LABELS[mid]
        elif src.era=='bw' and z['i'] in (191,192):name='冷冻仓库'
        elif k.endswith('pokemon_center') or z['bgm']==1060:name+='·宝可梦中心'
        elif z['parent']!=z['i'] and mid.startswith(src.era+'_zone_') and place not in ('royal_unova','medal_office','nature_preserve','rock_peak_chamber','iron_chamber','iceberg_chamber','pledge_grove'):
            name+='·'+str(z['i'])
        z['name']=name
