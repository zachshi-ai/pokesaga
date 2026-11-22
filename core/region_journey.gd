extends RefCounted

const NAMES := {"kanto":"关都","johto":"城都","hoenn":"丰缘","sinnoh":"神奥"}
const HOMES := {
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
		data.get_or_add("regional_badges",{}).get_or_add("sinnoh",[])
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
	var regional := {"kanto":[],"johto":[],"hoenn":[],"sinnoh":[]}
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
	return data.regional_badges.get("kanto" if region=="sevii" else region,[])

static func grant(data: Dictionary, region: String, badge: String) -> void:
	migrate(data)
	var local := badges(data,region)
	if badge not in local: local.append(badge)
	if badge not in data.badges: data.badges.append(badge)

static func begin(data: Dictionary, region: String, mode: String) -> Dictionary:
	if region not in HOMES or mode not in ["boxed","carried"]: return {}
	var staged := data.duplicate(true)
	migrate(staged)
	if staged.chapters.has(region): return {}
	if mode == "boxed":
		var party_script = load("res://core/party.gd")
		party_script.migrate_legacy_box(staged)
		var boxes: Array = staged.get("boxes",[])
		for mon in staged.get("party",[]):
			if mon is Dictionary and not mon.is_empty() and not party_script.store_in_boxes(boxes,mon):
				return {}
		staged.boxes = boxes
		staged.party = []
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
	return staged
