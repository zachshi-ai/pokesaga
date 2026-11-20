# PokeSaga

Godot 4.7.2 制作的多地区宝可梦同人游戏（Android）。关都、七岛、城都三套地图，战斗、图鉴、队伍、背包、电脑、修改器、融合、秘传技能、昼夜与天气全部在同一个工程里。

- 包名：`com.stepx.pokesaga`
- 引擎：Godot 4.7.2（`renderer` 用兼容模式，横屏 480×320，`aspect=keep`）
- 当前版本：4.46.0（versionCode 79）
- 安装包：见 Releases 页

## 目录

```
scenes/      boot.gd（主控 + 自检）、battle_ui、party_ui、dex_ui、bag_ui、pc_ui、shop_ui、editor_ui、fusion_ui、form_item_ui、dialog_ui
core/        world（地图/移动/坡/水面/树冠）、battle、data_hub、party、growth、encounter、facility、field、fusion、save_game、sound、story、touch_scroll
content/     regions/{kanto,sevii,johto,frontier,hoenn}/maps/*.json + emerald_maps/*.json+png（+*_fg.png）
             items / moves / species / abilities / berries / tm_map / trainers_db / story
assets/      tiles 图集、人物与树冠贴花、party_hd 立绘（1025 张 128×128）、audio（26 BGM + 16 SFX）
tools/       地图渲染、连边生成、落点修正、告示牌文本等离线脚本
```

## 自己编译

需要 Godot 4.7.2 与 Android 导出模板：

```bash
godot --headless --path . -- --selftest            # 65 项自检
godot --headless --path . --export-release "Android" PokeSaga.apk
```

导出配置见 `export_presets.cfg`（版本号在第 34/35 行）。

## 素材来源

- 地图数据：pokeemerald-expansion（GBA 关都/七岛）与 pokecrystal（城都），自建渲染管线导出为 PNG + 碰撞/坡/水面网格
- 立绘：PokeAPI official-artwork，缩放到 128×128
- 音频：原版曲谱 `.mid` + 自写合成器渲染成 ogg，不含 ROM 采样

本项目为非商业同人作品，宝可梦相关名称与形象版权归任天堂 / Game Freak / Creatures 所有。
