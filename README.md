# PokeSaga · 安卓学习版

用 Godot 4.7.2 开发的横屏宝可梦同人 RPG。当前学习版为 `4.57.0-study`，versionCode 为 90，包名为 `com.stepx.pokesaga.study`。它可以和 4.46 版同时安装，两份应用分别保存进度。

[下载 4.57 安卓学习版（ARM64 APK）](https://github.com/zachshi-ai/pokesaga/releases/download/v4.57.0-study/PokeSaga-4.57.0-study.apk) · [查看发布说明](https://github.com/zachshi-ai/pokesaga/releases/tag/v4.57.0-study)

关都可以带伙伴去两岛参加无线小游戏，城都可以按星期参加捕虫大会、拼阿露福遗迹石板，丰缘可以报名五种华丽大赛、挑战八间戏法屋或收集开拓象征。各地区共用主角、队伍、箱子和图鉴。[三作支线入口、奖励与验证范围](doc/三作支线.md)

[水静市华丽大赛安卓实拍](.github/preview/v4.57-contest.png) · [五轮后的得分和排名](.github/preview/v4.57-contest-results.png) · [阿露福遗迹触屏拼图](.github/preview/v4.57-alph.png) · [石板打开后出现未知图腾](.github/preview/v4.57-alph-open.png)

![安卓实拍・搬家货车驶入丰缘](.github/preview/v4.56-truck.gif)

全程操控《绿宝石》的小悠。阿银、空木博士、城都八位馆主、四天王、渡和赤红各自沿用剧情身份，并采用对应人物的 GBA 风格像素图。[城都人物对照与素材署名](doc/城都角色素材.md) · [在白银山与赤红同屏的安卓实拍](.github/preview/v4.55-red.png)

**地区转移器**随新档发放，旧档选择「继续冒险」后也会出现在背包里。探索时点 **START → 背包 → 重要道具 → 地区转移器**，选地区，再点「出发前往」。可以从屋内、洞窟、水上或异空间出发。首次进入有开场剧情的地区，会先到剧情起点，之后再去会抵达领航员旁。21 个目的地从开局就能选择，道具可重复使用，到达后自动保存。首次进入城都、丰缘会接上当地的开场剧情。 [查看背包实拍](.github/preview/v4.52-region-transfer.png)

![安卓同位置实拍对比。左列为 4.50，右列为 4.51。上排是常磐商店门前，下排是华蓝道馆的木桥和水池。](.github/preview/v4.51-field.png)

[查看战斗动图：皮卡丘使用十万伏特时，水伊布的 HP 从 132 降至 79](.github/preview/v4.51-battle-hp.gif)

## 从未白镇到丰缘联盟

标题的「新的冒险」从关都真新镇开始。第一次通过道路、船或地区转移器前往丰缘时，可选「乘坐搬家货车」或「直接抵达」。乘车时车厢和纸箱会随路面颠簸，停稳后车门透光，向右走下车。两种方式都在未白镇遇见妈妈。以后再去丰缘，仍可选乘车重看这一段，剧情只推进一次。先上自己家二楼调钟，再去隔壁家见小遥。随后向北走到 101 号道路，从小田卷博士的背包里选木守宫、火稚鸡或水跃鱼。

已有进度时选「继续冒险」。第一次去丰缘时，如队伍中已有宝可梦，游戏会询问如何安置。选「寄存队伍，重新组队」会把现有队员按顺序放进电脑空位，选「带现有队伍出发」可以带着伙伴走同一段剧情。两条路都沿用当前存档的背包、金钱、图鉴和名人堂记录。寄存时如果电脑空间不足，整队仍在手里。到过的旧地区可以用地区转移器返回。

丰缘徽章和秘传学习器分别记录获得进度。挑战橙华道馆的千里需要先取得四枚当地徽章。冲浪在战胜千里后由满充的父亲交给小悠，潜水要先完成绿岭宇宙中心的事件，再去大吾家领取。琉璃道馆在烈空坐平息固拉多和盖欧卡后开放。联盟依次挑战花月、芙蓉、波妮、源治和冠军米可利。

[安卓实拍 · 琉璃市的固拉多与盖欧卡](.github/preview/v4.56-sootopolis.png) · [安卓实拍 · 彩幽联盟冠军米可利](.github/preview/v4.56-wallace.png)

地图、地形、人物位置和训练家队伍的重建数据取自同一个《绿宝石》版本。[丰缘特殊道具获取与使用](doc/丰缘特殊道具.md) · [绿宝石源数据与地图脚本](https://github.com/pret/pokeemerald/tree/9103e529c2fbdd7add4a1ff3350c6c1f92112c42/data/maps)

## 从若叶镇到白银山

从关都经地区道路或地区转移器第一次进入城都，在若叶镇下楼从妈妈手中领取宝可装置，再到空木研究所从菊草叶、火球鼠和小锯鳄中选择伙伴。送回神奇的蛋后就能领精灵球。城都采用《水晶》的事件顺序，包括圆朱烧焦塔的水君线、满金电台和烟墨龙穴的问答。

集齐八枚城都徽章后，从若叶镇向东穿过都城瀑布和冠军之路，挑战四天王和阿渡。进名人堂后回若叶镇找空木博士领船票。搭水流号到枯叶，从发电厂找回零件、为收音机扩充频道，到拿齐关都八枚徽章。最后找真新镇的大木博士开放白银山，在山顶挑战赤红。[剧情与角色出场顺序](doc/城都剧情与人物.md) · [特殊道具获取与用法](doc/城都特殊道具.md)

在关都从尼比市往东走 3 号道路，首次进入月见山时，阿银会带着六只宝可梦等你。打赢后，每逢手机本地时间周一、周三，走到石英高原宝可梦中心东北侧通向四天王的走廊，可以再和他对战。当天获胜后他会离开，下一个约战日还会回来。

## 从真新镇开始

启动游戏先到《绿宝石》的烈空坐标题页。选择「新的冒险」从真新镇家中二楼的床边出发。走到右上方墙图前面朝上按 A，可翻看世界全景地图。在丰缘索引点「丰缘地图」，可以缩放《绿宝石》宝可导航的地区地图。下楼出门，走到真新镇北边的草丛，大木会带你去研究所领取初始伙伴。在研究所出口和小茂对战后，前往常磐商店领取包裹，交回大木后会同时收到图鉴和 5 个精灵球，常磐市北面的老人也会让路。草丛里可以遇敌、投球、练级，常磐市的宝可梦中心可以治疗队伍。经 2 号道路和常磐森林抵达尼比市，打赢小刚即可获得首枚徽章。本作沿用皮卡丘作为初始伙伴，小茂从伊布开始培养。

目前地图目录登记 1,662 张可达地图。九个主地区与十二个附属区域均有地图、步行入口和领航员，墙图登记了 555 个地点。24 条跨区通道包括海堤、栈道、隧道及山口。第一次从真新镇出发，可以直接找家外的领航员，点目标地区，再点「出发前往」。地图室、道路、道馆与室内房间保留各自的碰撞和进出点。新建地区侧重探索与交通。关都可以挑战到名人堂和七岛后日谈，城都可以走到白银山挑战赤红，丰缘可以走到彩幽联盟挑战米可利。

关都与七岛的 375 张地图采用《火红／叶绿》的 16 像素图块、调色板、地形属性和出入口编号。华蓝道馆的木桥可以步行，面向池水按 A 并确认冲浪后才会下水。城都沿用《心金／魂银》的房间尺寸、地形和出入口，用《火红／叶绿》和《绿宝石》的图块绘制场景。其他自建地区主要使用《绿宝石》素材。[地图与素材说明](doc/素材重建.md)

## 关都与七岛怎么玩

| 到了哪里 | 下一段剧情 |
| --- | --- |
| 华蓝市、枯叶市 | 到海角的小屋帮助正辉，拿船票上圣安奴号。在船上遇到小茂，帮助船长取得居合斩。船开走后，可从岸上继续挑战枯叶道馆。 |
| 玉虹市、紫苑镇、金黄市 | 从游戏厅海报找火箭队基地，取电梯钥匙和检视镜。在宝可梦塔顶救出富士老人，用宝可梦之笛唤醒卡比兽。金黄的守卫需要茶，西尔佛公司的门要用钥匙卡。 |
| 浅红市、红莲岛 | 在狩猎地带取金假牙和冲浪，替园长找回假牙学怪力。去宝可梦屋操作雕像开关，找到道馆的秘密钥匙。打赢夏伯后，正辉会在馆外邀请你去七岛。 |
| 第一次去七岛 | 到一之岛见锦辉，去三之岛赶走暴走族，在果实森林找回迷路的女孩，回二之岛交陨石。这段完成后可以回关都继续收集徽章。 |
| 常磐市、石英高原 | 打赢坂木，带齐八枚徽章通过关卡，推开胜利之路的岩石，连胜四天王与冠军，登记名人堂。 |
| 第二次去七岛 | 登记名人堂并实际拥有过 60 种关都宝可梦后，回真新镇找大木升级图鉴。去一之岛帮锦辉找红宝石，持彩虹通行证前往后续岛屿，帮助科拿、调查点之穴和火箭队仓库，取回蓝宝石并修复网络。 |

主线台词按本作改写。大木、小茂、正辉、富士老人、坂木、科拿和火箭队成员随事件登场或离开。可以用地区转移器提前看地图，推动剧情仍需在场景里完成对应事件。

## 特殊道具从哪里拿

关都的秘传学习器需到各自的赠送人或拾取点领取。居合斩找圣安奴号船长，冲浪找狩猎地带最深处的管理员，攀瀑要亲自穿过四之岛的薄冰。枯叶市、浅红市和 12 号道路的钓鱼人分别赠送破旧钓竿、好钓竿和厉害钓竿。在关都或七岛使用时，水域和竿的种类决定鱼群。

商店中打开「进化材料产地」，可以查到 40 种进化材料的购买地区。六之岛水路能捡到龙之鳞片，给海刺龙使用即可进化为刺龙王。在枯叶市宝可梦中心可以领取对战搜寻器，走满 100 步后在附近有已打败训练家的室外地点使用。地图上的学习器可教学，携带道具从队伍界面装备，战斗强化道具从场上的背包使用。[逐件查看获取地点、价格和使用示例](doc/进化道具获取.md)

标题页、背包、丰缘导航图和战斗场地采用原游戏图块与配色。前三世代宝可梦优先采用《绿宝石》正背面及异色，后来登场的宝可梦和形态使用与之相配的像素图。

## 队伍与触屏菜单

探索时点右上角 **START**，右侧会弹出图鉴、队伍、背包、电脑、工具和存档。点「工具」可以骑行、进入秘传或打开修改器，在宝可梦中心还能进入融合工坊。队员会飞翔或闪光时，在「秘传」选中该招即可使用，也可以教给其他队员。关掉图鉴等页面后，光标会回到刚才那一行。点地图空白处可直接收起菜单。键盘 Enter 开菜单，上下键选择、Enter 确认、Esc 返回。手柄可用 START、方向键及 A/B。

战斗时，右下角固定显示「战斗」「背包」「宝可梦」「逃跑」四项。点「战斗」查看每招的属性、威力和剩余 PP。当场可用的变身、Z 招式和太晶化在「特殊行动」里。出招时，受击一方的血条和 HP 数值一同逐渐下降，按各自行动顺序结算。点「宝可梦」可以滑动查看最多 12 名队员并换人。

- 同行队伍可带 12 只。满员后捕获的成员进电脑；在电脑中点选具体成员存入或取回，最后一只留在队伍中。旧存档的单箱收藏会迁入电脑。
- 队伍、背包、图鉴、修改器共用触屏控件。可以在卡片上直接滑动，松手后再点选。修改器支持按名字或编号查找、选招式和道具，保存后同时写入队伍与背包；取消会放弃本次草稿。
- 图鉴以主编号组织形态，1,025 个战斗物种归入 1,003 个主条目。按本作设计，22 只悖谬种归在其原型下。遇见铁辙迹后，输入 `990` 或铁辙迹可打开顿甲 No.0232 中的铁辙迹，战斗与存档继续使用铁辙迹自己的物种 ID。
- 图鉴默认列出已经见过的编号，详情只显示实际遇到或拥有的形态、闪光和战斗状态组合。地区形态、Mega、超极巨、不同属性、颜色、花纹和造型可单独查看。星星闪和方块闪共用该形态真实的异色配色，预览与战斗使用不同的闪光图形。太晶化按实际发动时的属性收录。多形态示例包括彩粉蝶的 20 种花纹、未知图腾的 28 种字形，以及霜奶仙的 9 种奶油 × 7 种糖饰。
- “该编号已捕获”表示物种收集进度。“已见过此外观”和“已拥有此外观”对应具体形态、闪光和太晶组合。查看图鉴不会新增记录。旧个体只有布尔型闪光字段时按星星闪迁移，缺少个体证据的旧历史只保留编号进度。

## 从源码安装

在 Godot 4.7.2 中导入本目录的 `project.godot`，按 F6 运行当前场景或 F5 启动游戏。命令行从项目根目录执行：

```bash
godot --headless --path . --import
godot --path .
tools/build_android.sh ../交付/PokeSaga-4.57.0-study.apk
```

构建 Android 需要匹配的 Godot 导出模板、JDK 17、Android SDK、platform-tools、build-tools 和 Godot 可访问的本机调试签名。已配置的机器可用 `GODOT_BIN`、`JAVA_HOME`、`ANDROID_HOME` 选择工具路径。本机脚本也识别 `~/Library/Application Support/PokeSagaBuild`。学习版使用 `Android Study` 导出预设，目标架构为 ARM64，输出为签名调试 APK。安装可用 `adb install -r ../交付/PokeSaga-4.56.0-study.apk`。

## 验证改动

从空存档验证关都出发、首次前往丰缘、挑战米可利，并重启读取丰缘名人堂记录：

```sh
python3 tools/test_hoenn_journey.py --godot godot --result-save /tmp/hoenn-champion.json
godot --headless --path . --script tools/test_hoenn_travel.gd
godot --headless --path . --script tools/test_region_journey.gd
```


```bash
godot --headless --path . -- --selftest
godot --headless --path . --script tools/test_world_returns.gd
godot --headless --path . --script tools/test_world_walks.gd
godot --headless --fixed-fps 60 --path . --script tools/test_field_mapping.gd
godot --headless --fixed-fps 60 --path . --script tools/test_firered_passages.gd
godot --headless --fixed-fps 60 --path . --script tools/test_frlg_story.gd
godot --headless --fixed-fps 60 --path . --script tools/test_world_atlas.gd
godot --headless --fixed-fps 60 --path . --script tools/test_region_transfer.gd
godot --headless --path . --script tools/test_npc_appearances.gd
python3 tools/test_first_chapter.py --godot /path/to/godot
python3 tools/test_kanto_journey.py --godot /path/to/godot
python3 tools/test_johto_journey.py --godot /path/to/godot
godot --headless --fixed-fps 60 --path . --script tools/test_kanto_campaign.gd
godot --headless --fixed-fps 60 --path . --script tools/test_evolution_items.gd
godot --headless --fixed-fps 60 --path . --script tools/test_collection.gd
godot --headless --fixed-fps 60 --path . --script tools/test_start_menu.gd
godot --headless --fixed-fps 60 --path . --script tools/test_battle_commands.gd
godot --headless --path . --script tools/test_dex_catalog.gd
godot --headless --fixed-fps 60 --path . --script tools/test_dex_sightings.gd
godot --headless --fixed-fps 60 --path . --script tools/test_battle_hp.gd
godot --headless --fixed-fps 60 --path . --script tools/test_johto_passage.gd
godot --headless --fixed-fps 60 --path . --script tools/test_johto_league.gd
godot --headless --fixed-fps 60 --path . --script tools/test_hoenn_ferry.gd
```

城都长流程从标题页另开若叶镇新档，经八馆、冠军之路、联盟、关都八馆和白银山。测试会在赤红战后重新读取存档，逐项核对队伍、背包、图鉴、徽章、名人堂和所在地图。特殊道具的通关档补测入口为 `tools/test_johto_item_journey.py --save <save.json> --godot <Godot>`。两条路线都支持用 `--pack` 指定从 APK 提取的游戏数据。角色出场与解锁条件可查阅[《金／银》白银山开放事件](https://github.com/pret/pokegold/blob/2bbfba60051acfbed96d68fb5e40173a06df67d8/maps/OaksLab.asm)及[《水晶》白银山山顶事件](https://github.com/pret/pokecrystal/blob/9ce4c4e5068ffdf56e23ca3d8dc9178b2465d482/maps/SilverCaveRoom3.asm)。

关都长流程从独立新档出发，通过游戏操作行走、捕捉、练级、交任务和打馆。通关后重启游戏，核对八枚徽章、名人堂、收藏、背包及七岛网络进度。联盟专项另测中途战败重置和强化版再战。手机图鉴专项 `tools/test_android_dex.py --help` 列出设备序列号、ADB 与截图目录参数；它在已安装学习版的横屏模拟器上按游戏画面坐标点击。

## 从素材开始学习

游戏自带运行所需的素材，直接导入工程即可游玩。重新制作图片、碰撞和音频的步骤及素材版本见 [素材重建说明](doc/素材重建.md)。核心代码集中在 `core/`，各触屏菜单在 `scenes/`，地图、剧情、招式、道具和形态表在 `content/`。

本项目用于非商业同人学习。宝可梦的名称与形象归相应权利人所有。中文字库的开放字体许可随 `assets/fonts/OFL.txt` 提供。
