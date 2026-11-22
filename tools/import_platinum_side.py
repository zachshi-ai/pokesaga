"""Compile field rewards, machines, regional dex and NPC trades from pret/pokeplatinum.

Usage: python3 tools/import_platinum_side.py /path/to/pokeplatinum /path/to/pokeapi/data/v2/csv
The game uses only the checked-in output. Upstream revisions are recorded there.
"""
import argparse
import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "content"
TRADES = {
    "OreburghCityNorthHouse1F_SchoolKidF": "kazza_abra",
    "EternaCityCondominiums1F_NinjaBoy": "charap_chatot",
    "SnowpointCityWestHouse_Mindy": "gaspar_haunter",
    "Route226House_Meister": "foppa_magikarp",
}
# Identifiers that changed between the Gen IV source and PokeAPI.
ALIASES = {"TINYMUSHROOM":"tiny-mushroom", "X_SPECIAL":"x-sp-atk", "PARLYZ_HEAL": "paralyze-heal", "TINY_MUSHROOM": "tiny-mushroom",
           "THUNDERSTONE": "thunder-stone", "DEEP_SEA_SCALE": "deep-sea-scale",
           "DEEP_SEA_TOOTH": "deep-sea-tooth", "SILVERPOWDER": "silver-powder",
           "NEVERMELTICE": "never-melt-ice", "ENERGYPOWDER": "energy-powder",
           "BRIGHTPOWDER": "bright-powder", "X_SP_DEF": "x-sp-def", "X_SP_ATK": "x-sp-atk"}
NAMES = {"PP_UP": "ＰＰ提升剂", "PP_MAX": "ＰＰ极限提升剂", "ESCAPE_ROPE": "离洞绳",
         "OLD_ROD": "神奥破旧钓竿", "GOOD_ROD": "神奥好钓竿", "SUPER_ROD": "神奥厉害钓竿",
         "REPEL": "除虫喷雾", "MAX_REPEL": "黄金喷雾", "SUPER_REPEL": "白银喷雾"}
# Only dispensers whose own entry executes the grant unconditionally apart from its one-time flag.
# Special stateful dispensers, including machines, trades and medicines for other NPCs, run in GDScript.
def simple_gifts(maps):
    gifts = {}
    for directory in sorted(maps.iterdir()):
        events, script = directory / "events.json", directory / "scripts.s"
        if not events.exists() or not script.exists() or "unused" in directory.name:
            continue
        actors = {r.get("script") for r in read(events).get("object_events", [])}
        for label, block in re.findall(r"^(\w+):\n(.*?)(?=^\w+:|\Z)", script.read_text(), re.M | re.S):
            if label not in actors:
                continue
            flag = re.findall(r"GoToIfSet (FLAG_RECEIVED_\w+)", block)
            prize = re.search(r"SetVar VAR_0x8004, ITEM_(\w+)\n\s*SetVar VAR_0x8005, (\d+)", block)
            if not prize or len(flag) != 1 or "SetFlag " + flag[0] not in block:
                continue
            conditions = re.findall(r"^\s*(\w+(?:If|Check|Get)\w*|Check\w+|Get\w+|ShowYesNoMenu)\b", block, re.M)
            if any(c not in {"GoToIfSet", "GoToIfCannotFitItem"} for c in conditions) or prize[1] in {"EXPLORER_KIT","POFFIN_CASE","BICYCLE"}:
                continue
            gifts[label] = [prize[1], int(prize[2])]
    return gifts


def read(path):
    return json.loads(path.read_text())


