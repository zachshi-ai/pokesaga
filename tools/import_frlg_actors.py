"""Recover FireRed object identities, spawn flags and the scripted paths used by the opening."""
import json
import re
from pathlib import Path

from PIL import Image

from asset_paths import project_path, source_path
from import_official_chars import indexed_sprite


# Nonhuman and named story actors whose original overworld picture has no Emerald equivalent.
ART = {
    "SNORLAX": ("pokemon/snorlax",32), "LORELEI": ("people/lorelei",16), "CELIO": ("people/celio",16), "RUBY": ("misc/ruby",16),
    "BLUE": ("people/blue", 16), "BILL": ("people/bill", 16),
    "CLEFAIRY": ("pokemon/clefairy", 16), "SLOWBRO": ("pokemon/slowbro", 16), "MR_FUJI": ("people/mr_fuji", 16),
    "POKEDEX": ("misc/pokedex", 16), "OLD_MAN_LYING_DOWN": ("people/old_man_lying_down", 32),
    "POLICEMAN": ("people/policeman", 16), "PIDGEOT": ("pokemon/pidgeot", 16),
}
# Standard FireRed facing frames are south, north and west. East mirrors west.
SWIM_ART = {"SWIMMER_M_WATER", "SWIMMER_F_WATER", "SWIMMER_M_LAND", "SWIMMER_F_LAND",
            "TUBER_M_WATER", "TUBER_M_LAND", "TUBER_F"}
CERULEAN_GYM_ART = {"PICNICKER", "MISTY", "GYM_GUY"}
GYM_CAST = {
    "CeruleanCity_Gym_EventScript_Luis": {"name":"游泳者 路易斯", "lines":["来一场水系宝可梦对战吧！"],
        "battle":{"team":[{"species":116,"level":16},{"species":90,"level":16}]}},
    "CeruleanCity_Gym_EventScript_Diana": {"name":"野餐少女 戴安娜", "lines":["想挑战小霞？先和我的角金鱼比一场吧！"],
        "battle":{"team":[{"species":118,"level":19}]}},
    "CeruleanCity_Gym_EventScript_GymGuy": {"name":"道馆向导", "lines":["小霞擅长水系。草系和电系招式能在这里派上用场。"]},
}

ROLES = {
    "FourIsland_IcefallCave_Back_EventScript_Lorelei": "icefall_lorelei",
    "SixIsland_RuinValley_EventScript_Scientist": "ruin_scientist",
    "OneIsland_PokemonCenter_1F_EventScript_Celio": "celio",
    "MtEmber_RubyPath_B5F_EventScript_Ruby": "ember_ruby",
    **{f"MtEmber_Exterior_EventScript_Grunt{i}": f"ember_grunt_{i}" for i in (1,2)},
    "Route12_EventScript_Snorlax": "snorlax_12",
    "Route16_EventScript_Snorlax": "snorlax_16",
    "PalletTown_EventScript_SignLady": "sign_lady",
    "PalletTown_ProfessorOaksLab_EventScript_Rival": "lab_rival",
    "PalletTown_ProfessorOaksLab_EventScript_ProfOak": "lab_oak",
    "ViridianCity_EventScript_TutorialOldMan": "old_man",
    "ViridianCity_Mart_EventScript_Clerk": "parcel_clerk",
    "PewterCity_EventScript_GymGuide": "gym_guide",
    "PewterCity_EventScript_RunningShoesAide": "shoes_aide",
    "CeruleanCity_EventScript_Policeman": "police",
    "CeruleanCity_EventScript_Slowbro": "slowbro",
    "CeruleanCity_EventScript_Lass": "slowbro_friend",
    "CeruleanCity_EventScript_Grunt": "cerulean_grunt",
    "ViridianCity_Gym_EventScript_Giovanni": "gym_giovanni",
    "SaffronCity_EventScript_DoorGuardGrunt": "silph_guard",
    "PokemonTower_7F_EventScript_MrFuji": "tower_fuji",
    "LavenderTown_VolunteerPokemonHouse_EventScript_MrFuji": "home_fuji",
    **{f"PokemonTower_7F_EventScript_Grunt{i}": f"tower_grunt_{i}" for i in range(1, 4)},
}
FLAG_ROLES = {
    "FLAG_HIDE_OAK_IN_PALLET_TOWN": "pallet_oak", "FLAG_HIDE_POKEDEX": "lab_dex",
    "FLAG_HIDE_BILL_CLEFAIRY": "bill_clefairy", "FLAG_HIDE_BILL_HUMAN_SEA_COTTAGE": "bill",
}
NAMES = {"icefall_lorelei":"科拿", "ruin_scientist":"研究员", "celio":"锦辉", "ember_ruby":"红宝石", "ember_grunt_1":"火箭队手下", "ember_grunt_2":"火箭队手下", "snorlax_12":"卡比兽", "snorlax_16":"卡比兽", "sign_lady":"镇上的姐姐","pallet_oak":"大木博士","old_man":"老人","shoes_aide":"大木的助手",
         "gym_guide":"道馆向导","police":"警察","slowbro":"呆壳兽","cerulean_grunt":"火箭队手下",
         "bill_clefairy":"皮皮","bill":"正辉","lab_dex":"图鉴","silph_giovanni":"坂木",
         "silph_guard":"火箭队守卫", "tower_fuji":"富士老人", "home_fuji":"富士老人",
         **{f"tower_grunt_{i}":"火箭队手下" for i in range(1,4)}}
