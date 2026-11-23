extends RefCounted
## 队伍数据：单档跨地区共用。战斗与菜单都读这里，避免两套数据源打架。
## 12 格上限与之前 ROM 版一致，空槽用 {} 占位而不是 null，便于下标运算。

const MAX_SIZE := 12
const Growth := preload("res://core/growth.gd")

const SHINY_KINDS := ["none", "star", "square"]

const STAT_LABELS := {"hp":"体力","atk":"攻击","def":"防御","spa":"特攻","spd":"特防","spe":"速度"}
# Wild Legendary Pokémon, Mythical Pokémon and Ultra Beasts available in Alola.
const ALOLA_SPECIAL := [144,145,146,150,151,243,244,245,249,250,251,377,378,379,380,381,382,383,384,385,386,480,481,482,483,484,485,486,487,488,489,490,491,492,493,494,638,639,640,641,642,643,644,645,646,647,648,649,716,717,718,719,720,721,772,773,785,786,787,788,789,790,791,792,793,794,795,796,797,798,799,800,801,802,803,804,805,806,807]

## Called once, at the birth of a new Alola Pokémon. Older individuals keep their saved stats.
static func init_alola_ivs(mon: Dictionary, rng: RandomNumberGenerator, fixed: Dictionary={}, guaranteed: int=0) -> void:
	if mon.is_empty() or mon.get("alola_ivs",false):return
	var natural: Dictionary={}
	for stat in STAT_LABELS:
		natural[stat]=rng.randi_range(0,31)
	if int(mon.species_id) in ALOLA_SPECIAL or "TOTEM" in str(mon.get("form","")):guaranteed=maxi(guaranteed,3)
	if guaranteed>0:
		var remaining:=STAT_LABELS.keys()
		for i in mini(6,guaranteed):
			var index:=rng.randi_range(0,remaining.size()-1)
			natural[remaining.pop_at(index)]=31
	for stat in fixed:
		if STAT_LABELS.has(stat):natural[stat]=clampi(int(fixed[stat]),0,31)
	mon.alola_ivs=true
	mon.ivs=natural
	mon.hyper_trained={}
	recalc(mon,true)

static func effective_iv(mon: Dictionary, stat: String) -> int:
	if not mon.get("alola_ivs",false) or mon.get("hyper_trained",{}).get(stat,false):return 31
	return int(mon.get("ivs",{}).get(stat,31))

static func shiny_kind(mon: Dictionary) -> String:
	var kind := str(mon.get("shiny_kind", ""))
	if kind in SHINY_KINDS:
		return kind
	return "star" if bool(mon.get("shiny", false)) else "none"

static func set_shiny_kind(mon: Dictionary, kind: String) -> void:
	mon["shiny_kind"] = kind if kind in SHINY_KINDS else "none"
	mon["shiny"] = mon.shiny_kind != "none"

## 两类合计 1/4096，其中 1/16 为方块闪。野外与孵蛋使用同一次抽取。
static func roll_shiny(rng: RandomNumberGenerator) -> String:
	var roll := rng.randi_range(0, 65535)
	if roll == 0:
		return "square"
	return "star" if roll < 16 else "none"

## 野生携带的树果：回血与解状态常见，抗性果和能力果少见
static func _random_berry() -> String:
	var common: Array = []
	var rare: Array = []
	for k in Data.berries.keys():
		var kind := String((Data.berries[k] as Dictionary).get("kind", ""))
		if kind in ["heal", "cure", "cure_all", "pp"]:
			common.append(k)
		elif kind != "":
			rare.append(k)
	var pool: Array = common if (randi() % 100) < 75 else rare
	if pool.is_empty():
		return ""
	return String(pool[randi() % pool.size()])

