extends Node
## 数据中枢：所有内容都从 content/ 下的 JSON 读，代码里不写死任何地区、物种、招式。
## 加一个地区 = 加一个目录 + 一份 region.json，内核不需要改动。

var species: Dictionary = {}          # id:int -> 种族数据
var moves: Dictionary = {}            # id:int -> 招式数据
var tm_map: Dictionary = {}           # "招式学习器 01" -> 招式 id
var abilities: Dictionary = {}        # id:int -> 特性（预留）
var items: Dictionary = {}            # id:int -> 道具（预留）
var regions: Dictionary = {}          # region_id:String -> region.json
var types: Dictionary = {}            # 属性克制表 attacker -> {defender: 倍率}
var types_cn: Dictionary = {}         # 属性中文名
var gimmicks: Dictionary = {}         # 战斗变化表：Z 招式 / 极巨招式 / 超极巨专属
var hms: Dictionary = {}              # 秘传学习器 key -> {name, move}
var tera_shards: Dictionary = {}      # 太晶碎块：属性 -> 道具名
var berries: Dictionary = {}          # 树果 key -> 中文名
var held_items: Dictionary = {}       # 携带道具 key -> {name, desc}
var evo_items: Dictionary = {}        # 进化道具 key -> 中文名
var ability_effects: Dictionary = {}  # 特性名 -> 数值化效果（见 content/ability_effects.json）
var gmax_effects: Dictionary = {}     # 超极巨专属招式的附加效果

const CORE_TABLES := {
	"species": "res://content/species.json",
	"moves": "res://content/moves.json",
	"abilities": "res://content/abilities.json",
	"items": "res://content/items.json",
}

func _ready() -> void:
	# Install the bundled CJK font after resources are imported, including standalone UI scenes.
	var theme := ThemeDB.get_default_theme()
	theme.default_font = load("res://assets/fonts/field-sans.otf")
	ThemeDB.fallback_font = theme.default_font

func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("数据文件不存在: " + path)
		return null

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("无法打开: " + path)
		return null

	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("JSON 解析失败: " + path)
	return parsed

## 加载全世代通用表。返回是否成功。
func load_core_tables() -> bool:
	var type_table = load_json("res://content/types.json")
	if type_table != null:
		types = type_table

	# 属性中文名与太晶碎块表：界面显示要用，缺了就退回英文 key
	var cn_table = load_json("res://content/types_cn.json")
	if cn_table is Dictionary:
		types_cn = cn_table
	var shard_table = load_json("res://content/tera_shards.json")
	if shard_table is Dictionary:
		tera_shards = shard_table
	var held = load_json("res://content/items.json")
	if held is Array:
		for it in held:
			if it is Dictionary:
				held_items[String((it as Dictionary).get("key", ""))] = it
	var tm_table = load_json("res://content/tm_map.json")
	if tm_table is Dictionary:
		tm_map = tm_table
	var hm_table = load_json("res://content/hms.json")
	if hm_table is Dictionary:
		hms = hm_table
	var berry_table = load_json("res://content/berries.json")
	if berry_table is Dictionary:
		berries = berry_table

	# 战斗变化表（Z 招式 / 极巨招式 / 超极巨专属）允许缺失，缺了就不给变化
	var ae = load_json("res://content/ability_effects.json")
	if ae is Dictionary:
		ability_effects = ae
	var ev = load_json("res://content/evo_items.json")
	if ev is Dictionary:
		evo_items = ev

	var ge = load_json("res://content/gmax_effects.json")
	if ge is Dictionary:
		for k2 in ge.keys():
			gmax_effects[int(str(k2))] = ge[k2]

	var gm = load_json("res://content/gimmicks.json")
	if gm is Dictionary:
		gimmicks = gm

	for key in CORE_TABLES:
		var path: String = CORE_TABLES[key]
		var rows = load_json(path)
		if rows == null:
			# 预留表允许缺失，但物种与招式必须有
			if key == "species" or key == "moves":
				return false
			continue
		var table: Dictionary = {}
		for row in rows:
			table[int(row["id"])] = row
		set(key, table)

	return not species.is_empty() and not moves.is_empty()

var destinations: Dictionary = {}
var world_passages: Array = []

