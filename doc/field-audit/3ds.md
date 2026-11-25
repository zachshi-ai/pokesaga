# 卡洛斯、阿罗拉与跨空间旧通道

[逐张地图的门、落点、步数与原作来源](3ds.tsv)包含卡洛斯 356 张、阿罗拉 203 张、以太旧通道 5 张、究极空间旧通道 6 张。石香镇的三种剧情地形另测。阿罗拉的四部作品共用一套地形，版本和剧情开门条件另行验证。

### 实际走过哪里

从每张图的出生格出发，用 Godot 的寻路碰撞规则找出当前可步行区域内的最远格，再逐步重放方向输入。每道门另从相邻格进入，载入目的地图，用真实返回落点步行至回程门。全部 570 张图合计行走 28,317 步，1,360 个有效出口全部进入并走回了原图。柜台测试在 32 间宝可梦中心分别站到护士和商店柜台前，确认撞柜台不能前进、按 A 能与柜台后正确的人对话。石香镇分别在巨石、最终兵器升起和弹坑阶段实走。阿罗拉 39 个带条件的地图入口在四版本、三个剧情状态下分别核对。

这是地图移动测试。默认逐图路线保留初期常驻 NPC，逐门检查直接使用地区场景的传送信号；战役剧情闸门单独测试。18 张图册直接解码已签名安卓包中的 570 张场景、家具和建筑贴图，再按游戏锚点合成。下列七张玩家视角使用同一包的运行资源重新截取。149 张重绘室内的包内纹理均与本地导入结果逐字节一致。APK 的 SHA-256 为 `21d286c496716d28fb097fcf0b46c5055aaf8fe48845bc69a2a2d7de98ac326a`。

| 地点 | 玩家视角 |
| --- | --- |
| 马利埃图书馆大厅 | [从南门走到中央通道](../../.github/preview/v4.68/3ds/alola_malie_library.png) |
| 马利埃图书馆楼上 | [从楼梯走到藏书架之间](../../.github/preview/v4.68/3ds/alola_malie_library_2f.png) |
| 古木镇旅馆 | [小悠出门后的位置](../../.github/preview/v4.68/3ds/kalos_camphrier.png) · [厅内原纹样地毯](../../.github/preview/v4.68/3ds/kalos_zone_17.png) |
| 2 号道路汽车旅馆 | [两张床与客房家具](../../.github/preview/v4.68/3ds/alola_motel_2.png) |
| 娑罗市宝可梦中心 | [小悠站在护士柜台前](../../.github/preview/v4.68/3ds/kalos_center_shalour.png) |
| 19 号道路 | [湿地与木桥边](../../.github/preview/v4.68/3ds/kalos_19.png) |

### 地面和室内的修订

卡洛斯的可通行面与建筑的投影高度不同，过坡、林地边缘和空中通道能出现露出背景的步行格。按地表类别从邻近连续平面补回透底像素，保留建筑轮廓。白檀道馆则按四向碰撞补蛛丝的转角和枝路。旅馆、民居、办公室等房间原先保留了已替换家具的碰撞，再把这些碰撞绘成了墙；现在房间地板连续铺至墙脚，床、书架、设备和桌椅各自承担碰撞。32 间中心的柜面、柜台碰撞和服务人员坐标也重新对齐。[宝可梦村同一地块改前改后](../../.github/preview/v4.68/3ds/xy-village-floor.png)

卡洛斯的 149 个民居、旅馆、咖啡店和办事处等室内场景按 53 个原始模型重铺。地板包含原版家具下方的铺面，地毯和楼梯保留原模型的形状与方向。古木镇旅馆的左侧楼梯、中央地毯和大厅两侧地板均可对照查看。[古木镇旅馆改前改后](../../.github/preview/v4.68/3ds/xy-camphrier-lobby.png)

