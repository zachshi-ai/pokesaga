"""Sun/Moon location and scene numbers plus the Ultra games' additional destinations."""
# IDs match the game's public location table. Names also serve as stable shared-save map IDs.
LOCS=dict(zip(range(6,32,2),'hauoli_outskirts 1 3 2 kalae_bay melemele_sea hauoli_beachfront hauoli hauoli_marina iki mahalo mahalo_bridge conflict'.split()))
LOCS.update(dict(zip(range(34,66,2),'hill farthest_hollow cemetery melemele_meadow seaward_cave berry_fields cavern cavern_den 4 5 6 7 8 9 hano hano_beach'.split())))
LOCS.update(dict(zip(range(68,80,2),'paniola heahea konikoni royal memorial_hill paniola_ranch'.split())))
LOCS.update(dict(zip(range(82,96,2),'wela wela_den brooklet brooklet_den lush life akala_outskirts'.split())))
LOCS.update({100:'diglett_tunnel',104:'royal_dome'})
LOCS.update(dict(zip(range(106,156,2),'10 11 secluded_shore 13 tapu 15 16 17 12 haina 14 ulaula_meadow po malie malie_garden hokulani blush_mountain abundance lake_sunne lake_moone lanakila shady_house megamart observatory league'.split())))
LOCS.update(dict(zip(range(156,194,2),'poni_meadow wilds ancient_path poni_breaker_coast poni_grove poni_plains poni_coast poni_gauntlet seafolk canyon altar moone hope resolution_cave exeggutor battle_tree aether_entrance ultra_deep_sea malie_cape'.split())))