static func make(species_id: int, level: int, move_ids: Array, form_key: String = "") -> Dictionary:
	# 形态只改属性/种族值/立绘，图鉴号不变
	var sp: Dictionary = Data.stats_of(species_id, form_key)
	var base: Dictionary = sp.get("base", {})
	var max_hp := int((2 * int(base.get("hp", 1)) + 31) * level / 100.0) + level + 10
	var stats := {
		"atk": int((2 * int(base.get("atk", 1)) + 31) * level / 100.0) + 5,
		"def": int((2 * int(base.get("def", 1)) + 31) * level / 100.0) + 5,
		"spa": int((2 * int(base.get("spa", 1)) + 31) * level / 100.0) + 5,
		"spd": int((2 * int(base.get("spd", 1)) + 31) * level / 100.0) + 5,
		"spe": int((2 * int(base.get("spe", 1)) + 31) * level / 100.0) + 5,
	}
	var moves: Array = []
	var pp: Array = []
	for mid in move_ids:
		var mv: Dictionary = Data.move_of(int(mid))
		if mv.is_empty():
			continue
		moves.append(int(mid))
		pp.append(int(mv.get("pp", 10)))
	var abil_ids: Array = sp.get("abilities", [])
	var ability := 0
	var ability_name := ""
	if not abil_ids.is_empty():
		ability = int(abil_ids[0])
		var ad: Dictionary = Data.abilities.get(ability, {})
		ability_name = String(ad.get("name", ""))
	# 大约两成的野生宝可梦带树果
	var berry := ""
	if randi() % 5 == 0:
		berry = _random_berry()
	var tera := ""
	var ty_list: Array = sp.get("types", [])
	if not ty_list.is_empty():
		tera = String(ty_list[0])
	var mon := {
		"species_id": species_id,
		"friendship": int(Data.training_values.get(str(species_id), {}).get("friendship", 70)),
		"form": form_key,
		"tera_type": tera,
		"berry": berry,
		"held": "",
		"ability": ability,
		"ability_name": ability_name,
		"name": String(sp.get("name", "?")),
		"types": sp.get("types", []),
		"level": level,
		"max_hp": max_hp,
		"hp": max_hp,
		"hp_text": "%d/%d" % [max_hp, max_hp],
		"stats": stats,
		"moves": moves,
		"pp": pp,
		"exp": Growth.exp_for_level(level, String(sp.get("growth", "medium_fast"))),
		"nature": "坦率",
		"shiny": false,
		"shiny_kind": "none",
	}

	var female_ratio := int(sp.get("gender",255))
	if female_ratio != 255:
		var sex_rng := RandomNumberGenerator.new()
		mon["sex"] = "female" if female_ratio==254 or sex_rng.randi_range(0,253)<female_ratio else "male"
	return mon

## 进化：换物种、按新种族值重算、保留等级与当前血量比例
static func evolve(m: Dictionary, to_species: int, to_form := "") -> bool:
	if m.is_empty():
		return false
	var sp: Dictionary = Data.stats_of(to_species, to_form)
	if sp.is_empty():
		return false
	m["species_id"] = to_species
	m["form"] = to_form
	m["name"] = String(sp.get("name", "?"))
	m["types"] = sp.get("types", [])
	m["sprite"] = Data.sprite_path(to_species, to_form)
	recalc(m, true)
	return true

## 换形态：属性、种族值、立绘一起换，血量按比例留下
static func set_form(m: Dictionary, form_key: String) -> void:
	if m.is_empty():
		return
	var sid := int(m.get("species_id", 0))
	if not form_key.is_empty() and Data.form_of(sid, form_key).is_empty():
		return
	m["form"] = form_key
	var sp: Dictionary = Data.stats_of(sid, form_key)
	m["name"] = String(sp.get("name", m.get("name", "?")))
	m["types"] = sp.get("types", m.get("types", []))
	m["sprite"] = Data.sprite_path(sid, form_key)
	recalc(m, true)