func travel_regions() -> Dictionary:
	if destinations.is_empty():
		var catalog = load_json("res://content/world_destinations.json")
		if catalog is Dictionary:
			destinations = catalog.get("regions", {})
			world_passages = catalog.get("passages", [])
	return destinations

## 保留完整地图目录，具体地图首次进入时才读入内存。
func load_region(region_id: String) -> Dictionary:
	if regions.has(region_id):
		return regions[region_id]
	var base := "res://content/regions/%s/" % region_id
	var region = load_json(base + "region.json")
	if region == null:
		return {}

	region["id"] = region_id
	region["_base"] = base
	var map_ids: Array = region.get("maps", []).duplicate()
	for file_name in DirAccess.get_files_at(base + "maps"):
		if file_name.ends_with(".json") and not map_ids.has(file_name.get_basename()):
			map_ids.append(file_name.get_basename())
	map_ids.sort()
	region["map_ids"] = map_ids
	region["maps"] = {}
	regions[region_id] = region
	return region

func load_map(region_id: String, map_id: String) -> Dictionary:
	if not regions.has(region_id):
		load_region(region_id)
	if not regions.has(region_id):
		return {}

	var region: Dictionary = regions[region_id]
	if region["maps"].has(map_id):
		return region["maps"][map_id]

	var data = load_json(String(region["_base"]) + "maps/" + map_id + ".json")
	if data == null:
		return {}

	data["id"] = map_id
	data["region"] = region_id
	region["maps"][map_id] = data
	return data

## 种族值可被存档覆盖（修改器改的东西要能存下来），所以留一份原始表做底
var base_species: Dictionary = {}

func snapshot_species() -> void:
	base_species = species.duplicate(true)

## 把存档里的种族值覆盖合并进生效表；没覆盖的保持原始值
func apply_species_overrides(ov: Dictionary) -> void:
	if base_species.is_empty():
		snapshot_species()
	for id in base_species.keys():
		var row: Dictionary = (base_species[id] as Dictionary).duplicate(true)
		var key := str(id)
		if ov.has(key):
			var patch: Dictionary = ov[key]
			var base: Dictionary = row.get("base", {}).duplicate(true)
			for k in base.keys():
				if patch.has(k):
					base[k] = int(patch[k])
			row["base"] = base
			if patch.has("catch_rate"):
				row["catch_rate"] = int(patch["catch_rate"])
		species[id] = row

## 商店货架：也走数据，加商品不用改界面
const SHOP_PATH := "res://content/shop.json"

func load_shop() -> Array:
	var rows = load_json(SHOP_PATH)
	if rows == null or not (rows is Array):
		return []
	return rows

func species_of(species_id: int) -> Dictionary:
	return species.get(species_id, {})

func move_of(move_id: int) -> Dictionary:
	return moves.get(move_id, {})

## ---------- 形态 ----------
## Mega、极巨化、地区形态都是同一只宝可梦的形态，不是新的图鉴号。
## 取形态就用这里，别自己拼字段。

func forms_of(species_id: int) -> Array:
	var sp: Dictionary = species.get(species_id, {})
	var f = sp.get("forms", [])
	return f if f is Array else []

func form_of(species_id: int, form_key: String) -> Dictionary:
	if form_key == "":
		return {}
	for f in forms_of(species_id):
		if f is Dictionary and String((f as Dictionary).get("key", "")) == form_key:
			return f
	return {}

## 把形态叠在物种上：种类、属性、种族值、立绘都可能是形态自己的
func stats_of(species_id: int, form_key: String = "") -> Dictionary:
	var sp: Dictionary = species.get(species_id, {})
	if sp.is_empty():
		return {}
	var f := form_of(species_id, form_key)
	if f.is_empty():
		return sp
	var out := sp.duplicate(true)
	out["form"] = form_key
	out["types"] = f.get("types", sp.get("types", []))
	out["base"] = f.get("base", sp.get("base", {}))
	var label := String(f.get("label", ""))
	if label != "":
		out["name"] = "%s（%s）" % [String(sp.get("name", "?")), label]
	if not (f.get("abilities", []) as Array).is_empty():
		out["abilities"] = f.get("abilities")
	return out

## 立绘：形态有自己的图就用形态的
## 队伍/箱子这种小格用游戏里的像素立绘（64x64），大图鉴才用官方画
func party_sprite_path(species_id: int) -> String:
	var p := "res://assets/party/%d.png" % species_id
	if ResourceLoader.exists(p):
		return p
	return sprite_path(species_id)


