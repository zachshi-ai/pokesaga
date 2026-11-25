# 《剑／盾》与扩展票地图逐图记录

4.68 签名 APK 的游戏资源里登记了 160 张伽勒尔本土地图、29 张铠岛地图和 33 张王冠雪原地图。溯传、战竞的道馆任务和对战场各有剑盾两套画面，宫门的塔入口按夺冠前后切换。逐个载入以上 227 种状态，经各自的 593 个出口核对目的地、实际落脚坐标及碰撞，共走 8,711 步。溯传的三段旋转座椅使用游戏内的座椅逻辑。14 座宝可梦中心另实测了护士和商店柜台。逐图记录含步数、出入口计数和原作对照范围。[逐图记录](galar.tsv)

| 地区 | 原有地图 | 本次新增 | 现有地图 | 新增实例 |
| --- | ---: | ---: | ---: | --- |
| 伽勒尔 | 106 | 54 | 160 | 旷野各湖岸、沙尘洼地、桥间空地与寄放屋、旷野车站、机擎市郊外、中心、对战咖啡馆、酒店客房、对战塔、五家服装店与四家沙龙 |
| 铠岛 | 18 | 11 | 29 | 挑战海滩、斗志洞窟、圆环海湾、锻炼平原、热身洞穴、锅底沙漠、各外海及蜂巢岛 |
| 王冠雪原 | 9 | 24 | 33 | 远古墓地、三岔平原、湖畔洞窟、冻海、通顶雪道、三座巨人遗迹、探险基地、村长家和极巨大冒险的十张地图 |

