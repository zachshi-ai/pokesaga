"""Build the display catalog from PokeAPI CSV and PokeSaga's playable species.
Pass --csv-dir to use a local PokeAPI data/v2/csv checkout, otherwise pinned
CSV files are downloaded into the converter cache. The runtime is offline.
"""
import argparse
import csv
import json
import re
import urllib.request
from collections import defaultdict
from pathlib import Path

from asset_paths import cache_path, project_path

REVISION = "193d8d4fbb57cf962e3f7c1ce5299a6fe847b3f8"
DATA = Path(project_path("content"))
PARADOX = {
    984:232, 985:39, 986:591, 987:200, 988:637, 989:82, 990:232, 991:225,
    992:297, 993:635, 994:637, 995:248, 1005:373, 1006:475, 1007:967, 1008:967,
    1009:245, 1010:640, 1020:244, 1021:243, 1022:639, 1023:638,
}
SWEETS = dict(strawberry="草莓", berry="莓果", love="爱心", star="星星", clover="幸运草", flower="花朵", ribbon="蝴蝶结")
CREAMS = {"vanilla-cream":"奶香香草","ruby-cream":"奶香红钻","matcha-cream":"奶香抹茶","mint-cream":"奶香薄荷",
          "lemon-cream":"奶香柠檬","salted-cream":"奶香雪盐","ruby-swirl":"红钻综合","caramel-swirl":"焦糖综合","rainbow-swirl":"三色综合"}
SPECIAL = {"battle-bond":"牵绊变身特性", "belle":"贵妇", "cosplay":"换装", "libre":"面罩摔角手", "phd":"博士",
           "pop-star":"偶像歌手", "rock-star":"硬摇滚", "own-tempo":"我行我素特性", "spiky-eared":"刺刺耳",
           "starter":"搭档", "totem":"霸主", "totem-alola":"阿罗拉霸主", "totem-busted":"霸主·现形", "totem-disguised":"霸主·化形",
           "plant":"草木蓑衣", "trash":"垃圾蓑衣", "sandy":"砂土蓑衣"}
COLORS = {669,670,671,550,422,423,585,586,774,931,978}
STYLES = {25,412,413,414,676,741,710,711,869,925,982,1007,1008}
SOURCE_ALIAS = {
    20:{"totem-alola":"ALOLA_TOTEM"},105:{"totem":"ALOLA_TOTEM"},
    678:{"female":"F","male-mega":"M_MEGA"},
    876:{"female":"F"},902:{"female":"F"},916:{"female":"F"},
    800:{"dusk":"DUSK_MANE","dawn":"DAWN_WINGS"},
    925:{"family-of-four":"FOUR"}, 801:{"original":"ORIGINAL_COLOR"},
}
LEGACY_KEYS = {"eevee-starter":["EEVEE_PARTNER"], "basculin-white-striped":["BASCULIN_HISUI"],
               "magearna-original":["MAGEARNA_ORIGINAL"], "ogerpon":["OGERPON_TEAL"]}
LOCAL_ONLY = {"SPINDA_SPOTS", "OGERPON_TEAL_TERA", "OGERPON_WELLSPRING_TERA", "OGERPON_HEARTHFLAME_TERA", "OGERPON_CORNERSTONE_TERA"}


def upper(key):
    return key.upper().replace("-", "_")


def get_tables(folder):
    def read(name):
        path = folder / (name + ".csv")
        if not path.is_file():
            folder.mkdir(exist_ok=True, parents=True)
            url = f"https://raw.githubusercontent.com/PokeAPI/pokeapi/{REVISION}/data/v2/csv/{path.name}"
            raw = urllib.request.urlopen(url, timeout=60).read()
            path.write_bytes(raw)
        with path.open(encoding="utf8") as f:
            return list(csv.DictReader(f))
    names = ["pokemon_species", "pokemon_species_names", "pokemon", "pokemon_forms", "pokemon_form_names",
             "pokemon_types", "pokemon_form_types", "types", "pokemon_stats", "pokemon_abilities"]
    return {n:read(n) for n in names}


