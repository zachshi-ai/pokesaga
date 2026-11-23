extends RefCounted
## One collectible crystal can be shared with any number of compatible partners.
const TYPES := {
	"NORMALIUM_Z":"normal","FIGHTINIUM_Z":"fighting","FLYINIUM_Z":"flying","POISONIUM_Z":"poison","GROUNDIUM_Z":"ground","ROCKIUM_Z":"rock","BUGINIUM_Z":"bug","GHOSTIUM_Z":"ghost","STEELIUM_Z":"steel","FIRIUM_Z":"fire","WATERIUM_Z":"water","GRASSIUM_Z":"grass","ELECTRIUM_Z":"electric","PSYCHIUM_Z":"psychic","ICIUM_Z":"ice","DRAGONIUM_Z":"dragon","DARKINIUM_Z":"dark","FAIRIUM_Z":"fairy"
}
# Local Z move id, required base move, compatible species, in-game item name.
const SPECIAL := {
	"PIKANIUM_Z":[866,"VOLT_TACKLE",[25],"皮卡丘Ｚ"],"PIKASHUNIUM_Z":[867,"THUNDERBOLT",[25],"智皮卡Ｚ"],
	"ALORAICHIUM_Z":[869,"THUNDERBOLT",[26],"阿罗雷Ｚ"],"EEVIUM_Z":[870,"LAST_RESORT",[133],"伊布Ｚ"],
	"SNORLIUM_Z":[871,"GIGA_IMPACT",[143],"卡比兽Ｚ"],"MEWNIUM_Z":[872,"PSYCHIC",[151],"梦幻Ｚ"],
	"DECIDIUM_Z":[873,"SPIRIT_SHACKLE",[724],"狙射树枭Ｚ"],"INCINIUM_Z":[874,"DARKEST_LARIAT",[727],"炽焰咆哮虎Ｚ"],
	"PRIMARIUM_Z":[875,"SPARKLING_ARIA",[730],"西狮海壬Ｚ"],"LYCANIUM_Z":[876,"STONE_EDGE",[745],"鬃岩狼人Ｚ"],
	"MIMIKIUM_Z":[877,"PLAY_ROUGH",[778],"谜拟丘Ｚ"],"KOMMONIUM_Z":[878,"CLANGING_SCALES",[784],"杖尾鳞甲龙Ｚ"],
	"TAPUNIUM_Z":[879,"NATURES_MADNESS",[785,786,787,788],"卡璞Ｚ"],"SOLGANIUM_Z":[880,"SUNSTEEL_STRIKE",[791,800],"索尔迦雷欧Ｚ"],
	"LUNALIUM_Z":[881,"MOONGEIST_BEAM",[792,800],"露奈雅拉Ｚ"],"ULTRANECROZIUM_Z":[882,"PHOTON_GEYSER",[800],"究极奈克洛Ｚ"],
	"MARSHADIUM_Z":[883,"SPECTRAL_THIEF",[802],"玛夏多Ｚ"]
}
const ULTRA_ONLY := ["LYCANIUM_Z","MIMIKIUM_Z","KOMMONIUM_Z","SOLGANIUM_Z","LUNALIUM_Z","ULTRANECROZIUM_Z"]

static func crystal(key: String) -> bool:
	return TYPES.has(key) or SPECIAL.has(key)

static func label(data,key: String) -> String:
	if TYPES.has(key):return str(data.type_name(TYPES[key]))+"Ｚ"
	return str(SPECIAL[key][3]) if SPECIAL.has(key) else ""

static func give(g,key: String) -> void:
	if not crystal(key):return
	var name:=label(g.get_node("/root/Data"),key)
	if g._bag_count(name)==0:g._give_bag_item(name,"held",key)
	g._flags()["a_crystal_"+key]=true
	g._persist()

static func move_id(data,mon: Dictionary,move: Dictionary,ultra: bool) -> int:
	var key:=str(mon.get("held",""))
	if TYPES.has(key):
		if TYPES[key]!=move.get("type",""):return 0
		return int(move.id) if move.category=="status" else int(data.z_move_for_type(TYPES[key]))
	if not SPECIAL.has(key) or (not ultra and key in ULTRA_ONLY):return 0
	var spec:Array=SPECIAL[key]
	if int(mon.species_id) not in spec[2] or str(move.key)!=spec[1]:return 0
	var form:=str(mon.get("form",""))
	match key:
		"ALORAICHIUM_Z":if form!="RAICHU_ALOLA":return 0
		"PIKASHUNIUM_Z":if form not in ["PIKACHU_ORIGINAL","PIKACHU_HOENN","PIKACHU_SINNOH","PIKACHU_UNOVA","PIKACHU_KALOS","PIKACHU_ALOLA","PIKACHU_PARTNER"]:return 0
		"SOLGANIUM_Z":if int(mon.species_id)==800 and form!="NECROZMA_DUSK_MANE":return 0
		"LUNALIUM_Z":if int(mon.species_id)==800 and form!="NECROZMA_DAWN_WINGS":return 0
		"ULTRANECROZIUM_Z":if form!="NECROZMA_ULTRA":return 0
	return int(spec[0])

static func status_bonus(battle, mon: Dictionary, move: Dictionary) -> void:
	var effect: Dictionary=load("res://core/alola_field.gd").data().z_effects.get(str(move.id),{})
	for stat in effect.get("boost",{}):
		battle._apply_stage(mon,stat,int(effect.boost[stat]),battle.log)
	match effect.get("effect",""):
		"heal":mon.hp=mon.max_hp
		"clearnegativeboost":
			for stat in mon.stages:mon.stages[stat]=maxi(0,int(mon.stages[stat]))
		"crit2":mon.crit_stage=mini(4,int(mon.get("crit_stage",0))+2)
		"healreplacement":battle.alola_heal_replacement["a" if mon in battle.team_a else "b"]=true
		"redirect":mon["alola_redirect"]=battle.completed_turns
