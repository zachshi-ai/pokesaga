#!/usr/bin/env python3
"""修告示牌文本（第二版）。

火红的脚本里文字不写在牌子标签下面，而是
  某EventScript::  msgbox SomeTextLabel
  某TextLabel::   .string "..."
所以先全局建"文本标签 -> 文字"，再顺着 msgbox 找到牌子真正要说的那句。
以前的做法是把整张图的 .string 全连一起，牌子上全是别人的对话。
"""
from asset_paths import project_path, source_path

import json
import os
import re

ROOT = project_path()
SRC_MAPS = source_path("emerald", "data/maps")
SRC_EXTRA = source_path("emerald", "data")
LABEL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)::?\s*$")


def scan_file(path):
    """返回 (labels, texts)：labels 标签->正文行；texts 文本标签->字符串"""
    labels, texts = {}, {}
    cur, body = None, []
    with open(path, errors="ignore") as f:
        for raw in f:
            line = raw.rstrip("\n")
            m = LABEL.match(line.strip())
            if m and (line[:1] not in ("\t", " ")):
                if cur:
                    labels[cur] = body
                cur, body = m.group(1), []
                continue
            if cur is None:
                continue
            body.append(line)
    if cur:
        labels[cur] = body
    for lab, lines in labels.items():
        parts = []
        for ln in lines:
            s = ln.strip()
            if s.startswith(".string"):
                t = s[s.find('"') + 1:]
                if t.endswith('"'):
                    t = t[:-1]
                parts.append(t)
        if parts:
            t = "".join(parts)
            t = (t.replace("\\n", "\n").replace("\\p", "\n").replace("\\l", "")
                 .replace("$", "").replace('\\"', '"').replace("{PLAYER}", "你").strip())
            if t:
                texts[lab] = t
    return labels, texts


def build_global_texts():
    texts = {}
    for base, dirs, files in os.walk(SRC_EXTRA):
        for f in files:
            if not f.endswith(".inc"):
                continue
            try:
                _l, t = scan_file(os.path.join(base, f))
            except Exception:
                continue
            for k, v in t.items():
                texts.setdefault(k, v)
    return texts


MB = re.compile(r"^\s*(?:msgbox|message)\s+([A-Za-z_][A-Za-z0-9_]*)")


def build_sign_index(global_texts):
    """源地图目录 -> [(x, y, text)]"""
    idx = {}
    for d in sorted(os.listdir(SRC_MAPS)):
        p = os.path.join(SRC_MAPS, d)
        mp, sp = os.path.join(p, "map.json"), os.path.join(p, "scripts.inc")
        if not (os.path.exists(mp) and os.path.exists(sp)):
            continue
        try:
            m = json.load(open(mp))
        except Exception:
            continue
        signs = [b for b in m.get("bg_events", []) if str(b.get("type")) == "sign"]
        if not signs:
            continue
        labels, _t = scan_file(sp)
        rows = []
        for b in signs:
            lab = str(b.get("script", ""))
            text = ""
            for ln in labels.get(lab, []):
                mm = MB.match(ln)
                if mm:
                    text = global_texts.get(mm.group(1), "")
                    if text:
                        break
            if not text:
                text = global_texts.get(lab, "")
            if text:
                rows.append((int(b["x"]), int(b["y"]), text))
        if rows:
            idx[d] = rows
    return idx


def fix_map(path, idx):
    data = json.load(open(path))
    signs = [o for o in data.get("objects", []) if o.get("kind") == "sign"]
    if not signs:
        return 0
    ours = [(int(o["at"][0]), int(o["at"][1]), o) for o in signs]
    best = None
    for d, rows in idx.items():
        cnt = {}
        for (x, y, _o) in ours:
            for (sx, sy, _t) in rows:
                k = (x - sx, y - sy)
                cnt[k] = cnt.get(k, 0) + 1
        if not cnt:
            continue
        (dx, dy), n = max(cnt.items(), key=lambda kv: (kv[1], -abs(kv[0][0]) - abs(kv[0][1])))
        score = (n, -abs(dx) - abs(dy))
        if best is None or score > (best[0], -abs(best[2]) - abs(best[3])):
            best = (n, d, dx, dy)
    changed = 0
    lookup = {}
    if best:
        _n, d, dx, dy = best
        lookup = {(sx + dx, sy + dy): t for (sx, sy, t) in idx[d]}
    for (x, y, o) in ours:
        t = lookup.get((x, y))
        if t:
            if o.get("text") != t:
                o["text"] = t
                changed += 1
            continue
        cur = str(o.get("text", ""))
        if len(cur) > 100:
            o["text"] = cur[:70].rstrip() + "……"
            changed += 1
    if changed:
        json.dump(data, open(path, "w"), ensure_ascii=False, indent=1)
    return changed


def main():
    global_texts = build_global_texts()
    idx = build_sign_index(global_texts)
    print("源地图 %d 张有牌子文本，全局文本 %d 条" % (len(idx), len(global_texts)))
    total = 0
    for reg in ("kanto", "sevii"):
        base = os.path.join(ROOT, "content/regions", reg, "maps")
        for f in sorted(os.listdir(base)):
            if f.endswith(".json"):
                total += fix_map(os.path.join(base, f), idx)
    print("修告示牌 %d 块" % total)


if __name__ == "__main__":
    main()