马利埃图书馆在四部游戏里都有两个楼层。马利埃市原门通向一楼，沿西侧楼梯可到新增二楼阅览室，按 A 可以读书架上的两段资料，回程落在同一段楼梯前。二楼的用途和楼层连接有原作资料，平面尺寸与书架位置为绿宝石镜头改绘。[马利埃市馆内资料](https://bulbapedia.bulbagarden.net/wiki/Malie_City#Malie_Library)

### 原作比对的范围

卡洛斯使用《X／Y》的分区编号、场景矩阵、网格原点和有编号的传送目标。台账逐门读取原表，列出目的地是否匹配、原始有坐标的入口有几扇、其中几扇落在同格、最大格差和偏移原因。752 个有编号的出口全部连到原版指定区域。676 个有坐标的入口里，509 个在原格触发。本次在 33 张图上把 64 扇墙门移回原模型入口，让小悠站在门的南侧向上进门，出门回到门外同一格。另有 4 处恢复了沼泽道路、水上岛屿、潮汐浅滩和徽章检验门的原入口。这四条路线从各自出生点逐步往返，共 422 步；从蔚蓝湾下水后有 121 步在水面。12 号路往北进入蔚蓝湾的边界和两侧落点都在水面。另实走了 399 步验证 12 号路和海湾之间的双向冲浪路线。余下 167 处在台账里分别标明原因，其中 104 处投影在实心模型上、41 处与主路隔断、17 处使用改绘平面、3 处与其他门或剧情锚点重合、2 处落在水域。原作没有坐标的脚本交通、改绘道馆以及自建跨区道使用适配入口。阿罗拉的原始场景和分区资料来自《太阳／月亮》，包括岛屿地形、部分独立场景、训练家与道具坐标。究极版增设房间、用地点关系补的室内与四版本剧情限制各自标注。未持有全部 USUM 室内原模型和全部商户的原作入门坐标，因此还不能从这份清单断言所有原版地点都已实现或逐格一致。在阿罗拉的 200 张本地地图中，110 张对应原始分区或实景，4 张只对应地点目录，84 张缺原始室内或平面坐标，马利埃图书馆 2 张另按楼层关系核对。[《X／Y》分区数据](https://3ds.pzfans.com/static/zones/pokemon-x-and-y/data/map.json) · [《太阳／月亮》场景与原坐标](https://3ds.pzfans.com/pokemon-sun-moon/pokemon-sun-moon-alola-map/)

《X／Y》目录含 360 个分区号。354 个号直接对应游戏里的原生地图；7 号路的两个可走段共用其中一个号。其余 6 个号属于同地点的额外视角或阶段，对应朝香镇 3、石香镇 23、风絮镇 30、遥香市 158、巴尔法姆香殿 296 和对战宅第 358，原表这六项均无独立传送门，石香镇 23 用于剧情阶段。[分区重用和普通门记录](../../tools/kalos_locations.py)

《太阳／月亮》的地点目录列有 295 个分区号，现有地图引用了 266 个。其中带可核对地形的 107 个号和带独立实景记录的 79 个号全部有对应。下列 29 个号只有地点层级索引，没有一一对应的室内平面或原入口格。这些地点在游戏里已可进入，表中保留未对上的原号，供逐个补证。[阿罗拉的地图与场景目录](https://3ds.pzfans.com/pokemon-sun-moon/pokemon-sun-moon-alola-map/)

| 原版地点 | 未单独对位的分区号 |
| --- | --- |
| 好奥乐市郊、2 号路、好奥乐市商业区 | 26、37 / 40 / 57 |
| 慷待市、皇家巨蛋 | 109 / 128 |
| 13 号路、15 号水路、16 号路 | 209 / 206 / 212 |
| 宝可梦联盟 | 219 至 224 |
| 海洋居民之村、对战树 | 256 / 264 至 267 |
| 以太乐园 | 269、270、274、275、277 至 280 |
| 究极空间 | 283 |

### 整图浏览

| 地区 | 按地图 ID 排序的整图 |
| --- | --- |
| 卡洛斯 | [1](../../.github/preview/v4.68/3ds/kalos-01.jpg) · [2](../../.github/preview/v4.68/3ds/kalos-02.jpg) · [3](../../.github/preview/v4.68/3ds/kalos-03.jpg) · [4](../../.github/preview/v4.68/3ds/kalos-04.jpg) · [5](../../.github/preview/v4.68/3ds/kalos-05.jpg) · [6](../../.github/preview/v4.68/3ds/kalos-06.jpg) · [7](../../.github/preview/v4.68/3ds/kalos-07.jpg) · [8](../../.github/preview/v4.68/3ds/kalos-08.jpg) · [9](../../.github/preview/v4.68/3ds/kalos-09.jpg) · [10](../../.github/preview/v4.68/3ds/kalos-10.jpg) |
| 阿罗拉 | [1](../../.github/preview/v4.68/3ds/alola-01.jpg) · [2](../../.github/preview/v4.68/3ds/alola-02.jpg) · [3](../../.github/preview/v4.68/3ds/alola-03.jpg) · [4](../../.github/preview/v4.68/3ds/alola-04.jpg) · [5](../../.github/preview/v4.68/3ds/alola-05.jpg) · [6](../../.github/preview/v4.68/3ds/alola-06.jpg) |
| 旧跨空间通道 | [以太](../../.github/preview/v4.68/3ds/aether-01.jpg) · [究极空间](../../.github/preview/v4.68/3ds/ultra-01.jpg) |

### 复测

```sh
godot --headless --path . --script tools/test_3ds_field_survey.gd -- /tmp/3ds-walk.tsv
godot --headless --path . --script tools/test_kalos_source_approaches.gd
python3 tools/test_kalos_maps.py
python3 tools/audit_3ds_map_sources.py --apk /path/to/PokeSaga.apk --xy /path/to/xy-atlas --sm /path/to/sm-atlas --walk /tmp/3ds-walk.tsv --output /tmp/3ds-sources.tsv
godot --headless --path . --script tools/test_ds_threshold_staff.gd
```

最后一项复测《白金》《黑／白》《黑2／白2》普通角色、剧情门卫和过场角色的出场条件。在合众 10 号路，精英训练家原来的站位压住单向落差，现向北挪一格。9 号路的黑带、两代的水手与宝可坞护卫在各自剧情条件满足后侧身。宝可坞最后一部影片获得好结局及旧档载入时都会检查全片成绩。白金 224 号路的谢米属于过场，离去后可北上，捕捉地点是花之乐园。[21 道门及原人物脚本](ds-door-staff.tsv) · [白金 224 号路原脚本](https://github.com/pret/pokeplatinum/blob/main/res/field/maps/route_224/scripts.s) · [黑2宝可坞门卫原脚本](https://github.com/fuddlesworth/pokebw2/blob/main/res/field/scripts/pokestar_studios_3.s)
