# PokeSaga —— 多地区宝可梦 RPG 底座

目标：一个底座装下所有地区（关都 / 城都 / 丰缘 / 神奥 / 合众 / 卡洛斯 / 阿罗拉 / 伽勒尔 / 帕底亚），
新增地区只加资源包，不改内核代码。

## 分层

- `core/` 内核：数据加载、地图与碰撞、战斗、存档。代码里不出现任何具体地区的名字。
- `content/` 内容：通用表（物种/招式/属性）+ `regions/<地区>/`。每个地区自带 `region.json` 和地图 JSON。
- `scenes/` 表现层：启动、后续的战斗界面、菜单、修改器面板。

## 数据格式

- `content/types.json`：属性克制表，attacker -> {defender: 倍率}，未列出一律 1.0
- `content/species.json`：物种（id / 名称 / 属性 / 种族值 / 捕获率 / 成长曲线）
- `content/moves.json`：招式（id / 名称 / 属性 / 威力 / 命中 / PP / 物理特殊 / 附加效果）
- `content/regions/<id>/region.json`：地区元信息（名称、图块集、BGM、地图列表）
- `content/regions/<id>/maps/<map>.json`：地图（尺寸、瓦片二维数组、出生点、NPC、传送点）

## 自检

```
/root/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --quit-after 120
```

覆盖：数据表加载、地图加载、碰撞与移动、跨地区传送、战斗回合跑完、存档读写。
当前 6/6 通过。

## 设计约定

1. 战斗是纯逻辑（`core/battle.gd`），不引用渲染和输入，可在 headless 下跑几万场做回归。
2. 存档一份跨地区，结构与地区解耦：`region` + `map` + `pos` + `party` + `flags` + `dex`。
3. 新增地区不新增引擎分支；地区差异通过数据字段表达（图块集、遭遇表、规则开关）。
