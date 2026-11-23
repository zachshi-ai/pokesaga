extends RefCounted

const NAMES := {"kanto":"关都","johto":"城都","hoenn":"丰缘","sinnoh":"神奥","unova":"合众","kalos":"卡洛斯","alola":"阿罗拉"}
const SEQUEL_HOME := {"map":"unova_b2_home","at":[4,6]}
const HOMES := {
	"alola":{"map":"alola_home","at":[8,7]},
	"kalos":{"map":"kalos_home_2f","at":[14,11]},
	"unova":{"map":"unova_bw_home_2f","at":[5,6]},
	"sinnoh":{"map":"sinnoh_twinleaf_town_player_house_2f","at":[4,6]},
	"kanto":{"map":"pallet_town_players_house_2f","at":[3,6]},
	"johto":{"map":"johto_players_house_2f","at":[6,6]},
	"hoenn":{"map":"em_inside_of_truck","at":[2,2]},
}
const KANTO := ["灰色徽章","蓝色徽章","橙色徽章","彩虹徽章","粉红徽章","金色徽章","深红徽章","绿色徽章"]
const JOHTO := ["飞翼徽章","昆虫徽章","标准徽章","魅影徽章","打击徽章","矿物徽章","冰川徽章","升龙徽章"]
const J2 := ["brock","misty","ltsurge","erika","janine","sabrina","blaine","blue"]

static func migrate(data: Dictionary) -> void:
	if data.has("chapters"):
		for key in ["sinnoh","unova","unova_bw2","kalos","alola"]:
			data.get_or_add("regional_badges",{}).get_or_add(key,[])
		return
	var origin := str(data.get("origin","kanto"))
	var flags: Dictionary = data.get("flags",{})
	var chapters := {origin:"origin"}
	if flags.get("got_starter",false) or flags.get("oak_in_lab",false): chapters.get_or_add("kanto","carried")
	if flags.get("j_gear",false) or flags.get("j_starter_species",0) or flags.get("johto_victory_done",false): chapters.get_or_add("johto","carried")
	if flags.get("h_started",false): chapters.get_or_add("hoenn","carried")
	data.chapters = chapters
	if chapters.has("kanto") and data.has("bag"):
		data.import_kanto_items = true
	var regional := {"kanto":[],"johto":[],"hoenn":[],"sinnoh":[],"unova":[],"unova_bw2":[],"kalos":[],"alola":[]}
	for badge in data.get("badges",[]):
		if badge in JOHTO: regional.johto.append(badge)
		elif badge in KANTO:
			var j2: bool = flags.get("j2_badge_"+str(J2[KANTO.find(badge)]),false)
			if j2: regional.johto.append(badge)
			if not j2 or flags.get("kanto_champion",false) or (chapters.has("kanto") and (flags.get("story_kanto_badge_"+str(J2[KANTO.find(badge)]),false) or not chapters.has("johto"))):
				regional.kanto.append(badge)
	data.regional_badges = regional
	if not chapters.has("kanto") and regional.kanto.is_empty():
		for key in ["beat_brock","beat_giovanni","kanto_eight_badges","viridian_gym_open","sevii_blaine_badge","surge_open","received_kanto_bike"]:
			flags.erase(key)
		for i in range(1,7): flags.erase("cinnabar_quiz_"+str(i))
		if flags.get("johto_dex",false): flags.erase("got_dex")
	data.flags = flags

static func badges(data: Dictionary, region: String) -> Array:
	if not data.has("regional_badges"): return data.get("badges",[])
	if region=="unova" and data.get("flags",{}).get("u2_started",false) and not data.flags.get("u1_memory",false):
		region="unova_bw2"
	return data.regional_badges.get("kanto" if region=="sevii" else region,[])

static func grant(data: Dictionary, region: String, badge: String) -> void:
	migrate(data)
	var local := badges(data,region)
	if badge not in local: local.append(badge)
	if badge not in data.badges: data.badges.append(badge)