def compile_data(src, csv_dir):
    maps = src / "res/field/maps"
    species = (src / "generated/species.txt").read_text().splitlines()
    move_ids = {r["key"]: r["id"] for r in read(CONTENT / "moves.json")}
    localized = {r["item_id"]: r["name"] for r in csv.DictReader((csv_dir / "item_names.csv").open()) if r["local_language_id"] == "12"}
    numeric_moves = (src / "generated/moves.txt").read_text().splitlines()
    names = {r["identifier"]: localized.get(r["id"]) for r in csv.DictReader((csv_dir / "items.csv").open())}
    held = {r["key"]: r["name"] for r in read(CONTENT / "items.json")}
    evos = read(CONTENT / "evo_items.json")
    berries = read(CONTENT / "berries.json")
    visible = re.findall(r"^(VisibleItems_\w+):\n\s*SetVar VAR_0x8008, ITEM_(\w+)\n\s*SetVar VAR_0x8009, (\d+)", (src / "res/field/scripts/visible_items.s").read_text(), re.M)
    hidden = re.findall(r"HIDDEN_ITEM_ENTRY\(ITEM_(\w+),\s*(\d+),\s*\d+,\s*(FLAG_OBTAINED_HIDDEN_\w+)\)", (src / "include/data/field/hidden_items.h").read_text())
    placed = {}
    for f in sorted(maps.glob("*/events.json")):
        for group in read(f).values():
            if isinstance(group, list):
                for row in group:
                    if isinstance(row, dict):
                        placed[row.get("script",row.get("hidden_item",""))] = True
    picks = {key:[item,int(count)] for key,item,count in visible if key in placed}
    picks.pop("VisibleItems_BattlePark_RazorFang",None)  # unused Diamond/Pearl Battle Park
    picks["VisibleItems_Unused7321_GriseousOrb"]=["GRISEOUS_ORB",1]  # overlay009 creates this ball at runtime
    picks.update({key:[item,int(count)] for item,count,key in hidden if key in placed})
    machines = {}
    items = {}
    berry_hours = {}
    for f in sorted((src / "res/items/data").glob("*.json")):
        item = read(f)
        key = f.stem.upper()
        pocket = item["fieldPocket"]
        if item.get("berryData"): berry_hours[key]=item["berryData"]["stageDuration"]
        if re.fullmatch(r"[TH]M\d\d", key):
            name = ("神奥秘传学习器 " if key.startswith("HM") else "神奥招式学习器 ") + key[2:]
            machines[key] = {"move": move_ids[item["teachesMove"][5:]], "species":[]}
            items[key] = [name, "tm"]
            continue
        name = NAMES.get(key) or evos.get(key) or held.get(key) or names.get(ALIASES.get(key,key.lower().replace("_","-"))) or item["name"]
        cat = {"POCKET_BALLS":"ball","POCKET_MEDICINE":"heal","POCKET_BERRIES":"berry","POCKET_KEY_ITEMS":"key","POCKET_BATTLE_ITEMS":"battle"}.get(pocket,"other")
        berry = key.removesuffix("_BERRY").lower()
        if berry in berries:
            name = berries[berry]["name"]
        if key in evos: cat = "evo"
        elif key in held or key in {"WIDE_LENS","ZOOM_LENS","METRONOME"}: cat = "held"
        elif key == "RARE_CANDY": cat = "candy"
        items[key] = [name,cat]
    tutors = {str(numeric_moves.index(r["move"])):{"location":r["location"].removeprefix("TUTOR_LOCATION_"),
              "shards":[r[c+"Cost"] for c in ("red","blue","yellow","green")], "species":[]}
              for r in read(src/"res/pokemon/move_tutors.json")}
    learned = {}
    safari = {}
    show = {}
    land_areas = (src/"generated/pal_park_land_area.txt").read_text().splitlines()
    water_areas = (src/"generated/pal_park_water_area.txt").read_text().splitlines()
    for index, sp in enumerate(species[1:494],1):
        f = src / "res/pokemon" / sp[8:].lower() / "data.json"
        dex_entry = read(f)
        if index <= 386:
            entry = dex_entry["catching_show"]
            area = land_areas.index(entry["pal_park_land_area"]) or (4 + water_areas.index(entry["pal_park_water_area"]))
            show[index] = [area,entry["rarity"],entry["catching_points"],[t.removeprefix("TYPE_").lower() for t in dex_entry["types"]]]
        safari[index]=dex_entry["safari_flee_rate"]
        learned[index]=[[int(lv),numeric_moves.index(mv)] for lv,mv in dex_entry["learnset"]["by_level"]]
        for mv in dex_entry["learnset"]["by_tutor"]:
            n=str(numeric_moves.index(mv))
            if n in tutors:tutors[n]["species"].append(index)
        for key in dex_entry["learnset"]["by_tm"]:
            machines[key]["species"].append(index)
    trades = {}
    for actor, file in TRADES.items():
        row = read(src / "res/npc_trades" / (file + ".json"))
        for key in ["species","requestedSpecies"]: row[key] = species.index(row[key])
        trades[actor] = row
    dex = read(src / "res/pokemon/sinnoh_pokedex.json")
    prices = {f.stem.upper(): read(f)["price"] for f in sorted((src/"res/items/data").glob("*.json"))}
    store_data=(src/"include/data/mart_items.h").read_text()
    common=[[k,int(n,16)] for k,n in re.findall(r"\{ ITEM_(\w+), (0x[0-9A-Fa-f]+) \}",store_data)]
    stock = {k:re.findall(r"\bITEM_(\w+)",v) for k,v in re.findall(r"const u16 (\w+)\[\] = \{([^}]+)\}",store_data)}
    stores={k:stock[n] for k,n in re.findall(r"\[(MART_SPECIALTIES_ID_\w+)\] = (\w+)",store_data)}
    sellers = {}
    for script in maps.glob("*/scripts.s"):
        for label, block in re.findall(r"^(\w+):\n(.*?)(?=^\w+:|\Z)",script.read_text(),re.M|re.S):
            if "PokeMartCommonWithGreeting" in block:sellers[label]="common"
            elif (m:=re.search(r"PokeMartSpecialtiesWithGreeting (MART_SPECIALTIES_ID_\w+)",block)):
                sellers[label]=m[1]
    stores["common"]=common
    seals = {k.upper(): re.findall(r"\b(\w+_SEAL_\w+)\b",v) for k,v in re.findall(r"SunyshoreMarketStock(\w+)\[\] = \{([^}]+)\}",store_data)}
    stores["seals"]=seals
    seal_array=(src/"src/applications/capsule_menu/main.c").read_text().split("sealTypeValues[SEAL_ID_MAX] = {",1)[1].split("};",1)[0]
    raw_seals = (src/"generated/seals.txt").read_text().splitlines()
    seal_prices={raw_seals[i]:int(r.split(",")[5].strip(),0) for i,r in enumerate(re.findall(r"\{ ([^}]+) \}",seal_array))}

    unown = {}
    plots = {}
    berries_initial = re.findall(r"\.berryItemID = ITEM_(\w+), \.yield = (\d+)", (src / "include/data/berry_init.h").read_text())
    radar = {}
    for directory in sorted(maps.iterdir()):
        events = directory / "events.json"
        encounters = directory / "encounters.json"
        if events.exists():
            for row in read(events).get("object_events",[]):
                if "berry_tree" in row:
                    key = "%s/%s" % (directory.name.upper(),row["id"])
                    item,qty = berries_initial[int(row["berry_tree"])]
                    plots[key] = [item,int(qty)]
        if encounters.exists() and (table:=read(encounters).get("unown_table",0)):
            unown[directory.name.upper()]=int(table)
        if encounters.exists() and "radar" in (wild := read(encounters)) and wild.get("land_rate",0):
            radar[directory.name.upper()] = [species.index(sp) for sp in wild["radar"]]
    honey = {k:[species.index(sp) for sp in v] for k,v in read(maps / "encounters_honey_tree.json").items()}
    honey_maps = re.findall(r"MAP_HEADER_(\w+)", (src / "src/overlay005/honey_tree.c").read_text().split("sHoneyTreeMapHeaderIDs[NUM_HONEY_TREES] = {",1)[1].split("};",1)[0])
    trainers = {}
    for name in ["galactic_grunt_iron_island_1", "galactic_grunt_iron_island_2", "riley_iron_island",
                 "commander_mars_stark_mountain", "commander_jupiter_stark_mountain",
                 *["leader_"+name+"_rematch" for name in ("roark","gardenia","fantina","maylene","wake","byron","candice","volkner")],
                 *[name+"_battleground" for name in ("cheryl","mira","riley","marley","buck")]]:
        tr = read(src / "res/trainers/data" / (name+".json"))
        trainers[name] = [{"species":species.index(m["species"]), "level":m["level"],
                           "moves":[numeric_moves.index(mv) for mv in (m["moves"] or []) if mv!="MOVE_NONE"],
                           "held":(m["item"] or "").removeprefix("ITEM_")} for m in tr["party"]]
    marsh_daily={k:[species.index(sp) for sp in v] for k,v in read(maps/"encounters_great_marsh_lookout.json").items() if k in {"before_national_dex","after_national_dex"}}
    prizes = [[item,int(cost)] for item,cost in re.findall(r"\{ ITEM_(\w+), (\d+) \}", (src/"src/scrcmd_game_corner_prize.c").read_text())]
    return {"garden_species":[species.index(sp) for sp in read(maps/"trophy_garden/encounters.json")["daily_encounters"]],"pal_park":show,"game_prizes":prizes,"seal_prices":seal_prices,"shops":stores,"sellers":sellers,"prices":prices,"unown":unown,"marsh_daily":marsh_daily,"tutors":tutors,"level_moves":learned,"safari":safari,"berry_hours":berry_hours,"plots":plots,"radar":radar,"honey":honey,"honey_maps":honey_maps,"trainers":trainers, "source":"pret/pokeplatinum@485c400f9d7bad10d906d556ba23e5e46d5b3e5e",
            "names_source":"PokeAPI/pokeapi@cd5f6c6232f23430aa6089896d96230f5f7ecef4",
            "dex":[species.index(s) for s in dex[1:]], "items":items,"machines":machines,
            "pickups":picks,"gifts":simple_gifts(maps),"trades":trades}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platinum", type=Path)
    parser.add_argument("csv", type=Path)
    args = parser.parse_args()
    result = compile_data(args.platinum, args.csv)
    (CONTENT / "sinnoh_side.json").write_text(json.dumps(result,ensure_ascii=False,separators=(",",":"))+"\n")
