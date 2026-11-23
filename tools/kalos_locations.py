"""Stable game ids for X/Y cartridge zones and script-operated passages."""
import re
TOWNS={0:'vaniville',8:'aquacorde',12:'camphrier',21:'geosenge',29:'dendemille',38:'couriway',45:'ambrette',
       53:'santalune',63:'lumiose',157:'cyllage',172:'shalour',187:'coumarine',200:'laverre',211:'anistar',
       222:'snowbelle',233:'kiloude',243:'league'}
CENTERS={13:'camphrier',24:'geosenge',33:'dendemille',40:'couriway',47:'ambrette',54:'santalune',75:'lumiose',76:'lumiose_north',159:'cyllage',174:'shalour',190:'coumarine',202:'laverre',214:'anistar',225:'snowbelle',234:'kiloude',244:'league',359:'lumiose_center_magenta'}
GYMS={55:'santalune',160:'cyllage',175:'shalour',191:'coumarine',78:'lumiose',203:'laverre',215:'anistar',226:'snowbelle'}
ALIAS={**TOWNS,**{z:'center_'+s if z!=359 else s for z,s in CENTERS.items()},**{z:'gym_'+s for z,s in GYMS.items()},
       1:'home_2f',2:'home_1f',4:'rival_home',5:'rival_home_2f',14:'shabboneau_castle',48:'ambrette_aquarium',
       49:'ambrette_fossil_lab',56:'gym_santalune_web',64:'lumiose_south_west',65:'lumiose_north',66:'lumiose_north_east',
       67:'lumiose_plazas_north',68:'lumiose_plazas_south',69:'lumiose_central',77:'tower',
       83:'sycamore_lab_lobby',84:'sycamore_lab_2f',85:'sycamore_lab',88:'cafe_soleil',93:'lysandre_cafe',
       96:'flare_labs',94:'flare_labs_b2',95:'flare_labs_b3',104:'lumiose_museum',109:'lumiose_station',
       110:'battle_institute',120:'victory_cafe',128:'stone_emporium',131:'herboriste',134:'herboriste_shop',
       135:'hotel',146:'sushi_high_roller',152:'lumiose_galettes',156:'looker_bureau',165:'cyllage_bike_shop',
       181:'mastery',182:'mastery_summit',188:'coumarine_hill',192:'coumarine_monorail_west',193:'coumarine_monorail_east',
       236:'kiloude_station',241:'battle_maison',245:'league_lobby',246:'league_hall',251:'e4_malva',252:'e4_siebold',
       253:'e4_wikstrom',254:'e4_drasna',255:'champion_stairs',256:'champion_room',257:'hall_of_fame',
       265:'daycare',286:'forest',287:'palace_approach',288:'palace',302:'parfum_garden',
       303:'glitter_entrance',304:'glitter',305:'reflection',309:'factory_gate',310:'factory',
       313:'frost_entrance',314:'frost_main',317:'frost',318:'village',319:'unknown_dungeon',320:'victory',321:'league_gate',
       329:'battle_chateau',334:'cave',335:'power_plant_gate',336:'power_plant',339:'flare_hq',341:'flare_hq_control',
       343:'terminus_entrance',346:'terminus_cave',349:'lost_hotel',350:'chamber_emptiness',351:'sea_spirits_den',
       352:'berry_fields',354:'friend_safari',355:'friend_safari_gate',357:'azure',356:'anistar_sundial'}
for n,z in enumerate((258,259,260,261,262,263,264,266,267,268,269,270,272,273,275,276,278,279,281,282,283,285),1):
    ALIAS[z]=str(n)