## 队伍 / 详情界面用的大立绘（官方 artwork，128px），没有就退回像素图
func party_hd_path(species_id: int) -> String:
	var p := "res://assets/party_hd/%d.png" % species_id
	if ResourceLoader.exists(p):
		return p
	return party_sprite_path(species_id)


func sprite_path(species_id: int, form_key: String = "") -> String:
	var f := form_of(species_id, form_key)
	var p := String(f.get("sprite", "")) if not f.is_empty() else ""
	if p != "":
		return p
	return "res://assets/mon/%d.png" % species_id

## 这只在战斗中能变成什么：mega 优先，否则 gmax，没有就空
func battle_form_of(species_id: int, form_key: String = "") -> Dictionary:
	for f in forms_of(species_id):
		if not (f is Dictionary):
			continue
		if String(f.get("kind", "")) in ["mega", "gmax"]:
			return f
	return {}

## ---------------- 战斗中的变化系统 ----------------
## Mega / 超极巨：看形态表；Z 招式与极巨招式：看 gimmicks.json。
## 这三套在原版都是一场战斗只能用其中一种，不能叠加。

## 进化道具的中文名：源码里写 ITEM_FIRE_STONE，界面要显示「火之石」
## 属性中文名：火 / 水 / 草，界面上不显示英文 key
func type_name(key: String) -> String:
	return String(types_cn.get(key, key))

## 树果中文名
## 特性效果：没写的特性返回空字典，调用方靠默认值兜底
func ability_effect(name: String) -> Dictionary:
	var d = ability_effects.get(name, {})
	return d if d is Dictionary else {}

func berry_def(key: String) -> Dictionary:
	var d = berries.get(key, {})
	return d if d is Dictionary else {}

func berry_name(key: String) -> String:
	var d := berry_def(key)
	return String(d.get("name", key))

func item_name(key: String) -> String:
	return String((held_items.get(key, {}) as Dictionary).get("name", key))

func evo_item_name(key: String) -> String:
	return String(evo_items.get(key.replace("ITEM_", ""), key.replace("ITEM_", "")))

## 超极巨专属招式的附加效果；没有就返回空
func gmax_effect(move_id: int) -> Dictionary:
	var e = gmax_effects.get(move_id, {})
	return e if e is Dictionary else {}

## 这个属性能用的 Z 招式（通用那条）
func z_move_for_type(ty: String) -> int:
	return int((gimmicks.get("z_by_type", {}) as Dictionary).get(ty, 0))

## 专属 Z 招式：只有那几只宝可梦有
func z_move_for_species(species_key: String) -> int:
	return int((gimmicks.get("z_exclusive", {}) as Dictionary).get(species_key, 0))

## 这个属性极巨化后的招式
func max_move_for_type(ty: String) -> int:
	return int((gimmicks.get("max_by_type", {}) as Dictionary).get(ty, 0))

## 超极巨专属招式：物种 + 属性
func gmax_move_for(species_key: String, ty: String) -> int:
	var row = (gimmicks.get("gmax_by_species", {}) as Dictionary).get(species_key, {})
	if not (row is Dictionary):
		return 0
	return int((row as Dictionary).get(ty, 0))

## Z 招式威力：按基础招式威力换算
func z_power(base_power: int) -> int:
	for row in gimmicks.get("z_power", []):
		if base_power >= int(row[0]):
			return int(row[1])
	return 100

## 极巨招式威力：先算档位，再按属性区分（格斗/毒偏弱）
func max_power(base_power: int, ty: String) -> int:
	var tier := 1
	for row in gimmicks.get("max_power", {}).get("tier_up", []):
		if base_power >= int(row[0]):
			tier = int(row[1])
			break
	var table: Array = (gimmicks.get("max_power", {}).get("weak", [])
		if ty in ["fighting", "poison"] else gimmicks.get("max_power", {}).get("normal", []))
	if table.is_empty():
		return 100
	return int(table[clampi(tier - 1, 0, table.size() - 1)])

func battle_forms_of(species_id: int) -> Array:
	var out: Array = []
	for f in forms_of(species_id):
		if f is Dictionary and String(f.get("kind", "")) in ["mega", "gmax"]:
			out.append(f)
	return out