## 按当前种族值重算一只的六维与满血（改完种族值、改完等级后调用）
static func recalc(m: Dictionary, keep_ratio: bool = false) -> void:
	if m.is_empty():
		return
	var sp: Dictionary = Data.stats_of(int(m.get("species_id", 0)), String(m.get("form", "")))
	var base: Dictionary = sp.get("base", {})
	var lv := clampi(int(m.get("level", 1)), 1, 100)
	var old_max := int(m.get("max_hp", 0))
	var old_hp := int(m.get("hp", 0))
	# 增强剂加的是基础点，独立存在 plus 里，换形态/升级都跟着走
	var plus: Dictionary = m.get("plus", {}) if m.get("plus", {}) is Dictionary else {}
	var effort: Dictionary = m.get("effort", {})
	var stats: Dictionary={}
	for stat in STAT_LABELS:
		var points:=2*(int(base.get(stat,1))+int(plus.get(stat,0)))+effective_iv(m,stat)+int(effort.get(stat,0))/4
		stats[stat]=int(points*lv/100.0)+(lv+10 if stat=="hp" else 5)
	var max_hp:=int(stats.hp)
	stats.erase("hp")
	m["stats"]=stats
	m["max_hp"]=max_hp
	if keep_ratio and old_max>0:
		m["hp"]=clampi(roundi(float(old_hp)*max_hp/old_max),0,max_hp)
	else:
		m["hp"]=clampi(old_hp,0,max_hp)
	m["hp_text"]="%d/%d" % [int(m.hp),max_hp]

## 把队伍压紧：空槽剔除、补齐到 MAX_SIZE 个 {}，并刷新 hp_text
static func compact(party: Array) -> Array:
	var out: Array = []
	for m in party:
		if m is Dictionary and not m.is_empty() and int(m.get("species_id", 0)) > 0:
			out.append(m)
	out = out.slice(0, MAX_SIZE)
	while out.size() < MAX_SIZE:
		out.append({})
	return out

## 战斗用：把队伍转成战斗单位（复制一份，避免战斗里掉血影响存档）
static func to_combatants(party: Array, levels: Array = []) -> Array:
	var out: Array = []
	for m in party:
		if m is Dictionary and not m.is_empty():
			var c: Dictionary = m.duplicate(true)
			c.erase("hp_text")
			out.append(c)
	return out

## 从战斗结果回写血量：只写 hp，不写别的字段
static func sync_hp(from_combatants: Array, party: Array) -> void:
	for i in mini(from_combatants.size(), party.size()):
		if party[i] is Dictionary and not party[i].is_empty():
			var hp := int(from_combatants[i].get("hp", party[i].get("hp", 0)))
			party[i]["hp"] = clampi(hp, 0, int(party[i].get("max_hp", 1)))
			party[i]["hp_text"] = "%d/%d" % [int(party[i]["hp"]), int(party[i].get("max_hp", 1))]

const BOX_COUNT := 200
const BOX_SIZE := 30

static func occupied(slots: Array) -> int:
	var count := 0
	for mon in slots:
		if mon is Dictionary and not mon.is_empty():
			count += 1
	return count

## Keep the original indices of occupied slots when filling holes in an old save.
static func insert_into(slots: Array, mon: Dictionary, capacity: int) -> bool:
	if mon.is_empty():
		return false
	for i in mini(slots.size(), capacity):
		if slots[i] == null or (slots[i] is Dictionary and slots[i].is_empty()):
			slots[i] = mon
			return true
	if slots.size() < capacity:
		slots.append(mon)
		return true
	return false

static func restore_trim(mon: Variant, deposited := false) -> void:
	if not mon is Dictionary or not mon.has("kalos_trim_until"):return
	if deposited or int(Time.get_unix_time_from_system())>=int(mon.kalos_trim_until):
		mon.erase("kalos_trim_until")
		if int(mon.get("species_id",0))==676:set_form(mon,"")

static func store_in_boxes(boxes: Array, mon: Dictionary) -> bool:
	for i in BOX_COUNT:
		if i == boxes.size():
			boxes.append({"name": "箱子 %d" % (i+1), "mons": []})
		if boxes[i] is Dictionary:
			if not boxes[i].has("mons"):
				boxes[i]["mons"] = []
			if boxes[i].mons is Array and insert_into(boxes[i].mons, mon, BOX_SIZE):
				restore_trim(mon,true)
				return true
	return false

static func migrate_legacy_box(save: Dictionary) -> void:
	var legacy = save.get("box", [])
	if not legacy is Array or legacy.is_empty():
		return
	if not save.get("boxes") is Array:
		save["boxes"] = []
	var pending: Array = []
	for mon in legacy:
		if mon is Dictionary and not mon.is_empty() and not store_in_boxes(save.boxes, mon):
			pending.append(mon)
	if pending.is_empty():
		save.erase("box")
	else:
		save["box"] = pending
