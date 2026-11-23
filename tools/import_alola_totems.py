"""Rebuild the Alola trial teams from the original version-specific encounter records.

Original game locations, including ally order, moves, abilities, and Totem auras:
https://bulbapedia.bulbagarden.net/wiki/Verdant_Cavern
https://bulbapedia.bulbagarden.net/wiki/Brooklet_Hill
https://bulbapedia.bulbagarden.net/wiki/Wela_Volcano_Park
https://bulbapedia.bulbagarden.net/wiki/Lush_Jungle
https://bulbapedia.bulbagarden.net/wiki/Hokulani_Observatory
https://bulbapedia.bulbagarden.net/wiki/Thrifty_Megamart_(Abandoned_Site)
https://bulbapedia.bulbagarden.net/wiki/Vast_Poni_Canyon
https://bulbapedia.bulbagarden.net/wiki/Seafolk_Village
"""
import json
from import_alola_trainers import ROOT, forms, moves, slug, species

TEAMS = """SM Gumshoos +1 Defense
Gumshoos|12|Adaptability|Pecha Berry|Super Fang|Bite|Leer|Scary Face
Yungoos|10|Stakeout|None|Leer|Tackle|Pursuit|Bide

SM Raticate +1 Defense
Raticate|12|Gluttony|Pecha Berry|Bite|Tail Whip|Scary Face|Tackle
Rattata|10|Hustle|None|Tackle|Focus Energy|Quick Attack|Tail Whip

USUM Gumshoos +1 Defense
Gumshoos|12|Adaptability|Pecha Berry|Super Fang|Bite|Tackle|Scary Face
Yungoos|10|Stakeout|None|Leer|Tackle|Pursuit|Odor Sleuth

USUM Raticate +1 Defense
Raticate|12|Gluttony|Pecha Berry|Super Fang|Bite|Fury Swipes|Scary Face
Rattata|10|Hustle|None|Tackle|Tail Whip|Quick Attack|Pursuit

USUM Gumshoos_rematch +2 Atk, Def, Sp. Atk, Sp. Def, Speed
Gumshoos|60|Adaptability|Chople Berry|Hyper Fang|Ice Fang|Protect|Crunch
Yungoos|58|Stakeout|None|Yawn|Mud-Slap|Torment|Super Fang

USUM Raticate_rematch +2 Atk, Def, Sp. Atk, Sp. Def, Speed
Raticate|60|Gluttony|Chople Berry|Hyper Fang|Throat Chop|Protect|Double Team
Rattata|58|Hustle|None|Super Fang|Tail Whip|Torment|Crunch

SM Kommo-o +1 Atk, Def, Sp. Atk, Sp. Def, Speed
Kommo-o|45|Soundproof|Mental Herb|Clanging Scales|Sky Uppercut|Flash Cannon|Protect
Hakamo-o|32|Bulletproof|None|Sky Uppercut|Autotomize|Work Up|Bide
Scizor|32|Technician|None|Metal Claw|Pursuit|Leer|Fury Cutter

USUM Kommo-o +1 Atk, Def, Sp. Atk, Sp. Def, Speed
Kommo-o|49|Soundproof|Roseli Berry|Drain Punch|Dragon Claw|Thunder Punch|Poison Jab
Noivern|48|Infiltrator|None|Boomburst|Screech|Dragon Pulse|Air Slash
Scizor|46|Technician|None|Light Screen|Pursuit|Bullet Punch|X-Scissor

SM Lurantis +2 Speed
Lurantis|24|Leaf Guard|Power Herb|Razor Leaf|X-Scissor|Solar Blade|Synthesis
Trumbeak|22|Keen Eye|None|Rock Blast|Pluck|Supersonic|Screech
Castform|22|Forecast|None|Sunny Day|Water Gun|Headbutt|Weather Ball

USUM Lurantis +2 Speed
Lurantis|24|Leaf Guard|Power Herb|Low Sweep|X-Scissor|Solar Blade|Synthesis
Kecleon|22|Color Change|None|Sunny Day|Ancient Power|Dizzy Punch|Screech
Comfey|22|Flower Veil|None|Sunny Day|Floral Healing|Flower Shield|Magical Leaf

SM Vikavolt +1 Atk, Def, Sp. Atk, Sp. Def, Speed
Vikavolt|29|Levitate|Occa Berry|Vice Grip|Charge|Bug Bite|Spark
Charjabug|28|Battery|None|String Shot|Vice Grip|Mud-Slap|Thunder Wave
Charjabug|28|Battery|None|Bite|Thunder Wave|Mud-Slap|Spark

USUM Togedemaru +2 Def
Togedemaru|33|Lightning Rod|Sitrus Berry|Zing Zap|Spiky Shield|Iron Head|Bounce
Skarmory|32|Sturdy|None|Stealth Rock|Steel Wing|Tailwind|Torment
Dedenne|31|Pickup|None|Super Fang|Eerie Impulse|Charm|Discharge

SM Wishiwashi +1 Defense
Wishiwashi|20|Schooling|Sitrus Berry|Water Gun|Growl|Rain Dance|Soak
Wishiwashi|18|Schooling|None|Helping Hand|Feint Attack|Brine|Aqua Ring
Alomomola|18|Healer|None|Helping Hand|Double Slap|Heal Pulse|Water Gun

USUM Araquanid +1 Speed
Araquanid|20|Water Bubble|Wacan Berry|Leech Life|Bubble|Bite|Aurora Beam
Dewpider|18|Water Bubble|None|Sticky Web|Rain Dance|Bug Bite|Bubble
Masquerain|18|Intimidate|None|Scary Face|Stun Spore|Tailwind|Bug Bite

SM Salazzle +1 Special Defense
Salazzle|22|Corrosion|Petaya Berry|Torment|Venom Drench|Toxic|Flame Burst
Salandit|20|Corrosion|None|Poison Gas|Venoshock|Taunt|Scratch

USUM Marowak +2 Speed
Marowak|22|Cursed Body|Thick Club|Hex|Flame Wheel|Brick Break|Detect
Salazzle|20|Corrosion|None|Poison Gas|Venoshock|Flame Burst|Torment

SM Mimikyu +1 Atk, Def, Sp. Atk, Sp. Def, Speed
Mimikyu|33|Disguise|Lum Berry|Play Rough|Shadow Claw|Astonish|Mimic
Haunter|27|Levitate|None|Hypnosis|Sucker Punch|Night Shade|Lick
Gengar|27|Cursed Body|None|Shadow Ball|Hypnosis|Night Shade|Shadow Punch

USUM Mimikyu +1 Atk, Def, Sp. Atk, Sp. Def, Speed
Mimikyu|35|Disguise|Lum Berry|Shadow Claw|Play Rough|Leech Life|Slash
Banette|32|Insomnia|None|Screech|Will-O-Wisp|Feint Attack|Curse
Jellicent|33|Cursed Body|None|Water Pulse|Snore|Spite|Night Shade

USUM Ribombee +2 Atk, Def, Sp. Atk, Sp. Def, Speed
Ribombee|55|Shield Dust|Occa Berry|Bug Buzz|Draining Kiss|Quiver Dance|Dazzling Gleam
Pelipper|52|Drizzle|None|Stockpile|Scald|Spit Up|Seed Bomb
Blissey|53|Serene Grace|None|Heal Pulse|Light Screen|Helping Hand|Dazzling Gleam"""