38 处具名野外分区的规划使用各地点的相邻方向、海域、洞口和区域地貌。138 个新增地区边界出口在这些分区和既有地区之间成对连接。地形、建筑在 Switch 上的透视和连续空间在此转译为四向、16 像素的二维格。旧档可以继续从原有地图坐标出发。现有直通口仍保留，所以某些地方也可以沿旧路线跨过中间分区。每处场地的道路长度、居民房间尺寸和家具坐标均是本作的适配。[地点与地貌草图](../../tools/galar_atlas/sites.txt) · [相邻表](../../tools/galar_atlas/links.txt) · [原作旷野地点](https://www.serebii.net/pokearth/galar/hammerlockehills.shtml) · [扩展票区域介绍](https://swordshield.pokemon.com/en-ca/expansionpass/setting-of-new-adventure/)

机擎市有两座中心，拳关市有西、中央、东三座，宫门市有南区和竞技场前两座。各店有可实际进出的门，厅内接入现有治疗和购买服务。城镇的屋门、相邻路口和角色脚下的碰撞格一起核过。新增支路向原有区域剧情检查传递目的地，牙牙湖之眼另检查水上自行车。冻凝村的线索和汇报、缰绳、三座遗迹调查和远古墓地的黑萝卜地保留原存档的事件标记。[拳关市的分店](https://www.serebii.net/pokearth/galar/hammerlocke.shtml) · [城镇服务地点](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9_Mart) · [官方城镇设计](https://assets.pokemon.com/assets/cms2/pdf/video-game/sword-shield/Galar_Tour_Brochure_US.pdf)

球湖湖畔恢复为一片真实、连通的湖水，北岸步道通向树丘和洞窟。大树丘陵换成有粗树干、果实和多层树冠的地标。战竞浴池重做了池缘，草路镇增加白垩地画。其余道路、雪原、湿原、矿道的重复地块按碰撞、材质边缘和地形选用绿宝石像素材质。[球湖湖畔](https://www.serebii.net/pokearth/galar/ballimerelake.shtml) · [大树丘陵](https://www.serebii.net/pokearth/galar/dynatreehill.shtml)

《剑／盾》的三个对战咖啡馆在机擎、拳关和宫门各自按日记录胜场。战竞爱奥尼亚酒店的两个大厅通往各自的楼上走廊，每一侧都有四间独立客房。东馆能逐人问话破案并领取广角镜，也能取得刺耳声、假哭学习器。西馆保留了游戏总监和通关后的森本双打。宫门同一座塔在通关前进入洛兹大厦，在通关后开放塔内接待、借用队伍、单打和双打。玩家原队在塔的定级对战结束后恢复。对战塔收录了五套租借队与 177 个训练家或丹帝段位条目。现有 BP 商店提供两类商品。[酒店的房间及住客](https://bulbapedia.bulbagarden.net/wiki/Hotel_Ionia) · [三个咖啡馆](https://www.serebii.net/swordshield/dailyevent.shtml) · [对战塔](https://www.serebii.net/swordshield/battletower.shtml) · [租借队](https://www.serebii.net/swordshield/rental.shtml)

在签名包提取的游戏资源中，从带有伽勒尔冠军记录的历程存档接着实玩，走进酒店逐人问话、领取道具并打赢森本，走到三个咖啡馆取胜并重访确认当日关闭。对战塔租借队分别打赢一场单打和双打，两次都回到接待大厅。另一份推进到皮欧尼的存档从巢穴营地借用巨沼怪，实际走进三层支洞，依次击败煤炭龟、暴雪王、赤面龙和水君，回到营地时任务完成并收回租借队伍。三条历程都使用游戏的移动、交互、菜单和战斗指令。[活动测试](../../tools/test_galar_venues_journey.py)

木杆镇西北、机擎市东南、拳关市西区、战竞镇东北与宫门市西侧的服装店各有货架和能使用的试衣间。四家沙龙位于机擎市东南部服装店旁、拳关市咖啡馆西面、战竞镇东南角与宫门市西路。走入一家店即可试穿买到的上装，服装同步写入同一份存档的衣柜。在 APK 提取资源的另一趟实走中，小悠买入五件上装、在五间更衣室各换装两次，到四个沙龙完成美发，逐次核对收费和持久状态，共走 1,298 步。保留绿宝石小悠的行走和冲浪动作，现有上装用 15 件原作商品和本作的色板呈现。在图形模式复核了两种发色、三种剪法，在走路和冲浪图集中的 12 个组合均有独立像素变化。[原作店铺方位](https://bulbapedia.bulbagarden.net/wiki/Trainer_customization) · [服装及价格](https://www.serebii.net/swordshield/customisation.shtml) · [官方训练家换装介绍](https://swordshield.pokemon.com/en-us/gameplay/clothes-hairdo-style/)

## 每张地图的运行画面

桌面 Godot 从签名 APK 的资源包启动后，逐张截取了 227 帧游戏视口。宝可梦中心、咖啡馆、对战塔和巢穴的视角分别取自走近柜台、场地或分岔后的站位。图集的顺序与逐图记录一致。[第 1 页](../../.github/preview/v4.68/galar/game-board-1.jpg) · [第 2 页](../../.github/preview/v4.68/galar/game-board-2.jpg) · [第 3 页](../../.github/preview/v4.68/galar/game-board-3.jpg) · [第 4 页](../../.github/preview/v4.68/galar/game-board-4.jpg) · [第 5 页](../../.github/preview/v4.68/galar/game-board-5.jpg) · [第 6 页](../../.github/preview/v4.68/galar/game-board-6.jpg) · [第 7 页](../../.github/preview/v4.68/galar/game-board-7.jpg)

## 原作对照的边界

三层极巨大冒险由十张固定洞室组成，每层两条支路和一个终点供单人选择。原作多人联机探险及其完整随机巢穴池还未复刻。三座巨人遗迹沿用项目现有解谜。宫门伦度罗瑟酒店沿用现有大厅。城镇的通称民宅、竞技场附属柜台和既有功能建筑尚未逐栋取得原作平面图。美发、服装与室内家具按绿宝石角色和地图尺寸适配。野生天气表、全部训练家与商店货单及各剧情标记组合也没有在本轮重跑。[战竞市](https://www.serebii.net/pokearth/galar/circhester.shtml) · [机擎市](https://www.serebii.net/pokearth/galar/motostoke.shtml) · [宫门市](https://www.serebii.net/pokearth/galar/wyndon.shtml)


复跑全部出口可用 `Godot --headless --path . --script tools/test_galar_atlas.gd -- /absolute/path/galar.tsv`。在图形窗口中增加绝对截图目录和 `pictures` 参数可保存全图集。