# Sector boundaries, footpaths, entrances and ferry services. Adjacent words are connected in both directions.
PATHS=[
'home home_1f hauoli_outskirts 1 iki mahalo mahalo_bridge conflict',
'1 3 2 hauoli hauoli_beachfront hauoli_outskirts lab','hauoli_outskirts school','hauoli hauoli_marina',
'3 meadow melemele_meadow seaward_cave kalae_bay','hauoli_outskirts melemele_sea hill farthest_hollow','hauoli_outskirts hill',
'2 cemetery','2 berry_fields','2 cavern cavern_den','2 big_wave_beach heahea_beach heahea',
'hauoli_marina heahea 4 paniola paniola_ranch 5 brooklet brooklet_den','paniola_ranch 6 royal royal_dome',
'6 heahea','royal 7 wela wela_den','7 8 lush','8 5','heahea hano hano_beach','heahea diglett_tunnel 9 konikoni',
'9 memorial_hill akala_outskirts life','heahea dimensional_lab','royal thrifty_mart',
'hano aether_docks aether_entrance aether_mansion','aether_entrance aether_lab aether_lab_b',
'aether_docks malie malie_garden','malie 10 hokulani observatory','malie malie_cape','malie 11 12 13 tapu 14 megamart',
'12 blush_mountain','12 secluded_shore ulaula_beach','13 haina abundance','tapu 15 16 ulaula_meadow 17 po shady_house',
'15 aether_house','16 zygarde_lab','ulaula_meadow lake_sunne','ulaula_meadow lake_moone',
'malie seafolk wilds ancient_path poni_breaker_coast hope','seafolk exeggutor','seafolk mina_house','seafolk seafolk_restaurant',
'ancient_path canyon altar','canyon moone','altar ultra_deep_sea','moone ultra_deep_sea','altar megalopolis megalo_tower','moone megalopolis',
'ancient_path poni_grove poni_plains poni_coast poni_gauntlet battle_tree','poni_plains poni_meadow resolution_cave',
'poni_wormhole ultra_forest','poni_wormhole ultra_jungle','poni_wormhole ultra_plant','poni_wormhole ultra_desert',
'poni_wormhole ultra_crater','poni_wormhole ultra_ruin','poni_wormhole ultra_deep_sea','poni_wormhole ultra_space_wilds','altar poni_wormhole moone',
'poni_wilds_beach poni_beach poni_wilds_beach','wilds poni_wilds_beach',
'tapu lanakila league','league e4_fighting','league e4_rock','league e4_ghost','league e4_flying','league champion_room',
'hauoli hauoli_mall','2 motel_2','8 motel_8','13 motel_13','heahea tide_song',
'aether_mansion rr_mansion rr_left','rr_mansion rr_right','rr_mansion rr_giovanni','hauoli festival_plaza',
'heahea_beach ulaula_beach poni_beach','aether_docks seafolk','hauoli_marina malie',
]
# Custom interiors and Ultra destinations. Existing retail scene floors use their location name.
EXTRAS={
'home':'小悠的房间','home_1f':'小悠的家','lab':'宝可梦研究所','school':'训练家学校','meadow':'美乐美乐花园・入口',
'big_wave_beach':'大浪海滩','heahea_beach':'慷待海滩','ulaula_beach':'乌拉乌拉海滩','poni_beach':'波尼海滩','poni_wilds_beach':'波尼原野・西岸',
'dimensional_lab':'空间研究所','thrifty_mart':'超值超市','aether_docks':'以太乐园・船坞','aether_lab':'以太乐园・地下实验区',
'aether_lab_b':'以太乐园・B实验室','aether_mansion':'以太乐园・露莎米奈宅邸','aether_house':'以太之家','zygarde_lab':'以太基地・重组装置',
'mina_house':'茉莉的家','seafolk_restaurant':'海洋居民之村・餐厅','megalopolis':'究极大都会','megalo_tower':'大都会塔',
'poni_wormhole':'究极之洞','ultra_forest':'究极森林','ultra_jungle':'究极丛林','ultra_plant':'究极发电厂','ultra_desert':'究极沙漠','ultra_crater':'究极山谷','ultra_ruin':'究极大厦','ultra_space_wilds':'究极空间零地带',
'e4_fighting':'联盟・格斗之间','e4_rock':'联盟・岩石之间','e4_ghost':'联盟・幽灵之间','e4_flying':'联盟・飞行之间','champion_room':'联盟・冠军之间',
'hauoli_mall':'好奥乐购物中心','motel_2':'2号道路・汽车旅馆','motel_8':'8号道路・汽车旅馆','motel_13':'13号道路・汽车旅馆','tide_song':'听涛酒店',
'rr_mansion':'火箭队城堡','rr_left':'火箭队城堡・西翼','rr_right':'火箭队城堡・东翼','rr_giovanni':'火箭队城堡・首领室','festival_plaza':'圆庆广场'}
CENTERS='hauoli 2 5 8 heahea paniola konikoni malie 10 16 tapu seafolk lanakila royal hokulani'.split()
for place in CENTERS:PATHS.append(f'{place} center_{place}')
# Source scenes that share a location but are physically distinct rooms or dungeon traversals.
SUBS={60:('lush','树林西侧'),61:('lush','树林北侧'),62:('lush','树林东侧'),63:('lush','丛林洞窟'),
 100:('haina','沙漠深处'),117:('lanakila','山腹'),118:('lanakila','积雪洞穴'),119:('lanakila','雪原'),
 122:('shady_house','二楼'),123:('shady_house','小房间'),124:('shady_house','储藏室'),125:('shady_house','卧室'),127:('shady_house','走廊'),129:('shady_house','露台'),131:('shady_house','首领室'),
 133:('megamart','仓库'),134:('megamart','店铺深处'),151:('observatory','观测室'),171:('canyon','第一洞窟'),172:('canyon','第二洞窟'),173:('canyon','北侧断崖'),174:('canyon','吊桥'),175:('canyon','考验之间'),184:('resolution_cave','最深处')}
EXTRAS.update(aether_conservation='以太乐园・保护区',malie_marina='马利埃静市・渡船码头',hauoli_city_hall='好奥乐市政府',pikachu_valley='皮卡丘山谷',plains_grotto='波尼平原・岩洞')
PATHS+=['aether_entrance aether_conservation','malie malie_marina aether_docks','hauoli hauoli_city_hall','4 pikachu_valley','poni_plains plains_grotto']
EXTRAS['sandy_cave']='通海洞穴'
PATHS.append('big_wave_beach sandy_cave')
PELAGO={'abeens':'悠悠度假地','aplenny':'速速度假地','aphun':'怦怦度假地','evelup':'欢欢度假地','avue':'暖暖度假地'}
for p,label in PELAGO.items():
    EXTRAS['pelago_'+p]=label
    PATHS.append('heahea pelago_abeens' if p=='abeens' else 'pelago_abeens pelago_'+p)
EXTRAS.update(hauoli_police='好奥乐市・警察局',ilima_room='伊利马的房间',photo_hauoli='好奥乐市・阿罗拉摄影俱乐部',photo_konikoni='可霓可市・阿罗拉摄影俱乐部')
PATHS+=['hauoli hauoli_police','hauoli ilima_room','hauoli photo_hauoli','konikoni photo_konikoni']
