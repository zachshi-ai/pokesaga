extends RefCounted
## 队伍数据：单档跨地区共用。战斗与菜单都读这里，避免两套数据源打架。
## 12 格上限与之前 ROM 版一致，空槽用 {} 占位而不是 null，便于下标运算。

const MAX_SIZE := 12
const Growth := preload("res://core/growth.gd")

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
	return {
		"species_id": species_id,
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
	}

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
	var max_hp := int((2 * (int(base.get("hp", 1)) + int(plus.get("hp", 0))) + 31) * lv / 100.0) + lv + 10
	m["max_hp"] = max_hp
	if keep_ratio and old_max > 0:
		m["hp"] = clampi(int(round(float(old_hp) / old_max * max_hp)), 0, max_hp)
	else:
		m["hp"] = clampi(old_hp, 0, max_hp)
	m["hp_text"] = "%d/%d" % [int(m["hp"]), max_hp]
	m["stats"] = {
		"atk": int((2 * (int(base.get("atk", 1)) + int(plus.get("atk", 0))) + 31) * lv / 100.0) + 5,
		"def": int((2 * (int(base.get("def", 1)) + int(plus.get("def", 0))) + 31) * lv / 100.0) + 5,
		"spa": int((2 * (int(base.get("spa", 1)) + int(plus.get("spa", 0))) + 31) * lv / 100.0) + 5,
		"spd": int((2 * (int(base.get("spd", 1)) + int(plus.get("spd", 0))) + 31) * lv / 100.0) + 5,
		"spe": int((2 * (int(base.get("spe", 1)) + int(plus.get("spe", 0))) + 31) * lv / 100.0) + 5,
	}

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