FALLBACK_GFX = {"ruin_scientist":"scientist", "ember_grunt_1":"team_rocket_m","ember_grunt_2":"team_rocket_m","pallet_oak":"oak","lab_oak":"oak","lab_rival":"fr_blue","old_man":"old_man",
                "shoes_aide":"scientist","gym_guide":"youngster","silph_giovanni":"giovanni", "silph_guard":"team_rocket_m",
                **{f"tower_grunt_{i}":"team_rocket_m" for i in range(1,4)}}
DIRECTIONS = {"up":"U", "down":"D", "left":"L", "right":"R"}


def normalize(identifier):
    return re.sub("[^a-z0-9]", "", identifier.lower())


def opening_paths(source):
    source = source.read_text()
    macro = re.search(r"\.macro walk_to_lab\s*\n(.*?)\.endm", source, re.S).group(1)
    result = {}
    for label in ("OakEnterLeft","OakEnterRight","OakWalkToLabLeft","OakWalkToLabRight","PlayerWalkToLabLeft","PlayerWalkToLabRight"):
        chunk = source.split("PalletTown_Movement_" + label + "::", 1)[1].split("step_end",1)[0]
        chunk = chunk.replace("walk_to_lab", macro)
        result[label] = "".join(DIRECTIONS[d] for d in re.findall(r"^\s*walk_(up|down|left|right)\s*$",chunk,re.M))
    return result