def tokens_for(sid, species, slug, suffix):
    raw = upper(slug)
    candidates = [raw]
    if sid == 666:
        candidates.append("SPEWPA_" + upper(suffix))
    if sid == 25 and suffix.endswith("-cap"):
        candidates.append("PIKACHU_" + upper(suffix.removesuffix("-cap")))
    if sid == 128:
        candidates.append(raw.removesuffix("_BREED"))
    if sid == 931:
        candidates.append(raw.removesuffix("_PLUMAGE"))
    if sid == 1017:
        candidates.append(raw.removesuffix("_MASK"))
    if sid == 774 and not suffix.endswith("-meteor"):
        candidates.append("MINIOR_CORE_" + upper(suffix))
    if sid == 869 and suffix.endswith("-sweet"):
        cream, sweet = suffix.removesuffix("-sweet").rsplit("-", 1)
        if cream == "vanilla-cream":
            candidates.append("ALCREMIE_" + upper(sweet))
        if sweet == "strawberry":
            candidates.append("ALCREMIE_" + upper(cream))
    su = SOURCE_ALIAS.get(sid, {}).get(slug.removeprefix(species + "-"))
    if su:
        candidates.insert(0, upper(species) + "_" + su)
    return candidates


def classify(sid, suffix, slug, is_base, local):
    if is_base: return "base"
    if "mega" in slug.split("-"): return "mega"
    if "gmax" in slug: return "gmax"
    if sid in (493,773): return "type"
    if sid in (201,664,665,666): return "pattern"
    if suffix in ("male","female"): return "gender"
    if sid != 25 and re.search(r"-(?:alola|galar|hisui|paldea)(?:-|$)", slug): return "regional"
    if sid in COLORS: return "color"
    if sid in STYLES: return "style"
    if local.get("battle_only") or local.get("kind") == "battle" or "totem" in suffix: return "battle"
    return "form"