CN={'Vaniville Town':'朝香镇','Aquacorde Town':'名水镇','Santalune City':'白檀市','Lumiose City':'密阿雷市','Camphrier Town':'古木镇','Ambrette Town':'古香镇','Cyllage City':'遥香市','Geosenge Town':'石香镇','Shalour City':'娑罗市','Coumarine City':'比翼市','Laverre City':'香薰市','Dendemille Town':'风絮镇','Anistar City':'百刻市','Couriway Town':'连理镇','Snowbelle City':'映雪市','Kiloude City':'奇楠市','Pokémon League':'宝可梦联盟','Pokémon League Gate':'徽章检验大门','Victory Road':'冠军之路','Prism Tower':'棱镜塔','Shabboneau Castle':'虚空之间城','Santalune Forest':'白檀森林','Parfum Palace':'巴尔法姆香殿','Glittering Cave':'闪耀洞窟','Reflection Cave':'镜穴','Connecting Cave':'地穴','Sea Spirit’s Den':'海神之穴','Azure Bay':'蔚蓝湾','Kalos Power Plant':'卡洛斯发电厂','Tower of Mastery':'精练之塔','Poké Ball Factory':'精灵球工厂','Frost Cavern':'冰结洞窟','Team Flare Secret HQ':'闪焰队秘密基地','Terminus Cave':'终结洞窟','Lost Hotel':'荒废旅馆','Unknown Dungeon':'无名洞窟','Chamber of Emptiness':'空虚之间','Pokémon Village':'宝可梦村','Battle Chateau':'对战城堡','Glittering Cave':'闪耀洞窟','Friend Safari':'朋友狩猎区','Lysandre Labs':'弗拉达利研究所','Lumiose Station':'密阿雷车站','Kiloude Station':'奇楠车站','Battle Maison':'对战宅第','Ambrette Aquarium':'古香水族馆','Blazing Chamber':'火焰之间','Flood Chamber':'水门之间','Dragonmark Chamber':'龙纹之间','Ironworks Chamber':'钢铁之间','Radiant Chamber':'光辉之间'}
CN['Shabboneau Castle']='古木镇城堡'
NAMED={1:'小悠的卧室',2:'小悠的家',49:'化石研究所',56:'白檀道馆・蛛网',63:'密阿雷市・南侧大道',65:'密阿雷市・北侧大道',69:'中央广场',83:'布拉塔诺研究所・一楼',84:'布拉塔诺研究所・二楼',85:'布拉塔诺研究所・三楼',88:'日轮咖啡馆',93:'弗拉达利咖啡馆',94:'弗拉达利研究所・地下二层',95:'弗拉达利研究所・地下三层',104:'密阿雷美术馆',110:'对战检验中心',120:'胜利咖啡馆',128:'石头馆',131:'草药店',135:'大酒店',146:'高级寿司店',152:'密阿雷小巷',156:'帅哥侦探事务所',165:'自行车店',182:'精练之塔・塔顶',192:'比翼市・海侧车站',193:'比翼市・山侧车站',245:'联盟大厅',246:'四天王之厅',251:'火焰之间・帕琦拉',252:'水门之间・志米',253:'钢铁之间・雁铠',254:'龙纹之间・朵拉塞娜',256:'光辉之间・卡露妮',257:'名人堂',265:'培育屋',302:'香殿后花园',317:'冰结洞窟・最深处',341:'最终兵器控制室',352:'树果园',356:'百刻日晷'}
for z,city in CENTERS.items(): NAMED[z]='宝可梦中心'
def name(z,zone):
    en=zone['name']
    base=CN.get(en)
    if not base:base=(en.split()[-1]+'号道路') if en.startswith('Route ') else next((CN.get(en.split()[0]+' City',CN.get(en.split()[0]+' Town',''))+'关口' for _ in (0,) if en.endswith(' Gate')),en)
    return NAMED.get(z,base+'道馆' if z in GYMS else base)
def mid(z):return 'kalos_'+ALIAS.get(z,'zone_'+str(z))

ALIAS.update({22:'crystals',274:'scary_house',51:'ambrette_hotel'})
NAMED.update({22:'石香镇・巨石遗迹',274:'荒郊小屋'})
# Rooms with no ordinary door (the original activates lifts, transports, or cutscenes).
# These links use separate marked floor cells; the rider arrives beside, never on, the return trigger.
SCRIPT_LINKS=[(1,2,'家里的楼梯'),(55,56,'攀绳'),(83,84,'研究所电梯'),(84,85,'研究所电梯'),
 (77,79,'棱镜塔电梯'),(79,80,'二层升降台'),(80,81,'三层升降台'),(81,82,'四层升降台'),(82,78,'馆主席电梯'),
 (96,94,'地下电梯'),(94,95,'机房电梯'),(96,102,'地下研究区'),(192,193,'比翼单轨列车'),
 (109,236,'奇楠专列'),(245,246,'联盟大门'),(256,257,'名人堂'),(355,354,'狩猎区接待处'),(127,156,'侦探事务所'),
 (86,87,'电梯'),(91,92,'电梯'),(111,112,'电梯'),(112,113,'电梯'),(114,115,'电梯'),(115,116,'电梯'),
 (135,136,'二楼电梯'),(136,137,'三楼电梯'),(137,138,'四楼电梯'),(138,139,'顶层电梯'),(144,145,'电梯'),
 (163,164,'单轨电梯'),(204,205,'单轨电梯'),(216,217,'单轨电梯')]
# Alternate camera/cutscene versions share the normal zone's activity and return point.
# They are retained as source references instead of becoming independent towns.
TECH={3:2,23:21,30:29,158:157,296:294,358:241}
# Native adjacent zones in the same matrix have no warp event in X/Y.
SEAMS=[(0,258),(258,8),(8,259),(260,53),(53,261),(53,285),(262,12),(12,264),
       (266,45),(266,157),(157,268),(270,187),(270,357),(273,200),(275,276),(279,38),
       (63,64),(65,66),(67,68)]

NAMED.update({51:'古香镇旅馆',126:'二星餐厅',140:'三星餐厅',141:'一星餐厅'})

NAMED.update({57:'白檀时装店',89:'时装沙龙',90:'时装沙龙・二楼',91:'南侧大道办公楼',125:'内向咖啡馆',130:'滑轮咖啡馆'})

ALIAS.update({123:'herboriste',131:'zone_131'})
NAMED.update({117:'汪汪咖啡修剪沙龙',122:'果汁馆',123:'草药店',131:'咖啡厅'})
