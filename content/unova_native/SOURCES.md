# 合众场景来源与重建

《黑》与《黑2》的地图分别保存在 `bw/`、`b2/`。同一地名在两年前后的道路、建筑、角色对象及通行数据从各自的版本读取。绘制地形时先对照原模型材质和碰撞，再选用绿宝石地块。门的原始编号记在 `source_warp`，原角色位置记在 `unova_cast.source_at`。每张图可以通过 `unova_origin` 把本地图块换算为原世界坐标。

| 来源 | 本项目使用的数据 |
| --- | --- |
| [squiddonaut/pokeblack @ 67d91a7](https://github.com/squiddonaut/pokeblack/tree/67d91a78b16caccbd4fbecdddf8a74c823d208a6) | 《黑》的区域头、矩阵、地表权限、模型、纹理、实物、角色、脚本及轨道 |
| [fuddlesworth/pokebw2 @ 345b790](https://github.com/fuddlesworth/pokebw2/tree/345b790e6000869b481b79838bb5727309f832fb) | 《黑2》的相应场景、铁路、地图机关及脚本，原野人物动画和模型编号 |
| [pret/pokeemerald @ 9103e52](https://github.com/pret/pokeemerald/tree/9103e529c2fbdd7add4a1ff3350c6c1f92112c42) | 地面、道路、水岸和室外道具轮廓使用的《绿宝石》地块和色彩 |
| [Pokabbie/pokeemerald-rogue @ 5ccb74c](https://github.com/Pokabbie/pokeemerald-rogue/tree/5ccb74cf1ef2c0349dfa5d70883b030bbc9ff803) | N、魁奇思、阿克罗玛、两作劲敌、馆主、四天王等的 GBA 风格行走图 |

需要 Python、NumPy、SciPy、Pillow、C 编译器以及 [apicula](https://github.com/scurest/apicula)。从上述版本检出源码后，用以下命令重新生成。请将四个目录改为本机路径。

```sh
python3 tools/build_unova_maps.py --bw /path/to/pokeblack --b2 /path/to/pokebw2 --emerald /path/to/pokeemerald --apicula /path/to/apicula
python3 tools/import_unova_actor_art.py /path/to/pokebw2 /path/to/pokeemerald-rogue
python3 tools/build_unova_atlas.py
```

原作连续三维轨道在掌机画面中被投影成四向行走格。桥下水道与上层桥重叠时，桥面优先。部分原机关以站台、开关、跳跃和触屏动作表示。道馆、联盟及其他具名内景按固定视角绘制，运行时不重现 DS 镜头旋转。桧扇市展望台与驱逐舰的不同停靠状态复用其原始地图。联机专用、另一版本专用、演出专用和挑战内部实例保留原区域编号，并以 `unova_technical_reason` 标明用途。