static func begin(data: Dictionary, region: String, mode: String, version := "x") -> Dictionary:
	if region not in HOMES or mode not in ["boxed","carried"]: return {}
	var staged := data.duplicate(true)
	migrate(staged)
	if staged.chapters.has(region): return {}
	if not _arrange_party(staged,mode): return {}
	staged.chapters[region] = mode
	staged.region = region
	staged.map = HOMES[region].map
	staged.pos = HOMES[region].at.duplicate()
	staged.facing = "down"
	for key in ["surfing","diving","bike"]: staged[key] = false
	staged.erase("field_elevation")
	staged.erase("location_label")
	if region == "hoenn":
		staged.flags.h_started = true
		staged.hoenn_field_revision = 1
	if region == "johto": staged.johto_field_revision = 1
	if region == "sinnoh": staged.flags.s_started = true
	if region == "unova": staged.flags.u1_started = true
	if region=="alola":
		if version not in preload("res://core/alola_field.gd").VERSIONS:return {}
		staged.flags.a_started=true
		staged.flags.a_version=version
	if region=="kalos":
		if version not in ["x","y"]:return {}
		staged.flags.k_started=true
		staged.flags.k_version=version
	return staged

## Copy the entire slot before changing the era. A full PC or a cancelled arrival
## leaves the current party, badges, maps and last healing location intact.
static func begin_unova_sequel(data: Dictionary, mode: String) -> Dictionary:
	var flags: Dictionary=data.get("flags",{})
	if mode not in ["carried","boxed"] or not flags.get("u1_ghetsis",false) or flags.get("u2_started",false): return {}
	var staged := data.duplicate(true)
	migrate(staged)
	if not _arrange_party(staged,mode): return {}
	staged.flags.u2_started=true
	staged.unova_sequel_party=mode
	staged.region="unova"
	staged.map=SEQUEL_HOME.map
	staged.pos=SEQUEL_HOME.at.duplicate()
	staged.facing="down"
	for key in ["surfing","diving","bike"]: staged[key]=false
	for key in ["field_elevation","location_label"]: staged.erase(key)
	if staged.get("centers",{}).has("unova"):
		staged.get_or_add("unova_centers",{})["bw"]=staged.centers.unova
	staged.get_or_add("centers",{}).erase("unova")
	if staged.get("last_pokemon_center",{}).get("region","")=="unova":
		staged.erase("last_pokemon_center")
	return staged

static func switch_unova_memory(data: Dictionary) -> Dictionary:
	if data.get("region","")!="unova" or not data.get("flags",{}).get("u2_champion",false): return {}
	var in_past: bool=data.flags.get("u1_memory",false)
	var here: Dictionary=HOMES.unova if in_past else SEQUEL_HOME
	if data.get("map","")!=here.map: return {}
	var staged:=data.duplicate(true)
	var home: Dictionary=SEQUEL_HOME if in_past else HOMES.unova
	var centers: Dictionary=staged.get_or_add("centers",{})
	var records: Dictionary=staged.get_or_add("unova_centers",{})
	if centers.has("unova"): records["bw" if in_past else "b2"]=centers.unova
	centers.erase("unova")
	if staged.get("last_pokemon_center",{}).get("region","")=="unova": staged.erase("last_pokemon_center")
	var next: String="b2" if in_past else "bw"
	if records.has(next):
		centers.unova=records[next]
		staged.last_pokemon_center=records[next]
	staged.flags.u1_memory=not in_past
	staged.map=home.map
	staged.pos=home.at.duplicate()
	staged.facing="down"
	for key in ["surfing","diving","bike"]: staged[key]=false
	for key in ["field_elevation","location_label"]: staged.erase(key)
	return staged

static func _arrange_party(staged: Dictionary, mode: String) -> bool:
	if mode=="carried": return true
	var party_script=load("res://core/party.gd")
	party_script.migrate_legacy_box(staged)
	var boxes: Array=staged.get("boxes",[])
	for mon in staged.get("party",[]):
		if mon is Dictionary and not mon.is_empty() and not party_script.store_in_boxes(boxes,mon): return false
	staged.boxes=boxes
	staged.party=[]
	return true
