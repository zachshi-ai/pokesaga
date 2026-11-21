"""Build the touch inventory atlas from indexed item art and its original palettes."""
import json
import re
from gen_world_extras import ITEM_ZH
from pathlib import Path

from PIL import Image
from asset_paths import project_path, source_path


def main():
    data = Path(project_path("content"))
    src = Path(source_path("emerald", "graphics/items"))
    out = Path(project_path("assets/ui/field"))
    out.mkdir(parents=True, exist_ok=True)

    def load(name):
        return json.loads((data / (name + ".json")).read_text())

    # The upstream game shares geometry across potion strengths, TMs and shards.
    icons = {}
    def register(label, shape, palette=None):
        palette = palette or shape
        if (src / "icons" / (shape + ".png")).is_file() and (src / "icon_palettes" / (palette + ".pal")).is_file():
            icons[label] = (shape, palette)

    for row in load("items"):
        register(row["name"], row["key"].lower())
    for key, name in load("evo_items").items():
        register(name, key.lower())
    for key, row in load("berries").items():
        register(row["name"], key + "_berry")
    for key, name in load("tera_shards").items():
        register(name, "tera_shard", key + "_tera_shard")
    for name, shape, pal in [
        ("精灵球","poke_ball","poke_ball"),("超级球","great_ball","great_ball"),
        ("高级球","ultra_ball","ultra_ball"),("大师球","master_ball","master_ball"),
        ("伤药","potion","potion"),("好伤药","potion","super_potion"),("厉害伤药","potion","hyper_potion"),
        ("全满药","potion","max_potion"),("全复药","potion","full_restore"),
        ("解毒药","status_heal","antidote"),("解麻药","status_heal","paralyze_heal"),
        ("灼伤药","status_heal","burn_heal"),("解眠药","status_heal","awakening"),
        ("解冻药","status_heal","ice_heal"),("万灵药","status_heal","full_heal"),
        ("力量强化","battle_stat_item","x_attack"),("神奇糖果","rare_candy","rare_candy"),
        ("活力碎片","revive","revive"),("活力块","max_revive","max_revive"),
        ("钓竿","old_rod","old_rod"),("离洞绳","escape_rope","escape_rope"),
        ("TM","tm","normal_tm_hm"),("HM","hm","normal_tm_hm"),
        ("PP 单项小补剂","ether","ether"),("橙橙果","oran_berry","oran_berry"),
        ("携带","leftovers","leftovers"),("太晶","tera_shard","normal_tera_shard"),
        ("其他","tm_case","tm_case")
    ]:
        register(name, shape, pal)
    # Match item IDs through the upstream structure. Medicine, plates and drives
    # often share a silhouette while referencing completely different palettes.
    source_root = Path(source_path("emerald"))
    graphics = (source_root/"src/data/graphics/items.h").read_text()
    files = {symbol: Path(path).stem for symbol, path in re.findall(
        r'(gItemIcon\w+)\[\]\s*=\s*INCGFX_\w+\("([^"]+)"', graphics)}
    definitions = (source_root/"src/data/items.h").read_text()
    pairs = {}
    for ident, block in re.findall(r'\[ITEM_(\w+)\]\s*=\s*\{(.*?)\n\s*\},', definitions, re.S):
        shape = re.search(r'\.iconPic\s*=\s*(\w+)', block)
        palette = re.search(r'\.iconPalette\s*=\s*(\w+)', block)
        if shape and palette and shape[1] in files and palette[1] in files:
            pairs[ident] = (files[shape[1]], files[palette[1]])
    aliases = {value[0]:key.removeprefix("ITEM_") for key,value in ITEM_ZH.items()}
    for obj in load("items"):
        key = obj["key"].removeprefix("OGERPON_")
        if key.startswith("MEMORY_"):
            key = key[7:]+"_MEMORY"
        if key.startswith("ROTOM_"):
            key = "ROTOM_CATALOG"
        aliases[obj["name"]] = key
    aliases.update({"麻痹药":"PARALYZE_HEAL","熔岩饼干":"LAVA_COOKIE","PP 单项全补剂":"MAX_ETHER",
                    "PP 多项小补剂":"ELIXIR","PP 多项全补剂":"MAX_ELIXIR","PP 单项":"ETHER",
                    "PP 多项":"ELIXIR","PP 全满":"MAX_ELIXIR","力量强化":"X_ATTACK","圣灰":"SACRED_ASH",
                    "自行车":"MACH_BIKE","其他":"TM_CASE","携带":"LEFTOVERS","太晶":"NORMAL_TERA_SHARD",
                    "钓竿":"OLD_ROD","PP 提升剂":"PP_UP","优质伤药":"SUPER_POTION","地区转移器":"SCANNER"})
    for name, ident in aliases.items():
        if ident in pairs:
            register(name, *pairs[ident])
    shapes = sorted(set(icons.values()))
    if not shapes:
        raise FileNotFoundError(f"未找到 {src} 中的道具图片及调色板")
    step, cols = 24, 16
    sheet = Image.new("RGBA", (step * cols, step * ((len(shapes)+cols-1)//cols)))
    for i, (key, palette) in enumerate(shapes):
        pic = Image.open(src / "icons" / (key+".png"))
        if pic.mode != "P":
            raise ValueError(f"{key} 不是索引色图像")
        colors = [int(n) for ln in (src/"icon_palettes"/(palette+".pal")).read_text().splitlines()[3:] for n in ln.split()]
        pic.putpalette(colors)
        pic.info["transparency"] = 0
        tile = pic.convert("RGBA")
        tile.thumbnail((step,step),Image.Resampling.NEAREST)
        sheet.alpha_composite(tile,((i%cols)*step+(step-tile.width)//2, (i//cols)*step+(step-tile.height)//2))
    sheet.save(out/"bag_icons.png")
    (data/"ui_item_icons.json").write_text(json.dumps({k:shapes.index(v) for k,v in sorted(icons.items())},ensure_ascii=False,indent=1)+"\n")
    print(f"{len(icons)} 个道具名称，{len(shapes)} 个精灵图格")


if __name__ == "__main__":
    main()