def build(project, source):
    originals = {normalize(p.parent.name):json.loads(p.read_text()) for p in sorted((source/"data/maps").glob("*/map.json"))}
    base_flags = (source/"data/event_scripts.s").read_text().split("EventScript_ResetAllMapFlags::",1)[1].split("\n\tend",1)[0]
    initial = sorted(set(re.findall(r"setflag (FLAG_HIDE_\w+)",base_flags)))
    result = {}
    poses = {}
    for region in ("kanto","sevii"):
        for path in sorted((project/"content/regions"/region/"maps").glob("*.json")):
            data = json.loads(path.read_text())
            meta_file = project/"content/emerald_maps"/(data.get("emerald","")+".json")
            components = json.loads(meta_file.read_text()).get("member_maps",{}) if meta_file.is_file() else {}
            components = components or {path.stem:[0,0]}
            existing = {tuple(n["at"]):n for n in data.get("npcs",[])}
            events = {}
            for name,offset in components.items():
                original = originals.get(normalize(name),{})
                for obj in original.get("object_events",[]) or []:
                    if obj.get("type")!="object": continue
                    x,y = obj["x"]+offset[0],obj["y"]+offset[1]
                    graphics=obj["graphics_id"].removeprefix("OBJ_EVENT_GFX_")
                    flag=obj.get("flag","0")
                    script=obj.get("script","")
                    role=ROLES.get(script) or FLAG_ROLES.get(flag)
                    if name=="silph_co_11f" and graphics=="GIOVANNI": role="silph_giovanni"
                    source_pose = graphics in SWIM_ART or (normalize(name)=="ceruleancitygym" and graphics in CERULEAN_GYM_ART)
                    if not (role or source_pose or graphics in ART or flag.startswith("FLAG_HIDE_")): continue
                    row=existing.get((x,y))
                    restore = flag in ("FLAG_HIDE_SAFFRON_ROCKETS", "FLAG_HIDE_SAFFRON_CIVILIANS")
                    if row is None and not (role or restore or source_pose): continue
                    if row and (row.get("transit") or graphics in ("ITEM_BALL","CUT_TREE","PUSHABLE_BOULDER","ROCK_SMASH_ROCK")): continue
                    event = {}
                    if source_pose:
                        # gInitialMovementTypeFacingDirections uses the first direction of a walk
                        # sequence, and defaults to south for look-around/wander-around actors.
                        direction = re.search(r"(?:^|_)(UP|DOWN|LEFT|RIGHT)(?:_|$)",obj["movement_type"])
                        face = direction.group(1).lower() if direction else "down"
                        pose = "fr_" + graphics.lower() + "_" + face
                        poses[pose] = (graphics.lower(),face)
                        event["field_art"] = pose
                        if graphics.endswith("_WATER"):
                            event["in_water_pose"] = True
                        if row is None:
                            event["name"] = ("游泳圈少年 " if graphics.startswith("TUBER") else "游泳者 ") + script.split("_")[-1]
                        event.update(GYM_CAST.get(script,{}))
                    if flag not in ("0",""): event["flag"]=flag
                    if role:
                        event["role"]=role
                        if role in NAMES: event["name"]=NAMES[role]
                    if flag == "FLAG_HIDE_ICEFALL_CAVE_ROCKETS": event.update(gfx="team_rocket_m",name="火箭队手下")
                    if graphics in ART: event["gfx"]="fr_"+graphics.lower()
                    elif role in FALLBACK_GFX: event["gfx"]=FALLBACK_GFX[role]
                    if row is None:
                        event["add"]=True
                        if restore:
                            event["name"]="火箭队手下" if graphics=="ROCKET_M" else ("大比鸟" if graphics=="PIDGEOT" else "市民")
                            if "gfx" not in event:
                                event["gfx"]={"ROCKET_M":"team_rocket_m","WORKER_M":"man","BOY":"youngster","LASS":"lass"}.get(graphics,"man")
                        elif role=="slowbro_friend":
                            event.update(name="训练家",gfx="lass")
                    events[f"{x},{y}"]=event
            if events: result[f"{region}/{path.stem}"]=events
    out={"initial":initial,"maps":result,"opening_paths":opening_paths(source/"data/maps/PalletTown/scripts.inc")}
    (project/"content/frlg_actors.json").write_text(json.dumps(out,ensure_ascii=False,separators=(",",":"))+"\n")
    for gfx,(path,width) in ART.items():
        img=indexed_sprite(source/"graphics/object_events/pics"/(path+".png"))
        img.crop((0,0,width,img.height)).save(project/"assets/npc"/("fr_"+gfx.lower()+".png"))
    for pose,(graphics,face) in poses.items():
        sheet = indexed_sprite(source/"graphics/object_events/pics/people"/(graphics+".png"))
        left = {"down":0, "up":16, "left":32, "right":32}[face]
        frame = sheet.crop((left,0,left+16,sheet.height))
        if face=="right":
            frame = frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        frame.save(project/"assets/npc"/(pose+".png"))
    oak = indexed_sprite(source/"graphics/object_events/pics/people/prof_oak.png")
    oak.save(project/"assets/npc/fr_oak_walk.png")
    print(f"{sum(map(len,result.values()))} conditional or named actors in {len(result)} maps; {len(initial)} initial flags")


if __name__=="__main__":
    build(Path(project_path()),Path(source_path("firered")))
