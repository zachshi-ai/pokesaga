extends RefCounted
## Map data keeps gameplay roles and trainer classes; the pictures can be updated independently.
const DIRECTORY := "res://assets/oras_npc/"
const LEADERS := {"小刚":"brock", "小霞":"misty", "马志士":"surge", "莉佳":"erika", "阿桔":"koga", "娜姿":"sabrina", "夏伯":"blaine", "坂木":"giovanni"}
const TRAINERS := {
	"Bird Keeper":"bird_keeper", "Picnicker":"picnicker", "Swimmer M":"swimmer_m",
	"Swimmer F":"swimmer_f", "Fisherman":"fisherman", "Youngster":"youngster", "Lass":"lass",
	"Hiker":"hiker", "Camper":"camper", "Bug Catcher":"bug_catcher", "Ruin Maniac":"ruin_maniac",
	"Aroma Lady":"aroma_lady", "Pkmn Ranger":"ranger", "Beauty":"beauty", "Pokemaniac":"pokemaniac",
	"Tuber":"tuber", "Cooltrainer":"cooltrainer_m", "Gentleman":"gentleman",
	"Pkmn Breeder":"breeder", "Rocker":"rocker",
	"钓鱼人":"fisherman", "登山男":"hiker", "养鸟人":"bird_keeper", "野餐少女":"picnicker",
	"捕虫少年":"bug_catcher", "宝可梦狂":"pokemaniac", "短裤小子":"youngster", "露营少年":"camper",
	"研究员":"scientist", "水手":"sailor", "少女":"lass", "空手道王":"blackbelt", "大姐姐":"beauty",
	"绅士":"gentleman", "喷火者":"kindler", "学生":"schoolkid"
}
const NAMES := {"小镇少女":"lass", "开拓少女":"battle_girl", "对战塔前台":"clerk", "登记员":"clerk", "工地师傅":"man", "女士":"woman", "空手道师父":"old_expert"}

static var _shadow: GradientTexture2D

static func foot_shadow() -> GradientTexture2D:
	if _shadow == null:
		var falloff := Gradient.new()
		falloff.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		falloff.colors = PackedColorArray([Color(0.06,0.11,0.16,0.4), Color(0.06,0.11,0.16,0.26), Color(0.06,0.11,0.16,0)])
		_shadow = GradientTexture2D.new()
		_shadow.width = 48
		_shadow.height = 16
		_shadow.fill = GradientTexture2D.FILL_RADIAL
		_shadow.fill_from = Vector2(0.5,0.5)
		_shadow.fill_to = Vector2(1,0.5)
		_shadow.gradient = falloff
	return _shadow

static func texture_for(npc: Dictionary) -> Texture2D:
	var name_text := str(npc.get("name", ""))
	var role := str(npc.get("gfx", ""))
	if npc.has("gives_mon") and name_text == "精灵球":
		return load("res://assets/props/ball.png")
	if npc.get("transit", false):
		role = "navigator"
	elif npc.has("heal"):
		role = "nurse"
	elif npc.has("shop"):
		role = "clerk"
	elif npc.get("form_items", false):
		role = "scientist"
	elif npc.has("daycare"):
		role = "old_woman" if role == "old_woman" else "old_man"
	elif name_text.begins_with("馆主 "):
		role = str(LEADERS.get(name_text.trim_prefix("馆主 "), role))
	elif name_text.contains(" 的 "):
		role = str(TRAINERS.get(name_text.get_slice(" 的 ", 0), role))
	elif name_text.begins_with("游泳者 "):
		role = "swimmer_f" if str(npc.get("trainer","")).begins_with("SwimmerF") else "swimmer_m"
	elif name_text.begins_with("宝可梦迷 "):
		role = "pokefan_f" if str(npc.get("trainer","")).begins_with("PokefanF") else "pokefan_m"
	elif name_text.contains(" ") and npc.has("battle"):
		role = str(TRAINERS.get(name_text.get_slice(" ",0), role))
	elif NAMES.has(name_text) or role == "":
		role = str(NAMES.get(name_text, "man"))
	var path := DIRECTORY + role + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	return null
