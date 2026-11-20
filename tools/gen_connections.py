#!/usr/bin/env python3
"""把原版的「地图连接」（connections）变成城际通道。

火红的岛/路是拼在一起的无缝地图，靠 connections 直接走过去，没有 warp。
我们这边每张图是独立场景，所以在接壤的那一列/一行可走格上放传送门，
走过去就到隔壁图的对应位置，效果和原版一路走到底差不多。
用法: python3 tools/gen_connections.py --region=sevii [--dry]
"""
import json
import os
import re
import sys

PJ = "/root/build/pokesaga"
ROOT = "/root/build/pokeemerald-expansion-master"
MD = os.path.join(ROOT, "data/maps")
EM = os.path.join(PJ, "content/emerald_maps")

REGION = "kanto"
for a in sys.argv:
    if a.startswith("--region="):
        REGION = a.split("=")[1]
DRY = "--dry" in sys.argv
REG = os.path.join(PJ, "content/regions/%s/maps" % REGION)


def norm(s):
    return re.sub(r"[^a-z0-9]", "", str(s).lower().replace("frlg", ""))


def main():
    rooms = {}
    for f in os.listdir(REG):
        if f.endswith(".json"):
            rooms[f[:-5]] = json.load(open(os.path.join(REG, f)))
    # 原版 id -> 房间 id
    by_norm = {}
    for k in rooms:
        by_norm[norm(k)] = k
        by_norm["map" + norm(k)] = k
    srcmaps = {}
    for d in os.listdir(MD):
        if not d.endswith("_Frlg"):
            continue
        try:
            m = json.load(open(os.path.join(MD, d, "map.json")))
        except Exception:
            continue
        srcmaps[norm(str(m.get("id", "")))] = (d, m)

    cols = {}
    for gid, r in rooms.items():
        p = os.path.join(EM, str(r.get("emerald", "")) + ".json")
        if r.get("emerald") and os.path.exists(p):
            cols[gid] = json.load(open(p)).get("collision") or []

    made = 0
    for key, (d, m) in srcmaps.items():
        gid = by_norm.get(norm(str(m.get("id", "")))) or by_norm.get("map" + norm(d[:-5]))
        if not gid or gid not in cols:
            continue
        col = cols[gid]
        H, W = len(col), len(col[0])
        for c in m.get("connections") or []:
            tgt = by_norm.get(norm(str(c.get("map", ""))))
            if not tgt or tgt == gid or tgt not in cols:
                continue
            off = int(c.get("offset", 0)) // 16
            direction = str(c.get("direction", ""))
            tcol = cols[tgt]
            TH, TW = len(tcol), len(tcol[0])
            pairs = []
            if direction == "right":
                for y in range(H):
                    ty = y - off
                    if not (0 <= ty < TH):
                        continue
                    if int(col[y][W - 1]) != 0 or int(tcol[ty][0]) != 0:
                        continue
                    pairs.append(([W - 1, y], [0, ty]))
            elif direction == "left":
                for y in range(H):
                    ty = y - off
                    if not (0 <= ty < TH):
                        continue
                    if int(col[y][0]) != 0 or int(tcol[ty][TW - 1]) != 0:
                        continue
                    pairs.append(([0, y], [TW - 1, ty]))
            elif direction == "down":
                for x in range(W):
                    tx = x - off
                    if not (0 <= tx < TW):
                        continue
                    if int(col[H - 1][x]) != 0 or int(tcol[0][tx]) != 0:
                        continue
                    pairs.append(([x, H - 1], [tx, 0]))
            elif direction == "up":
                for x in range(W):
                    tx = x - off
                    if not (0 <= tx < TW):
                        continue
                    if int(col[0][x]) != 0 or int(tcol[TH - 1][tx]) != 0:
                        continue
                    pairs.append(([x, 0], [tx, TH - 1]))
            if not pairs:
                # 原版 offset 对不同尺寸的图不好换算，退化成「两边按顺序等距配对」
                a_edge, b_edge = [], []
                if direction in ("right", "left"):
                    ax = W - 1 if direction == "right" else 0
                    bx = 0 if direction == "right" else TW - 1
                    a_edge = [[ax, y] for y in range(H) if int(col[y][ax]) == 0]
                    b_edge = [[bx, y] for y in range(TH) if int(tcol[y][bx]) == 0]
                else:
                    ay = H - 1 if direction == "down" else 0
                    by = 0 if direction == "down" else TH - 1
                    a_edge = [[x, ay] for x in range(W) if int(col[ay][x]) == 0]
                    b_edge = [[x, by] for x in range(TW) if int(tcol[by][x]) == 0]
                if a_edge and b_edge:
                    n = min(len(a_edge), len(b_edge), 8)
                    for i in range(n):
                        ai = i * (len(a_edge) - 1) // max(1, n - 1) if n > 1 else 0
                        bi = i * (len(b_edge) - 1) // max(1, n - 1) if n > 1 else 0
                        pairs.append((a_edge[ai], b_edge[bi]))
            if not pairs:
                continue
            # 每一对都接上（边缘可走格本来就少，一格格接最贴近原版走法）
            for a_cell, b_cell in pairs:
                if not any(list(w["at"]) == a_cell and (w["to"] or {}).get("map") == tgt
                           for w in rooms[gid]["warps"]):
                    rooms[gid].setdefault("warps", []).append(
                        {"at": a_cell, "to": {"region": REGION, "map": tgt, "at": b_cell}})
                    made += 1
                if not any(list(w["at"]) == b_cell and (w["to"] or {}).get("map") == gid
                           for w in rooms[tgt]["warps"]):
                    rooms[tgt].setdefault("warps", []).append(
                        {"at": b_cell, "to": {"region": REGION, "map": gid, "at": a_cell}})
                    made += 1
            print("  连接 %-34s %s -> %-34s %d 格" % (gid, direction, tgt, len(pairs)))

    if not DRY:
        for gid, r in rooms.items():
            json.dump(r, open(os.path.join(REG, gid + ".json"), "w"), ensure_ascii=False, indent=1)
    print("%s 新建连接门 %d 个" % (REGION, made))


if __name__ == "__main__":
    main()