def build(tab):
    local_species = {r["id"]:r for r in json.loads((DATA / "species.json").read_text())}
    type_names = json.loads((DATA / "types_cn.json").read_text())
    source_species = {int(r["id"]):r for r in tab["pokemon_species"]}
    pokemon = {int(r["id"]):int(r["species_id"]) for r in tab["pokemon"]}
    names = {(int(r["pokemon_species_id"]),r["local_language_id"]):r["name"] for r in tab["pokemon_species_names"]}
    labels = {(int(r["pokemon_form_id"]),r["local_language_id"]):r["form_name"] for r in tab["pokemon_form_names"]}
    types = {r["id"]:r["identifier"] for r in tab["types"]}
    mon_types, form_types, stats, abilities = defaultdict(list), defaultdict(list), defaultdict(dict), defaultdict(list)
    for table, field, out in [("pokemon_types","pokemon_id",mon_types),("pokemon_form_types","pokemon_form_id",form_types)]:
        for r in sorted(tab[table],key=lambda r:int(r["slot"])):
            out[int(r[field])].append(types[r["type_id"]])
    for r in tab["pokemon_stats"]:
        if 0 < int(r["stat_id"]) <= 6:
            stats[int(r["pokemon_id"])][("hp","atk","def","spa","spd","spe")[int(r["stat_id"])-1]] = int(r["base_stat"])
    for r in sorted(tab["pokemon_abilities"],key=lambda r:int(r["slot"])):
        abilities[int(r["pokemon_id"])].append(int(r["ability_id"]))
    patterns = {r["form_identifier"]:labels.get((int(r["id"]),"12"),"") for r in tab["pokemon_forms"] if pokemon[int(r["pokemon_id"])] == 666}
    forms = defaultdict(list)
    for r in tab["pokemon_forms"]:
        forms[pokemon[int(r["pokemon_id"])]].append(r)
    all_rows = {}
    for sid, sp in local_species.items():
        stem = source_species[sid]["identifier"]
        english = names[sid,"9"]
        cn = names[sid,"12"]
        own = {f["key"]:f for f in sp.get("forms",[])}
        opts = []
        sex_diff = source_species[sid]["has_gender_differences"] == "1"
        has_sexes = any(r["form_identifier"] == "female" for r in forms[sid])
        for r in forms[sid]:
            fid, pid = int(r["id"]), int(r["pokemon_id"])
            slug, suffix = r["identifier"], r["form_identifier"]
            if slug == "arceus-unknown": continue  # an unused Generation IV type slot
            is_base = fid == sid
            if sid == 716: is_base = suffix == "neutral"
            if sid == 925: is_base = suffix == "family-of-three"
            candidates = tokens_for(sid, stem, slug, suffix)
            local_key = next((k for k in candidates if k in own),"")
            local = own.get(local_key,{})
            art = "" if is_base else local_key or upper(slug)
            label = labels.get((fid,"12"),"") or SPECIAL.get(suffix) or local.get("label") or ("基础形态" if is_base else labels.get((fid,"9"),"") or suffix)
            if suffix == "gmax":
                label = {"toxtricity-amped-gmax":"超极巨·高调", "toxtricity-low-key-gmax":"超极巨·低调","urshifu-single-strike-gmax":"超极巨·一击流","urshifu-rapid-strike-gmax":"超极巨·连击流"}.get(slug,"超极巨化")
            if sid == 201:
                label = {"question":"？","exclamation":"！"}.get(suffix,suffix.upper())
            if sid in (493,773): label = type_names[suffix] + "属性"
            if sid in (664,665): art, label = "", "羽化花纹·" + patterns[suffix]
            if sid == 666: art = local_key or upper(slug)
            if sid == 774:
                if suffix.endswith("-meteor"):
                    # All seven meteor shells share a front sprite; the core colour is revealed in battle.
                    art = ""
                    label = "流星外壳·" + {"red":"红","orange":"橙","yellow":"黄","green":"绿","blue":"浅蓝","indigo":"蓝","violet":"紫"}[suffix.split("-")[0]] + "色核心"
                else: art = "MINIOR_CORE_" + upper(suffix)
            if sid == 869 and suffix.endswith("-sweet"):
                cream, sweet = suffix.removesuffix("-sweet").rsplit("-", 1)
                label = CREAMS[cream] + "·" + SWEETS[sweet] + "糖饰"
                art = "ALCREMIE_" + upper(cream + "-" + sweet)
            if sid == 678 and suffix.startswith("mega-"): label += "·" + ("雄性" if suffix == "mega-male" else "雌性")
            if sid == 978 and suffix == "mega": label += "·" + {"curly":"上弓","droopy":"下垂","stretchy":"平挺"}[slug.split("-")[1]]
            if sid == 801 and slug == "magearna-original-mega": label += "·五百年前的颜色"
            if sex_diff and not has_sexes and is_base: label = "雄性的样子" if label == "基础形态" else label + "·雄性"
            kind = classify(sid,suffix,slug,is_base,local)
            if r["is_battle_only"] == "1" and kind == "form": kind = "battle"
            v = {"key":slug,"label":label,"kind":kind,"species_id":sid,"form":local_key,"art_key":art,
                 "pokeapi_id":pid,"pokeapi_form_id":fid,"slug":slug}
            # Some purely visual forms share one Pokemon ID. Keep their real battle data,
            # and apply differences only; user-edited base stats still flow through Data.stats_of.
            for field, value in [("types",form_types[fid] or mon_types[pid]),("base",stats[pid]),("abilities",abilities[pid])]:
                baseline = local.get(field) or sp.get(field)
                if value and value != baseline and (not is_base or fid != sid):
                    v[field] = value
            if sid in (493,773) and (local.get("types") or sp["types"]) != [suffix]: v["types"] = [suffix]
            # These represent actual recorded forms. Shared artwork or base stats alone
            # cannot establish ownership of a rarer colour, accessory or battle form.
            records = list(dict.fromkeys(([local_key] if local_key else []) + LEGACY_KEYS.get(slug, [])))
            if is_base: records.insert(0, "")
            if art and art not in records: records.append(art)
            if not records: records.append(upper(slug))
            v["record_forms"] = records
            opts.append(v)
        if sex_diff and not has_sexes:
            opts.append({"key":stem+"-female","label":"雌性的样子","kind":"gender","species_id":sid,"form":"","art_key":upper(stem)+"_FEMALE",
                         "pokeapi_id":sid,"pokeapi_form_id":0,"slug":stem+"-female"})
        for key in sorted(own.keys() & LOCAL_ONLY):
            local = own[key]
            opts.append({"key":key.lower().replace("_","-"),"label":local["label"] if sid != 327 else "个体斑纹示例","kind":"battle" if sid==1017 else "pattern",
                         "species_id":sid,"form":key,"art_key":key,"pokeapi_id":sid,"pokeapi_form_id":0,"slug":key.lower().replace("_","-")})
        opts.sort(key=lambda v:v["kind"] != "base")
        assert len({v["key"] for v in opts}) == len(opts) and sum(v["kind"] == "base" for v in opts) == 1, sid
        all_rows[str(sid)] = {"name":cn,"english":english,"slug":stem,"aliases":list(dict.fromkeys([sp["name"],sp["key"]])),"variants":opts}
    return {"source_revision":REVISION,"paradox":{str(k):v for k,v in PARADOX.items()},"related":{"282":[1006]},"species":all_rows}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv-dir", type=Path, default=Path(cache_path("pokeapi-"+REVISION)))
    args = parser.parse_args()
    result = build(get_tables(args.csv_dir))
    with (DATA / "dex_catalog.json").open("w") as out:
        json.dump(result,out,ensure_ascii=False,separators=(",",":"))
        out.write("\n")
    print("species",len(result["species"]),"display variants",sum(len(r["variants"]) for r in result["species"].values()))
