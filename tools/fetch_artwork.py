#!/usr/bin/env python3
"""补拉官方立绘（缺的才拉），jsDelivr 优先，回退 GitHub raw。"""
from asset_paths import project_path, cache_path

import json
import os
import urllib.request
from concurrent.futures import ThreadPoolExecutor

OUT = project_path("assets/party_hd")
RAW = cache_path("official-artwork-c0542f7")
SIZE = 128

SRC = [
    "https://cdn.jsdelivr.net/gh/PokeAPI/sprites@c0542f7c51215d9672439012838c99f520596cbd/sprites/pokemon/other/official-artwork/%d.png",
    "https://raw.githubusercontent.com/PokeAPI/sprites/c0542f7c51215d9672439012838c99f520596cbd/sprites/pokemon/other/official-artwork/%d.png",
]


def get(url, timeout):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 pokesaga"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def fetch(sid):
    dst = os.path.join(RAW, "%d.png" % sid)
    if os.path.exists(dst) and os.path.getsize(dst) > 1000:
        return sid, True
    for u in SRC:
        for attempt in range(2):
            try:
                data = get(u % sid, 20)
                if len(data) > 1000:
                    with open(dst, "wb") as f:
                        f.write(data)
                    return sid, True
            except Exception:
                continue
    return sid, False


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(RAW, exist_ok=True)
    species = json.load(open(project_path("content/species.json")))
    ids = sorted({int(s["id"]) for s in species if int(s["id"]) > 0})
    miss = [i for i in ids if not (os.path.exists(os.path.join(RAW, "%d.png" % i))
                                   and os.path.getsize(os.path.join(RAW, "%d.png" % i)) > 1000)]
    print("缺 %d / %d" % (len(miss), len(ids)), flush=True)
    ok = 0
    bad = []
    with ThreadPoolExecutor(max_workers=24) as ex:
        for n, (sid, good) in enumerate(ex.map(fetch, miss)):
            if good:
                ok += 1
            else:
                bad.append(sid)
            if (n + 1) % 50 == 0:
                print("  %d/%d" % (n + 1, len(miss)), flush=True)
    print("补到 %d，仍缺 %d %s" % (ok, len(bad), bad[:12]), flush=True)

    from PIL import Image
    made = 0
    for sid in ids:
        src = os.path.join(RAW, "%d.png" % sid)
        if not os.path.exists(src):
            continue
        try:
            im = Image.open(src).convert("RGBA")
        except Exception:
            continue
        im.thumbnail((SIZE, SIZE), Image.LANCZOS)
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        canvas.paste(im, ((SIZE - im.width) // 2, (SIZE - im.height) // 2))
        canvas.save(os.path.join(OUT, "%d.png" % sid), optimize=True)
        made += 1
    print("生成 %d 张" % made, flush=True)
    if made != len(ids):
        raise SystemExit("有立绘未成功获取或转换")


if __name__ == "__main__":
    main()
