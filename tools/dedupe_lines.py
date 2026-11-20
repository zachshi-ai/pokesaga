#!/usr/bin/env python3
"""同一张图里两个 NPC 台词完全相同就重写后者的最后一句。

批量生成的居民台词是组合出来的，跨图撞车无所谓（自检只查同一张图内），
但同一张图里出现两段一模一样的对话会显得像复制粘贴，这里按一张图内去重。
用法: python3 tools/dedupe_lines.py [--dry]
"""
from asset_paths import project_path

import json
import os
import sys

PJ = project_path()
REGIONS = os.path.join(PJ, "content/regions")

POOL = [
    "我也是刚搬来的。", "这条路我天天走。", "你要去哪儿？", "别在门口站着。",
    "最近安静得很。", "东西都涨价了。", "我这儿有张旧地图。", "听说有人在山里迷路。",
    "宝可梦比人好相处。", "记得带够球。", "这附近有野生的。", "我孙子也玩这个。",
    "天气要变了。", "晚上别乱走。", "这栋楼有点年头。", "我什么都不知道。",
]


def main():
    dry = "--dry" in sys.argv
    total = 0
    for rid in sorted(os.listdir(REGIONS)):
        d = os.path.join(REGIONS, rid, "maps")
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not f.endswith(".json"):
                continue
            p = os.path.join(d, f)
            m = json.load(open(p))
            npcs = m.get("npcs") or []
            seen = {}
            changed = False
            k = 0
            for n in npcs:
                ls = n.get("lines") or []
                if not ls:
                    continue
                key = String_key = n.get("name", "") + "|" + "|".join(ls)
                if key not in seen:
                    seen[key] = True
                    continue
                # 撞了就换最后一句，直到不撞
                for _ in range(len(POOL)):
                    ls2 = list(ls[:-1]) + [POOL[k % len(POOL)]]
                    k += 1
                    key2 = n.get("name", "") + "|" + "|".join(ls2)
                    if key2 not in seen:
                        n["lines"] = ls2
                        seen[key2] = True
                        changed = True
                        break
            if changed:
                total += 1
                if not dry:
                    json.dump(m, open(p, "w"), ensure_ascii=False, indent=1)
                print("  改写台词", rid + "/" + f[:-5])
    print("处理 %d 张图" % total)


if __name__ == "__main__":
    main()