abilities = {slug(row["key"]): row["id"] for row in json.loads((ROOT / "content/abilities.json").read_text())}
species_ids = {slug(name): sid for sid, name in species.items()}
species_ids.update(castform=351, wishiwashi=746, mimikyu=778)
berries = json.loads((ROOT / "content/berries.json").read_text())

def pokemon(line, boss):
    name, level, ability, item, *attacks = line.split("|")
    sid = species_ids[slug(name)]
    mon = {"species": sid, "level": int(level), "ability": abilities[slug(ability)], "moves": [moves[slug(move)] for move in attacks]}
    if item.endswith(" Berry"):
        mon["berry"] = slug(item[:-6])
        assert mon["berry"] in berries
    elif item != "None":
        mon["held"] = item.upper().replace(" ", "_")
    if boss:
        if sid == 746:
            mon["form"] = "WISHIWASHI_SCHOOL"
        elif sid == 778:
            mon["form"] = "MIMIKYU_TOTEM_DISGUISED"
        else:
            mon["form"] = next(f for f in forms[str(sid)] if f.endswith("_TOTEM"))
    elif sid == 19:
        mon["form"] = "RATTATA_ALOLA"
    return mon

def build():
    result = {"sunmoon": {}, "ultrasunultramoon": {}}
    stats = {"Defense":"def", "Def":"def", "Speed":"spe", "Special Defense":"spd"}
    for trial in TEAMS.split("\n\n"):
        header, lead, *allies = trial.splitlines()
        version, encounter, stage, stat = header.split(" ", 3)
        boss = pokemon(lead, True)
        sid = boss["species"]
        key = str(sid) + ("_rematch" if encounter.endswith("_rematch") else "")
        cfg = {"stat": stats.get(stat, "all"), "stages": int(stage), "allies": [pokemon(row, False) for row in allies]}
        if sid in (746,752):
            cfg.update(ally_hp=0.5, weather="rain")
        if sid == 758:
            cfg["repeat_ally"] = True
        result["sunmoon" if version == "SM" else "ultrasunultramoon"][key] = {"team":[boss], "alola_totem":cfg}
    return result

if __name__ == "__main__":
    (ROOT / "content/alola_campaign_totems.json").write_text(json.dumps(build(), ensure_ascii=False, separators=(",", ":")) + "\n")
