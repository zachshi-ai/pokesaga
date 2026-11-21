# PokeSaga · 安卓学习版

用 Godot 4.7.2 开发的横屏宝可梦同人 RPG。当前学习版为 `4.50.0-study`，versionCode 为 83，包名为 `com.stepx.pokesaga.study`。它可以和 4.46 版同时安装，两份应用分别保存进度。

## 从真新镇开始

启动游戏先到《绿宝石》的烈空坐标题页。选择「新的冒险」从真新镇家中二楼的床边出发。走到右上方墙图前面朝上按 A，可翻看世界全景地图。在丰缘索引点「丰缘地图」，可以缩放《绿宝石》宝可导航的地区地图。下楼出门，进大木研究所选择初始伙伴，再向北进入 1 号道路。草丛里可以遇敌、投球、练级，常磐市的宝可梦中心可以治疗队伍。经 2 号道路和常磐森林抵达尼比市，打赢小刚即可获得首枚徽章。城都另有八徽章门禁、四天王、冠军与名人堂登记。

本版共 1,230 张地图。九个主地区与十二个附属区域均有地图、步行入口和领航员，墙图登记了 555 个地点。24 条跨区通道包括海堤、栈道、隧道及山口。第一次从真新镇出发，可以直接找家外的领航员，点目标地区，再点「出发前往」。地图室、道路、道馆与室内房间保留各自的碰撞和进出点。新建地区侧重探索与交通；首枚徽章和城都联盟已有可游玩的剧情。

场景以 GBA《绿宝石》的 16 像素地图块搭建。真新镇使用丰缘的房屋和家具；大木、小刚等关都专属人物使用同世代《火红》的像素角色。标题页、背包、丰缘导航图和战斗场地采用原游戏图块与配色。前三世代宝可梦优先采用《绿宝石》正背面及异色，后来登场的宝可梦和形态使用与之相配的像素图。各地图的通行、剧情和存档继续使用本作的坐标。[地图与素材说明](doc/素材重建.md)

## 队伍与触屏菜单

探索时点右上角 **START**，右侧会弹出图鉴、队伍、背包、电脑、工具和存档。点「工具」可以骑行、使用闪光、飞行、秘传或打开修改器，在宝可梦中心还能进入融合工坊。关掉图鉴等页面后，光标会回到刚才那一行。点地图空白处可直接收起菜单。键盘 Enter 开菜单，上下键选择、Enter 确认、Esc 返回。手柄可用 START、方向键及 A/B。

战斗时，右下角固定显示「战斗」「背包」「宝可梦」「逃跑」四项。点「战斗」查看每招的属性、威力和剩余 PP。当场可用的变身、Z 招式和太晶化在「特殊行动」里。点「宝可梦」可以滑动查看最多 12 名队员并换人。

- 同行队伍可带 12 只。满员后捕获的成员进电脑；在电脑中点选具体成员存入或取回，最后一只留在队伍中。旧存档的单箱收藏会迁入电脑。
- 队伍、背包、图鉴、修改器共用触屏控件。可以在卡片上直接滑动，松手后再点选。修改器支持按名字或编号查找、选招式和道具，保存后同时写入队伍与背包；取消会放弃本次草稿。
- 图鉴以主编号组织形态，1,025 个战斗物种归入 1,003 个主条目。按本作设计，22 只悖谬种归在其原型下。输入 `990` 或铁辙迹会打开顿甲 No.0232 中的铁辙迹，战斗与存档继续使用铁辙迹自己的物种 ID。
- 图鉴详情分别选形态、闪光和战斗状态。地区形态、Mega、超极巨、不同属性、颜色、花纹和造型可单独查看。星星闪和方块闪共用该形态真实的异色配色，预览与战斗使用不同的闪光图形。普通极巨和通用太晶采用图层表现。多形态示例包括彩粉蝶的 20 种花纹、未知图腾的 28 种字形，以及霜奶仙的 9 种奶油 × 7 种糖饰。
- “该编号已捕获”表示物种收集进度。“外观预览”“已见过此外观”“已拥有此外观”对应具体形态、闪光和太晶组合。图鉴预览不会新增捕获记录。旧个体只有布尔型闪光字段时按星星闪迁移，缺少个体证据的旧历史只保留编号进度。

## 从源码安装

在 Godot 4.7.2 中导入本目录的 `project.godot`，按 F6 运行当前场景或 F5 启动游戏。命令行从项目根目录执行：

```bash
godot --headless --path . --import
godot --path .
tools/build_android.sh ../交付/PokeSaga-4.50.0-study.apk
```

构建 Android 需要匹配的 Godot 导出模板、JDK 17、Android SDK、platform-tools、build-tools 和 Godot 可访问的本机调试签名。已配置的机器可用 `GODOT_BIN`、`JAVA_HOME`、`ANDROID_HOME` 选择工具路径。本机脚本也识别 `~/Library/Application Support/PokeSagaBuild`。学习版使用 `Android Study` 导出预设，目标架构为 ARM64，输出为签名调试 APK。安装可用 `adb install -r ../交付/PokeSaga-4.50.0-study.apk`。

## 验证改动

```bash
godot --headless --path . -- --selftest
godot --headless --path . --script tools/test_world_returns.gd
godot --headless --path . --script tools/test_world_walks.gd
godot --headless --fixed-fps 60 --path . --script tools/test_world_atlas.gd
godot --headless --path . --script tools/test_npc_appearances.gd
python3 tools/test_first_chapter.py --godot /path/to/godot
godot --headless --fixed-fps 60 --path . --script tools/test_collection.gd
godot --headless --fixed-fps 60 --path . --script tools/test_start_menu.gd
godot --headless --fixed-fps 60 --path . --script tools/test_battle_commands.gd
godot --headless --path . --script tools/test_dex_catalog.gd
godot --headless --fixed-fps 60 --path . --script tools/test_johto_passage.gd
godot --headless --fixed-fps 60 --path . --script tools/test_johto_league.gd
godot --headless --fixed-fps 60 --path . --script tools/test_hoenn_ferry.gd
```

首章测试用独立新档实际走路、遇敌、投球、治疗、打馆，再启动第二个进程读回徽章。联盟测试会检查门禁、战败治疗、五连战及名人堂快照。手机图鉴专项 `tools/test_android_dex.py --help` 列出设备序列号、ADB 与截图目录参数；它在已安装学习版的横屏模拟器上按游戏画面坐标点击。

## 从素材开始学习

游戏自带运行所需的素材，直接导入工程即可游玩。重新制作图片、碰撞和音频的步骤及素材版本见 [素材重建说明](doc/素材重建.md)。核心代码集中在 `core/`，各触屏菜单在 `scenes/`，地图、剧情、招式、道具和形态表在 `content/`。

本项目用于非商业同人学习。宝可梦的名称与形象归相应权利人所有。中文字库的开放字体许可随 `assets/fonts/OFL.txt` 提供。
