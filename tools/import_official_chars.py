#!/usr/bin/env python3
"""导出绿宝石原版角色图：玩家用 brendan 九帧行走图，NPC 用各职业的第一帧。

原图是 P 模式索引色，索引 0 需要转成透明，否则会带一块底色。
"""
import os
from PIL import Image

SRC = "/root/build/pokeemerald-expansion-master/graphics/object_events/pics/people"
OUT = "/root/build/pokesaga/assets"


def to_rgba(path):
    im = Image.open(path).convert("P")
    pal = im.getpalette()
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    px = im.load()
    op = out.load()
    for y in range(im.height):
        for x in range(im.width):
            v = px[x, y]
            if v == 0:
                continue
            r = pal[v * 3] if pal else 0
            g = pal[v * 3 + 1] if pal else 0
            b = pal[v * 3 + 2] if pal else 0
            op[x, y] = (r, g, b, 255)
    return out


# NPC 名字关键词 -> 原版人物图
ROLES = [
    ("护士", "nurse"),
    ("馆主", "brock"),
    ("博士", "professor_birch"),
    ("水手", "sailor"),
    ("港口", "sailor"),
    ("商人", "man"),
    ("老板", "man"),
    ("老伯", "old_man"),
    ("老人", "old_man"),
    ("爷爷", "old_man"),
    ("少女", "lass"),
    ("女孩", "lass"),
    ("少年", "youngster"),
    ("小子", "youngster"),
    ("捕虫", "bug_catcher"),
    ("登山", "hiker"),
    ("训练家", "cooltrainer_m"),
    ("导游", "camper"),
    ("游客", "camper"),
    ("旅人", "backpacker"),
    ("登记员", "clerk"),
    ("前台", "teala"),
]


def main():
    os.makedirs(os.path.join(OUT, "npc"), exist_ok=True)
    # 玩家：走路九帧
    walk = to_rgba(os.path.join(SRC, "brendan", "walking.png"))
    walk.save(os.path.join(OUT, "player_emerald.png"))
    print("player", walk.size)

    made, miss = [], []
    for _, key in ROLES:
        p = os.path.join(SRC, key + ".png")
        if not os.path.exists(p):
            # 有些人物在子目录里
            hit = None
            for root, _, files in os.walk(SRC):
                if key + ".png" in files:
                    hit = os.path.join(root, key + ".png")
                    break
            if hit is None:
                miss.append(key)
                continue
            p = hit
        im = to_rgba(p)
        # 取第一帧（16x32）
        frame = im.crop((0, 0, 16, 32))
        frame.save(os.path.join(OUT, "npc", key + ".png"))
        made.append(key)
    print("npcs", len(made), made)
    print("missing", miss)


if __name__ == "__main__":
    main()
