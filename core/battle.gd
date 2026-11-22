class_name Battle
extends RefCounted
## 战斗内核：纯逻辑，不碰渲染、不碰输入。
## 这样做的好处是可以在 headless 下跑成千上万场做回归测试，
## 接新地区、新世代规则时只改这里的一方，不牵动界面。

signal variant_seen(side: String, mon: Dictionary)
signal health_changed(line: int, side: String, slot: int, mon: Dictionary)

const STAGE_MULT := [0.33, 0.4, 0.5, 0.66, 1.0, 1.5, 2.0, 2.5, 3.0]
const FieldScript := preload("res://core/field.gd")

var team_a: Array = []
var team_b: Array = []
var fishing_encounter := false
var active_a := 0
var active_b := 0
var log: Array = []
var rng := RandomNumberGenerator.new()
var over := false
var winner := ""
var caught := false          # 是否抓到（抓到即结束，不算打赢也不算打输）
var completed_turns := 0
var caught_species := 0
var guard_turns := {"a":0, "b":0}
var acting_side := ""
var fled := false
var last_crit := false      # 上一次攻击是否会心（界面要念出来）
var last_berry := ""        # 上一次攻击里对手吃掉的抗性果
var field                       # 天气 / 场地 / 屏障 / 撒菱 / 重力

func _init(seed_value: int = 0) -> void:
	field = FieldScript.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

## 造一只战斗用的宝可梦（个体/努力先按 0 处理，后续接存档时再补）
static func make_combatant(species_id: int, level: int, move_ids: Array, form_key: String = "") -> Dictionary:
	var sp: Dictionary = Data.stats_of(species_id, form_key)
	var c := {
		"species_id": species_id,
		"form": form_key,
		"name": sp.get("name", "?"),
		"types": sp.get("types", []),
		"level": level,
		"moves": [],
		"pp": [],
		"stages": {"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0},
		"fainted": false,
		"status": "",
		"status_turns": 0,
	}
	var ab: Array = sp.get("abilities", [])
	c["ability"] = int(ab[0]) if not (ab as Array).is_empty() else 0
	c["forms_used"] = 0      # Mega / 超极巨 用掉没有
	c["z_used"] = 0          # Z 招式用掉没有
	c["tera_used"] = 0       # 太晶化用掉没有
	c["tera_type"] = ""
	c["tera_active"] = false
	c["gmax_active"] = false
	c["ability_name"] = String((Data.abilities.get(int(c["ability"]), {}) as Dictionary).get("name", ""))
	var base: Dictionary = sp.get("base", {})
	var hp_base := int(base.get("hp", 1))
	c["max_hp"] = int((2 * hp_base + 0) * level / 100.0) + level + 10
	c["stats"] = {
		"atk": int((2 * int(base.get("atk", 1))) * level / 100.0) + 5,
		"def": int((2 * int(base.get("def", 1))) * level / 100.0) + 5,
		"spa": int((2 * int(base.get("spa", 1))) * level / 100.0) + 5,
		"spd": int((2 * int(base.get("spd", 1))) * level / 100.0) + 5,
		"spe": int((2 * int(base.get("spe", 1))) * level / 100.0) + 5,
	}
	c["hp"] = c["max_hp"]
	for mid in move_ids:
		var mv: Dictionary = Data.move_of(int(mid))
		if mv.is_empty():
			continue
		c["moves"].append(int(mid))
		c["pp"].append(int(mv.get("pp", 10)))
	return c

## 队伍来源不止一种（存档队伍 / 程序造的战斗单位），统一补齐战斗必需字段，
## 免得存档里的字典少了 stages、fainted 就在第一次出手时报错。
static func normalize_team(team: Array) -> Array:
	for c in team:
		if not (c is Dictionary):
			continue
		var d: Dictionary = c
		if not d.has("stages"):
			d["stages"] = {"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0}
		if not d.has("status"):
			d["status"] = ""
		if not d.has("status_turns"):
			d["status_turns"] = 0
		if not d.has("form"):
			d["form"] = ""
		if not d.has("forms_used"):
			d["forms_used"] = 0
		if not d.has("z_used"):
			d["z_used"] = 0
		if not d.has("tera_used"):
			d["tera_used"] = 0
		if not d.has("tera_type"):
			var ty0: Array = d.get("types", [])
			d["tera_type"] = String(ty0[0]) if not ty0.is_empty() else ""
		if not d.has("tera_active"):
			d["tera_active"] = false
		if not d.has("gmax_active"):
			d["gmax_active"] = false
		if not d.has("berry"):
			d["berry"] = ""
		if not d.has("held"):
			d["held"] = ""
		if not d.has("no_repeat"):
			d["no_repeat"] = 0
		if not d.has("charging"):
			d["charging"] = {}
		if not d.has("sub_hp"):
			d["sub_hp"] = 0
		if not d.has("protected"):
			d["protected"] = false
		if not d.has("charge"):
			d["charge"] = false
		if not d.has("aqua_ring"):
			d["aqua_ring"] = false
		if not d.has("semi_invuln"):
			d["semi_invuln"] = false
		if not d.has("ability"):
			var ab: Array = (Data.species_of(int(d.get("species_id", 1))) as Dictionary).get("abilities", [])
			d["ability"] = int(ab[0]) if not (ab as Array).is_empty() else 0
			d["ability_name"] = String((Data.abilities.get(int(d["ability"]), {}) as Dictionary).get("name", ""))
		if not d.has("moves"):
			d["moves"] = []
		if not d.has("pp"):
			d["pp"] = []
		var moves: Array = d["moves"]
		var pp: Array = d["pp"]
		while pp.size() < moves.size():
			pp.append(int((Data.move_of(int(moves[pp.size()])) as Dictionary).get("pp", 10)))
		d["pp"] = pp
		if not d.has("stats"):
			var base: Dictionary = (Data.stats_of(int(d.get("species_id", 1)),
				String(d.get("form", ""))) as Dictionary).get("base", {})
			var lv := int(d.get("level", 1))
			d["stats"] = {
				"atk": int((2 * int(base.get("atk", 1))) * lv / 100.0) + 5,
				"def": int((2 * int(base.get("def", 1))) * lv / 100.0) + 5,
				"spa": int((2 * int(base.get("spa", 1))) * lv / 100.0) + 5,
				"spd": int((2 * int(base.get("spd", 1))) * lv / 100.0) + 5,
				"spe": int((2 * int(base.get("spe", 1))) * lv / 100.0) + 5,
			}
		if not d.has("max_hp") or int(d.get("max_hp", 0)) <= 0:
			var b2: Dictionary = (Data.stats_of(int(d.get("species_id", 1)),
				String(d.get("form", ""))) as Dictionary).get("base", {})
			var lv2 := int(d.get("level", 1))
			d["max_hp"] = int((2 * int(b2.get("hp", 1)) + 31) * lv2 / 100.0) + lv2 + 10
		if not d.has("hp"):
			d["hp"] = int(d["max_hp"])
		d["hp"] = clampi(int(d["hp"]), 0, int(d["max_hp"]))
		d["fainted"] = d["hp"] == 0
	return team

func start(a_team: Array, b_team: Array) -> void:
	completed_turns=0
	guard_turns = {"a":0, "b":0}
	acting_side = ""
	field.reset()
	team_a = normalize_team(a_team)
	team_b = normalize_team(b_team)
	active_a = _first_alive(team_a)
	active_b = _first_alive(team_b)
	over = false
	winner = ""
	caught = false
	caught_species = 0
	fled = false
	_check_end()
	if over: return
	_on_send_out("a")
	_on_send_out("b")

## ---------------- 战斗中的形态变化 ----------------
## Mega 进化、极巨化都是同一只宝可梦在战斗里换形态：图鉴号不变，
## 只换属性、种族值、立绘。极巨化额外把血量翻倍。一场战斗每种变化一次。

## Direct hits begin at the move announcement. Other effects describe HP on the next line.
## Consumers copy the value
## before another combatant acts or the same move deals a second hit.
func _set_hp(mon: Dictionary, value: int, at_line := -1) -> void:
	mon.hp = value
	if at_line < 0: at_line = log.size()
	if not team_a.is_empty() and is_same(mon, cur_a()):
		health_changed.emit(at_line, "a", active_a, mon)
	elif not team_b.is_empty() and is_same(mon, cur_b()):
		health_changed.emit(at_line, "b", active_b, mon)

func available_forms(side: String) -> Array:
	var c: Dictionary = cur_a() if side == "a" else cur_b()
	if c["fainted"] or int(c.get("forms_used", 0)) > 0:
		return []
	var list: Array = Data.battle_forms_of(int(c.get("species_id", 0)))
	var cur_form := String(c.get("form", ""))
	var out: Array = []
	for f in list:
		# Mega 之后不能再极巨化，同一时间只维持一个变化
		if cur_form != "" and String(f.get("key", "")) != cur_form:
			continue
		out.append(f)
	return out

## 变化按钮该写什么：Mega 和极巨化是两码事，只有一种时不能都叫 Mega
func form_action_label(side: String) -> String:
	var forms: Array = available_forms(side)
	if forms.is_empty():
		return ""
	var has_mega := false
	var has_gmax := false
	for f in forms:
		var k := String((f as Dictionary).get("kind", ""))
		if k == "mega":
			has_mega = true
		elif k == "gmax":
			has_gmax = true
	if has_mega and has_gmax:
		return "Mega/极巨"
	if has_gmax:
		return "极巨化"
	return "Mega"

func transform(side: String, form_key: String) -> Dictionary:
	var c: Dictionary = cur_a() if side == "a" else cur_b()
	var f: Dictionary = Data.form_of(int(c.get("species_id", 0)), form_key)
	if f.is_empty():
		return {"ok": false, "text": "没有这个形态。"}
	var kind := String(f.get("kind", ""))
	var old_name := String(c["name"])
	var base: Dictionary = f.get("base", {})
	var lv := int(c["level"])
	# 血量按比例迁移，极巨化额外翻倍
	var ratio := 1.0
	if int(c["max_hp"]) > 0:
		ratio = float(int(c["hp"])) / float(int(c["max_hp"]))
	# 按种族值比例换算血量，避免和别处的血量公式打架
	var old_base_hp := int((Data.stats_of(int(c.get("species_id", 0)), String(c.get("form", ""))) as Dictionary)
		.get("base", {}).get("hp", 1))
	var new_max := int(round(float(int(c["max_hp"])) * int(base.get("hp", old_base_hp)) / maxf(1.0, float(old_base_hp))))
	if kind == "gmax":
		new_max *= 2
	c["form"] = form_key
	var sp_name := String((Data.species_of(int(c.get("species_id", 0))) as Dictionary).get("name", old_name))
	c["name"] = "%s（%s）" % [sp_name, String(f.get("label", ""))]
	c["types"] = f.get("types", c["types"])
	c["max_hp"] = new_max
	_set_hp(c, clampi(int(round(ratio * new_max)), 1, new_max))
	c["stats"] = {
		"atk": int((2 * int(base.get("atk", 1)) + 31) * lv / 100.0) + 5,
		"def": int((2 * int(base.get("def", 1)) + 31) * lv / 100.0) + 5,
		"spa": int((2 * int(base.get("spa", 1)) + 31) * lv / 100.0) + 5,
		"spd": int((2 * int(base.get("spd", 1)) + 31) * lv / 100.0) + 5,
		"spe": int((2 * int(base.get("spe", 1)) + 31) * lv / 100.0) + 5,
	}
	c["forms_used"] = int(c.get("forms_used", 0)) + 1
	c["gmax_active"] = kind == "gmax"
	variant_seen.emit(side, c)
	var verb := "极巨化了" if kind == "gmax" else "Mega 进化了"
	return {"ok": true, "text": "%s %s！" % [old_name, verb]}


## ---------------- 特性驱动的形态切换 ----------------
## 这些形态不是玩家按出来的，是特性和携带物触发的：只换属性、种族值、立绘，
## 不占回合，也不消耗 Mega / 极巨化的次数。血量按种族值比例迁移。

func switch_form(side: String, form_key: String, reason: String = "") -> bool:
	var c: Dictionary = cur_a() if side == "a" else cur_b()
	if String(c.get("form", "")) == form_key:
		return false
	var sid := int(c.get("species_id", 0))
	var sp: Dictionary = Data.species_of(sid)
	if sp.is_empty():
		return false
	var f: Dictionary = Data.form_of(sid, form_key)
	if form_key != "" and f.is_empty():
		return false
	var old_base: Dictionary = (Data.stats_of(sid, String(c.get("form", ""))) as Dictionary).get("base", {})
	var ratio := float(int(c["hp"])) / float(maxi(1, int(c["max_hp"])))
	var sp_name := String(sp.get("name", String(c.get("name", ""))))
	if f.is_empty():
		c["form"] = ""
		c["name"] = sp_name
		c["types"] = sp.get("types", c["types"])
	else:
		c["form"] = form_key
		c["types"] = f.get("types", c["types"])
		var label := String(f.get("label", ""))
		c["name"] = sp_name if label == "" else "%s（%s）" % [sp_name, label]
	var new_base: Dictionary = (Data.stats_of(sid, form_key) as Dictionary).get("base", {})
	c["max_hp"] = int(round(float(int(c["max_hp"])) * float(int(new_base.get("hp", 1))) \
		/ maxf(1.0, float(int(old_base.get("hp", 1))))))
	_set_hp(c, clampi(int(round(ratio * float(int(c["max_hp"])))), 0, int(c["max_hp"])))
	var lv := int(c.get("level", 1))
	c["stats"] = {
		"atk": int((2 * int(new_base.get("atk", 1)) + 31) * lv / 100.0) + 5,
		"def": int((2 * int(new_base.get("def", 1)) + 31) * lv / 100.0) + 5,
		"spa": int((2 * int(new_base.get("spa", 1)) + 31) * lv / 100.0) + 5,
		"spd": int((2 * int(new_base.get("spd", 1)) + 31) * lv / 100.0) + 5,
		"spe": int((2 * int(new_base.get("spe", 1)) + 31) * lv / 100.0) + 5,
	}
	variant_seen.emit(side, c)
	if reason != "":
		log.append(reason)
	return true

## 出场时该变成什么形态（太晶变形、ＡＲ系统、面具、阴晴不定、鱼群、界限盾壳）
func _form_switch_on_send_out(c: Dictionary) -> void:
	var side := _side_of(c)
	var ab := _ab(c)
	var sid := int(c.get("species_id", 0))
	var held := String(c.get("held", ""))
	if ab == "太晶变形":
		switch_form(side, "TERAPAGOS_TERASTAL", "%s 的%s让它变成了太晶形态！" % [c["name"], ab])
	elif ab == "ＡＲ系统" and held.begins_with("MEMORY_"):
		var tk := held.substr(7).to_lower()
		switch_form(side, "SILVALLY_" + tk.to_upper(), "%s 的%s按存储碟改变了属性！" % [c["name"], ab])
	elif ab == "鱼群":
		_schooling_check(c)
	elif ab == "界限盾壳":
		_shields_down_check(c)
	elif ab == "阴晴不定":
		_forecast_check(c)
	# 靠道具定形态：洛托姆家电、原始回归宝珠、奈克洛兹玛究极结晶
	var item_form := {
		479: {"ROTOM_HEAT": "ROTOM_HEAT", "ROTOM_WASH": "ROTOM_WASH", "ROTOM_FROST": "ROTOM_FROST",
			"ROTOM_FAN": "ROTOM_FAN", "ROTOM_MOW": "ROTOM_MOW"},
		382: {"BLUE_ORB": "KYOGRE_PRIMAL"},
		383: {"RED_ORB": "GROUDON_PRIMAL"},
		800: {"ULTRANECROZIUM_Z": "NECROZMA_ULTRA"},
	}
	# 石板 / 卡带 / 花 / 腐朽武器：按道具名前缀推到对应形态
	var plate_type := {"FLAME_PLATE": "FIRE", "SPLASH_PLATE": "WATER", "ZAP_PLATE": "ELECTRIC",
		"MEADOW_PLATE": "GRASS", "ICICLE_PLATE": "ICE", "FIST_PLATE": "FIGHTING",
		"TOXIC_PLATE": "POISON", "EARTH_PLATE": "GROUND", "SKY_PLATE": "FLYING",
		"MIND_PLATE": "PSYCHIC", "INSECT_PLATE": "BUG", "STONE_PLATE": "ROCK",
		"SPOOKY_PLATE": "GHOST", "DRACO_PLATE": "DRAGON", "DREAD_PLATE": "DARK",
		"IRON_PLATE": "STEEL", "PIXIE_PLATE": "FAIRY"}
	var suffix_form := ""
	if sid == 493 and plate_type.has(held):
		suffix_form = "ARCEUS_" + String(plate_type[held])
	elif sid == 493 and held.ends_with("_PLATE"):
		suffix_form = "ARCEUS_" + held.trim_suffix("_PLATE")
	elif sid == 649 and held.ends_with("_DRIVE"):
		suffix_form = "GENESECT_" + held.trim_suffix("_DRIVE")
	elif sid == 492 and held == "GRACIDEA":
		suffix_form = "SHAYMIN_SKY"
	elif sid == 888 and held == "RUSTED_SWORD":
		suffix_form = "ZACIAN_CROWNED"
	elif sid == 889 and held == "RUSTED_SHIELD":
		suffix_form = "ZAMAZENTA_CROWNED"
	if suffix_form != "":
		switch_form(side, suffix_form, "%s 借着%s改变了形态！" % [c["name"], Data.item_name(held)])

	if item_form.has(sid) and (item_form[sid] as Dictionary).has(held):
		var fk := String((item_form[sid] as Dictionary)[held])
		switch_form(side, fk, "%s 借着%s改变了形态！" % [c["name"], Data.item_name(held)])

	# 厄诡椪的面具：带着哪张面具就是哪个形态
	var masks := {"OGERPON_TEAL_MASK": "OGERPON_TEAL", "OGERPON_WELLSPRING_MASK": "OGERPON_WELLSPRING",
		"OGERPON_HEARTHFLAME_MASK": "OGERPON_HEARTHFLAME", "OGERPON_CORNERSTONE_MASK": "OGERPON_CORNERSTONE"}
	if masks.has(held) and sid == 1017:
		switch_form(side, String(masks[held]), "%s 戴上了%s！" % [c["name"], Data.item_name(held)])
	# 达摩模式 / 群聚变形：出场先按血量对一次形态
	if ab == "达摩模式":
		_zen_check(c)
	elif ab == "群聚变形":
		_power_construct_check(c)

## 鱼群：等级够、体力过半才成群
func _schooling_check(c: Dictionary) -> void:
	if int(c.get("species_id", 0)) != 746:
		return
	var ok := int(c.get("level", 1)) >= 20 and float(int(c["hp"])) > float(int(c["max_hp"])) * 0.25
	var want := "WISHIWASHI_SCHOOL" if ok else ""
	if switch_form(_side_of(c), want, "" if not ok else "%s 聚集起了同伴，变成了群聚形态！" % c["name"]):
		pass

## 界限盾壳：体力过半是核心，掉到一半以下变回陨石
func _shields_down_check(c: Dictionary) -> void:
	if int(c.get("species_id", 0)) != 774:
		return
	var core := float(int(c["hp"])) > float(int(c["max_hp"])) * 0.5
	if core:
		switch_form(_side_of(c), "MINIOR_CORE_RED", "%s 的壳裂开了，露出了核心！" % c["name"])
	else:
		switch_form(_side_of(c), "", "%s 变回了陨石形态。" % c["name"])

## 达摩模式：体力不到一半变达摩，回到一半以上变回来
func _zen_check(c: Dictionary) -> void:
	if int(c.get("species_id", 0)) != 555:
		return
	var low := float(int(c["hp"])) <= float(int(c["max_hp"])) * 0.5
	var galar := String(c.get("form", "")).begins_with("DARMANITAN_GALAR")
	if low:
		switch_form(_side_of(c), "DARMANITAN_GALAR_ZEN" if galar else "DARMANITAN_ZEN",
			"%s 进入了达摩模式！" % c["name"])
	else:
		switch_form(_side_of(c), "DARMANITAN_GALAR_STANDARD" if galar else "",
			"%s 变回了普通形态。" % c["name"])

## 群聚变形：体力不到一半变完全体
func _power_construct_check(c: Dictionary) -> void:
	if int(c.get("species_id", 0)) != 718:
		return
	var low := float(int(c["hp"])) <= float(int(c["max_hp"])) * 0.5
	if low and String(c.get("form", "")) != "ZYGARDE_COMPLETE":
		switch_form(_side_of(c), "ZYGARDE_COMPLETE", "%s 的细胞聚集起来，变成了完全体形态！" % c["name"])
	elif not low and String(c.get("form", "")) == "ZYGARDE_COMPLETE":
		switch_form(_side_of(c), "ZYGARDE_50_POWER_CONSTRUCT", "%s 散回了 50% 形态。" % c["name"])

## 阴晴不定：形态跟着天气走
func _forecast_check(c: Dictionary) -> void:
	if int(c.get("species_id", 0)) != 351:
		return
	var wmap := {"sun": "CASTFORM_SUNNY", "rain": "CASTFORM_RAINY", "snow": "CASTFORM_SNOWY"}
	var want := String(wmap.get(String(field.weather), ""))
	switch_form(_side_of(c), want, "" if want == "" else "%s 变成了%s的样子！" % [c["name"], field.weather_name(String(field.weather))])

## 回合末统一过一遍靠血量/天气/回合驱动的形态
func _form_switch_end_turn(c: Dictionary) -> void:
	var ab := _ab(c)
	match ab:
		"达摩模式":
			_zen_check(c)
		"鱼群":
			_schooling_check(c)
		"花之礼":
			if int(c.get("species_id", 0)) == 421:
				var sunny := String(field.weather) == "sun"
				var want := "CHERRIM_SUNSHINE" if sunny else ""
				if String(c.get("form", "")) != want:
					switch_form(_side_of(c), want, "%s %s" % [c["name"],
						"在阳光下张开了花瓣！" if sunny else "把花瓣合了起来。"])
		"界限盾壳":
			_shields_down_check(c)
		"群聚变形":
			_power_construct_check(c)
		"阴晴不定":
			_forecast_check(c)
		"牵绊变身":
			if int(c.get("kos", 0)) > 0 and String(c.get("form", "")) != "GRENINJA_BATTLE_BOND":
				switch_form(_side_of(c), "GRENINJA_BATTLE_BOND", "%s 和训练家的羁绊加深了，变成了羁绊形态！" % c["name"])
		"太晶变形":
			if float(int(c["hp"])) <= float(int(c["max_hp"])) * 0.5 \
					and String(c.get("form", "")) != "TERAPAGOS_STELLAR":
				switch_form(_side_of(c), "TERAPAGOS_STELLAR", "%s 的结晶绽放出星晶之光！" % c["name"])
		"饱了又饿":
			if String(c.get("form", "")) == "MORPEKO_HANGRY":
				switch_form(_side_of(c), "", "%s 吃饱了，变回了满腹形态。" % c["name"])
			else:
				switch_form(_side_of(c), "MORPEKO_HANGRY", "%s 饿了，变成了空腹形态！" % c["name"])

## 携带石板 / 卡带：招式属性跟着道具走（制裁光砾、高科技光炮）
func _type_on_item(attacker: Dictionary, mv: Dictionary) -> void:
	if String(mv.get("effect", "")) != "CHANGE_TYPE_ON_ITEM":
		return
	var i2 := String(attacker.get("held", ""))
	var map2 := {"FLAME_PLATE": "fire", "SPLASH_PLATE": "water", "ZAP_PLATE": "electric",
		"MEADOW_PLATE": "grass", "ICICLE_PLATE": "ice", "FIST_PLATE": "fighting",
		"TOXIC_PLATE": "poison", "EARTH_PLATE": "ground", "SKY_PLATE": "flying",
		"MIND_PLATE": "psychic", "INSECT_PLATE": "bug", "STONE_PLATE": "rock",
		"SPOOKY_PLATE": "ghost", "DRACO_PLATE": "dragon", "DREAD_PLATE": "dark",
		"IRON_PLATE": "steel", "PIXIE_PLATE": "fairy",
		"DOUSE_DRIVE": "water", "SHOCK_DRIVE": "electric", "BURN_DRIVE": "fire", "CHILL_DRIVE": "ice"}
	if not map2.has(i2):
		return
	attacker["types"] = [String(map2[i2])]
	log.append("%s 的属性被%s改变了！" % [attacker["name"], Data.item_name(i2)])

## ---------------- Z 招式 ----------------
## 一场战斗一次。先把这一招换成它的 Z 版本，再按 Z 版本打出去。
func z_move_of(c: Dictionary, move_id: int) -> int:
	var key := String((Data.species_of(int(c.get("species_id", 0))) as Dictionary).get("key", ""))
	var form_key := String(c.get("form", ""))
	# 专属 Z：只有那几只，且形态也要对得上（阿罗拉雷丘、黄昏鬃岩狼人这些）
	var excl := Data.z_move_for_species(key)
	if excl <= 0 and form_key != "":
		excl = Data.z_move_for_species(form_key)
	# 通用 Z：按招式属性走
	var mv: Dictionary = Data.move_of(move_id)
	if excl > 0:
		return excl
	return Data.z_move_for_type(String(mv.get("type", "normal")))

func can_use_z(side: String) -> bool:
	var c: Dictionary = cur_a() if side == "a" else cur_b()
	if c.get("fainted", false) or int(c.get("z_used", 0)) > 0:
		return false
	if int(c.get("forms_used", 0)) > 0 or bool(c.get("tera_active", false)):
		return false
	return not Data.gimmicks.is_empty()

func use_z(side: String, idx: int) -> Dictionary:
	var c: Dictionary = cur_a() if side == "a" else cur_b()
	if not can_use_z(side):
		return {"ok": false, "text": "现在不能用 Z 招式。"}
	var moves: Array = c.get("moves", [])
	if idx < 0 or idx >= moves.size():
		return {"ok": false, "text": "没有这一招。"}
	var base_id := int(moves[idx])
	var zid := z_move_of(c, base_id)
	if zid <= 0:
		return {"ok": false, "text": "这一招没有 Z 形态。"}
	c["z_used"] = int(c.get("z_used", 0)) + 1
	return {"ok": true, "move": zid, "base": base_id,
		"text": "%s 的 %s 变成了 Z 招式！" % [String(c["name"]), String((Data.move_of(base_id) as Dictionary).get("name", ""))]}

## 出一招 Z 招式：等级/属性/物特都跟基础招式，威力按换算表
func z_move_data(c: Dictionary, base_id: int) -> Dictionary:
	var zid := z_move_of(c, base_id)
	var base: Dictionary = Data.move_of(base_id)
	var out: Dictionary = (Data.move_of(zid) as Dictionary).duplicate(true)
	if out.is_empty():
		return out
	out["power"] = Data.z_power(int(base.get("power", 60)))
	out["type"] = String(base.get("type", out.get("type", "normal")))
	out["category"] = String(base.get("category", out.get("category", "physical")))
	out["name"] = "%s（Z）" % String(out.get("name", ""))
	return out

## ---------------- 太晶化 ----------------
## 一场战斗一次：属性换成太晶属性，本系加成提到 2 倍。
func can_use_tera(side: String) -> bool:
	var c: Dictionary = cur_a() if side == "a" else cur_b()
	if c.get("fainted", false) or int(c.get("tera_used", 0)) > 0 or bool(c.get("tera_active", false)):
		return false
	if int(c.get("forms_used", 0)) > 0 or int(c.get("z_used", 0)) > 0:
		return false
	return String(c.get("tera_type", "")) != ""

func use_tera(side: String) -> Dictionary:
	var c: Dictionary = cur_a() if side == "a" else cur_b()
	if not can_use_tera(side):
		return {"ok": false, "text": "现在不能太晶化。"}
	var ty := String(c.get("tera_type", ""))
	c["tera_used"] = int(c.get("tera_used", 0)) + 1
	c["tera_active"] = true
	var old_name := String(c["name"])
	c["types"] = [ty]
	c["name"] = "%s（太晶）" % old_name
	variant_seen.emit(side, c)
	return {"ok": true, "text": "%s 太晶化了！属性变成 %s。" % [old_name, ty]}

## 换上场时踩钉子：尖刺、隐形岩、毒菱、黏网、钢刺
func _apply_hazards(side: String, mon: Dictionary) -> void:
	var rock_eff: float = effectiveness("rock", mon.get("types", []))
	var res: Dictionary = field.on_switch_in(side, mon, rock_eff)
	var dmg := int(res.get("damage", 0))
	if dmg > 0:
		_set_hp(mon, maxi(0, int(mon["hp"]) - dmg))
		if int(mon["hp"]) <= 0:
			mon["fainted"] = true
	for line in res.get("text", []):
		log.append(String(line))
	if String(res.get("status", "")) != "":
		mon["status"] = String(res["status"])
		log.append(_status_text(String(mon["name"]), String(res["status"])))
	var stages: Dictionary = res.get("stages", {})
	for k in stages.keys():
		mon["stages"][k] = clampi(int(mon["stages"].get(k, 0)) + int(stages[k]), -6, 6)
		log.append("%s 的%s下降了！" % [mon["name"], _stat_name(String(k))])
	if int(mon["hp"]) <= 0:
		log.append("%s 倒下了！" % mon["name"])

## 登场特性：威吓这类进场就生效的
func _on_send_out(side: String) -> void:
	var me: Dictionary = cur_a() if side == "a" else cur_b()
	var foe: Dictionary = cur_b() if side == "a" else cur_a()
	if me.get("fainted", false):
		return
	me.erase("metronome_move")
	me.erase("metronome_chain")
	me.erase("acted_this_turn")
	variant_seen.emit(side, me)
	if str(me.get("held", "")) == "BERSERK_GENE":
		me.held = ""
		me["spent_gene"] = true
		_apply_stage(me, "atk", 2, log)
		if str(me.get("status", "")).is_empty():
			me.status = "cfu"
			me.status_turns = rng.randi_range(2, 4)
		log.append("%s 的破坏基因被消耗了！" % me.name)
	var me_eff: Dictionary = Data.ability_effect(_ab(me))
	# 出场自动开天气的特性
	var weather_ab := {"扬沙": "sandstorm", "降雨": "rain", "日照": "sun", "降雪": "snow"}
	var wab := _ab(me)
	if weather_ab.has(wab):
		var wk := String(weather_ab[wab])
		var rock_map: Dictionary = {"sun": "HEAT_ROCK", "rain": "DAMP_ROCK",
			"sandstorm": "SMOOTH_ROCK", "snow": "ICY_ROCK"}
		var rock: String = String(rock_map.get(wk, ""))
		var turns := 8 if String(me.get("held", "")) == rock else 5
		log.append(field.set_weather(wk, turns))
		log.append("%s 的%s改变了天气！" % [me["name"], wab])

	# 出场自动开场地（电气/青草/薄雾/精神制造者）
	var terrain_on := String(Data.ability_effect(_ab(me)).get("terrain_on_send", ""))
	if terrain_on != "" and String(field.terrain) != terrain_on:
		log.append(field.set_terrain(terrain_on))
		log.append("%s 的%s展开了%s！" % [me["name"], _ab(me), field.terrain_name(terrain_on)])

	# 数据表里的出场天气（始源之海、终结之地、绯红脉动这类）
	var wsend := String(me_eff.get("weather_on_send", ""))
	if wsend != "" and wsend != "strong_winds" and String(field.weather) != wsend:
		log.append(field.set_weather(wsend))
		log.append("%s 的%s改变了天气！" % [me["name"], _ab(me)])
	# 归零化境：出场把天气清掉
	if bool(me_eff.get("clear_weather_on_send", false)) and String(field.weather) != "":
		log.append(field.set_weather(""))
		log.append("%s 的%s让天气恢复了原状！" % [me["name"], _ab(me)])
	# 气闸 / 无关天气：把天气影响停掉
	if bool(me_eff.get("weather_nullify", false)) and String(field.weather) != "":
		field.weather_turns = 0
		field.weather = ""
		log.append("%s 的%s让天气的影响消失了！" % [me["name"], _ab(me)])
	# 拟态：属性跟着场地走
	if bool(me_eff.get("mimicry", false)) and String(field.terrain) != "":
		var tmap := {"electric": "electric", "grassy": "grass", "misty": "fairy", "psychic": "psychic"}
		var tt := String(tmap.get(String(field.terrain), ""))
		if tt != "":
			me["types"] = [tt]
			log.append("%s 的拟态让它变成了 %s 属性！" % [me["name"], Data.type_name(tt)])
	# 察觉 / 危险预知：出场给个提示
	if bool(me_eff.get("frisk", false)):
		var foe_item := String(foe.get("held", ""))
		log.append("%s 察觉到了 %s 身上的%s。" % [me["name"], foe["name"],
			Data.item_name(foe_item) if foe_item != "" else "没什么道具"])
	if bool(me_eff.get("forewarn", false)):
		log.append("%s 察觉到了 %s 藏着的杀招！" % [me["name"], foe["name"]])
	# 甘露之蜜：出场降对手闪避
	var drop_foe: Dictionary = me_eff.get("on_send_drop_foe", {})
	if not drop_foe.is_empty():
		_apply_stage(foe, String(drop_foe.get("stat", "eva")), -int(drop_foe.get("delta", 1)), log)
	# 看门犬等：出场时自己提升
	if bool(me_eff.get("guard_dog", false)):
		_apply_stage(me, "atk", 1, log)

	if _ab(me) == "威吓":
		if int(foe["stages"]["atk"]) > -6:
			foe["stages"]["atk"] = clampi(int(foe["stages"]["atk"]) - 1, -6, 6)
			log.append("%s 的威吓让 %s 的攻击下降了！" % [me["name"], foe["name"]])

	# 其它出场特性：下载、不挠之剑、不屈之盾
	if bool(me_eff.get("on_send_boost", false)):
		var atk_s := float(me["stats"].get("atk", 0))
		var spa_s := float(me["stats"].get("spa", 0))
		var pick := "atk" if float(foe["stats"].get("def", 0)) <= float(foe["stats"].get("spd", 0)) else "spa"
		if atk_s >= spa_s and pick == "spa":
			pick = "atk"
		elif spa_s > atk_s and pick == "atk":
			pick = "spa"
		_apply_stage(me, pick, 1, log)
		log.append("%s 的下载提升了%s！" % [me["name"], _stat_name(pick)])
	var send_stage: Dictionary = me_eff.get("on_send_stage", {})
	if not send_stage.is_empty():
		var ss := String(send_stage.get("stat", "atk"))
		_apply_stage(me, ss, int(send_stage.get("delta", 1)), log)
	# 踩影一类的束缚
	if bool(me_eff.get("trap_foe", false)):
		foe["trapped"] = true
		log.append("%s 的%s缠住了 %s！" % [me["name"], _ab(me), foe["name"]])
	# 除障：出场清掉自己场地的陷阱
	if bool(me_eff.get("clear_hazards_on_send", false)):
		var hs := _side_of(me)
		var hzd: Dictionary = field.hazards.get(hs, {})
		var any_clear := false
		for k in hzd.keys():
			if typeof(hzd[k]) == TYPE_BOOL:
				if bool(hzd[k]):
					hzd[k] = false
					any_clear = true
			elif int(hzd[k]) > 0:
				hzd[k] = 0
				any_clear = true
		if any_clear:
			log.append("%s 的除障清掉了场地上的陷阱！" % me["name"])
	# 靠特性/携带物在出场时切换形态（鱼群、界限盾壳、达摩模式、太晶变形、ＡＲ系统、面具、阴晴不定）
	_form_switch_on_send_out(me)

## 投球。纯概率，不改血量以外的状态：血越少、捕获率越高、球越好，越容易成。
## 返回值给界面拿去播报：{ok: bool, shakes: int, text: String}
func throw_ball(ball_bonus: float = 1.0, ball_name: String = "精灵球") -> Dictionary:
	if ball_name=="计时球":ball_bonus=minf(4.0,1.0+float(completed_turns)*0.1)
	var target: Dictionary = cur_b()
	var mx := maxi(1, int(target.get("max_hp", 1)))
	var hp := clampi(int(target.get("hp", 0)), 0, mx)
	var sp: Dictionary = Data.species_of(int(target.get("species_id", 1)))
	var rate := float(sp.get("catch_rate", 45))
	rate = preload("res://core/johto_apricorns.gd").adjusted_rate(ball_name,cur_a(),target,sp,rate,fishing_encounter)
	# 血少更好抓；捕获率 45 是「普通」，255 是「几乎必中」
	var hp_factor := (3.0 * mx - 2.0 * hp) / (3.0 * mx)
	var p := clampf((hp_factor * rate / 255.0) * ball_bonus * 1.6, 0.02, 0.96)
	var shakes := 0
	if ball_name == "大师球" or rng.randf() < p:
		shakes = 3
		caught = true
		target.capture_ball = ball_name
		if ball_name=="友友球": target.friendship=200
		caught_species = int(target.get("species_id", 0))
		over = true
		winner = "caught"
		return {"ok": true, "shakes": 3, "text": "太好了！抓到 %s 了！" % String(target.get("name", "?"))}
	shakes = int(clampf(p * 4.0, 0.0, 2.0))
	# 没抓到，对手照打一下
	return {"ok": false, "shakes": shakes, "text": "%s 从%s里跑出来了！" % [String(target.get("name", "?")), ball_name]}

## 逃跑：速度越快越容易跑掉，连续失败会越来越难跑
var escape_tries := 0

func try_flee() -> Dictionary:
	if over:
		return {"ok": false, "text": "战斗已经结束了。"}
	escape_tries += 1
	var my_spe := float(maxi(1, int(cur_a().get("stats", {}).get("spe", 1))))
	var foe_spe := float(maxi(1, int(cur_b().get("stats", {}).get("spe", 1))))
	var chance := my_spe * 128.0 / foe_spe + 30.0 * escape_tries
	if str(cur_a().get("held",""))=="SMOKE_BALL" or my_spe >= foe_spe or rng.randi_range(0, 255) < chance:
		fled = true
		over = true
		winner = "fled"
		return {"ok": true, "text": "成功逃走了！"}
	return {"ok": false, "text": "没能逃掉！"}

func cur_a() -> Dictionary:
	return team_a[active_a]

func cur_b() -> Dictionary:
	return team_b[active_b]

func _stage_mult(stage: int) -> float:
	return STAGE_MULT[clampi(stage + 4, 0, 8)]

## 命中/闪避等级用的表跟能力等级不一样，单独一张
const ACC_MULT := [0.33, 0.375, 0.43, 0.5, 0.6, 0.75, 1.0, 1.33, 1.66, 2.0, 2.33, 2.66, 3.0]

func _acc_mult(stage: int) -> float:
	return ACC_MULT[clampi(stage + 6, 0, 12)]

## 特性名查表：内核按名字判断，换语言不影响
func _ab(c: Dictionary) -> String:
	# 化学变化气体在场时，所有特性失效
	if _gas_active() and String(c.get("ability_name", "")) != "化学变化气体":
		return ""
	return String(c.get("ability_name", ""))

## 场上有没有化学变化气体
func _gas_active() -> bool:
	# 还没开打的时候队伍是空的，别在这儿越界
	if team_a.is_empty() or team_b.is_empty():
		return false
	if active_a >= team_a.size() or active_b >= team_b.size():
		return false
	for c in [cur_a(), cur_b()]:
		if String((c as Dictionary).get("ability_name", "")) == "化学变化气体" \
				and not bool((c as Dictionary).get("fainted", false)):
			return true
	return false

func gravity_on() -> bool:
	return field.gravity_active()

func effectiveness_on(atk_type: String, defender: Dictionary, ignore_ability := false) -> float:
	# 被击落到地面后，飘浮和飞行系的免疫都不算数
	if bool(defender.get("grounded", false)) and atk_type == "ground":
		var t_types: Array = []
		for t in defender["types"]:
			if String(t) != "flying":
				t_types.append(t)
		if t_types.is_empty():
			t_types = ["normal"]
		return effectiveness(atk_type, t_types)
	# 漂浮：地面招式无效（破格类特性可以照打）
	if atk_type == "ground" and (bool(Data.ability_effect(_ab(defender)).get("levitate", false)) \
			or _ab(defender) in ["飘浮", "漂浮"]) and not ignore_ability:
		return 0.0
	return effectiveness(atk_type, defender["types"])

func effectiveness(atk_type: String, def_types: Array) -> float:
	var table: Dictionary = Data.types.get(atk_type, {})
	var mult := 1.0
	for t in def_types:
		mult *= float(table.get(t, 1.0))
	return mult

## 这一只在不在场上（"a" / "b"）
func _side_of(c: Dictionary) -> String:
	if not team_a.is_empty() and team_a[active_a] == c:
		return "a"
	return "b"

## 招式实际威力：变威力招式都收在这里，免得各路 if 散落
func _power_of(attacker: Dictionary, defender: Dictionary, move: Dictionary) -> int:
	var p := int(move.get("power", 0))
	var eff := String(move.get("effect", ""))
	match eff:
		"POWER_BASED_ON_USER_HP", "FLAIL":
			# 抓狂、起死回生：血越少打得越痛（20~120）
			var r1 := float(attacker["hp"]) / float(maxi(1, int(attacker["max_hp"])))
			p = int(20.0 + 100.0 * (1.0 - r1))
		"POWER_BASED_ON_TARGET_HP":
			var r2 := float(defender["hp"]) / float(maxi(1, int(defender["max_hp"])))
			p = int(20.0 + 100.0 * (1.0 - r2))
		"RETURN":
			p = maxi(1, int(attacker.get("friendship", 200)) * 2 / 5)
		"FRUSTRATION":
			p = maxi(1, (255 - int(attacker.get("friendship", 200))) * 2 / 5)
		"HEAT_CRASH":
			# 体重差招式：按自身体重倍率缩放
			p = int(80.0 * float(Data.ability_effect(_ab(attacker)).get("weight_mult", 1.0)))
		"DOUBLE_POWER_ON_ARG_STATUS":
			# 目标中了指定状态时威力翻倍（如毒击对中毒目标）
			var want: Array = (move.get("extra", {}) as Dictionary).get("power_status", [])
			if want.is_empty():
				want = ["psn", "tox", "par", "slp"]
			if want.has(String(defender.get("status", ""))):
				p *= 2
		"STORED_POWER":
			# 蓄能焰袭：能力提升的阶数越多越痛
			var sum := 0
			for k2 in (attacker["stages"] as Dictionary).keys():
				var v2 := int(attacker["stages"][k2])
				if v2 > 0:
					sum += v2
			p = 20 + 20 * sum
		"TRUMP_CARD":
			# 王牌：PP 越少威力越大
			var mine_pp := 0
			var mv_id2 := 0
			for i2 in (attacker["moves"] as Array).size():
				if int(attacker["moves"][i2]) == int(move.get("id", 0)):
					mine_pp = int(attacker["pp"][i2])
					mv_id2 = i2
			p = mini(200, 40 + (5 - mine_pp) * 40) if mv_id2 >= 0 else p
		"TERRAIN_PULSE":
			# 大地波动：按场地改属性并翻倍
			var tmap2 := {"electric": "electric", "grassy": "grass", "misty": "fairy", "psychic": "psychic"}
			if tmap2.has(String(field.terrain)):
				p = int(p * 2.0)
		"WEATHER_BALL":
			var wmap := {"sun": "fire", "rain": "water", "sandstorm": "rock", "snow": "ice"}
			if wmap.has(String(field.weather)):
				p = int(p * 2.0)
		"BOLT_BEAK", "FISHIOUS_REND":
			# 先出手时威力翻倍
			if bool(attacker.get("moved_first", false)):
				p *= 2
		"PAYBACK", "AVALANCHE", "REVENGE":
			# 后出手（或先挨了打）时威力翻倍
			if not bool(attacker.get("moved_first", true)):
				p *= 2
		"BODY_PRESS":
			# 用防御代替攻击
			p = int(p * (float(attacker["stats"].get("def", 1)) / maxf(1.0, float(attacker["stats"].get("atk", 1)))))
		"SHELL_SIDE_ARM":
			# 物理特殊取更高的那一项
			if float(attacker["stats"].get("spa", 0)) > float(attacker["stats"].get("atk", 0)):
				p = int(p * 1.0)
		"ASSURANCE":
			# 本回合已经挨过打就翻倍
			if int(defender.get("hit_this_turn", 0)) > 0:
				p *= 2
		"SYNCHRONOISE":
			# 和自己同属性时威力提升
			if (attacker["types"] as Array).has(String(move.get("type", ""))):
				p = int(p * 1.5)
		"MAGNITUDE":
			var mag := [10, 30, 50, 70, 90, 110, 150]
			p = int(mag[rng.randi_range(0, mag.size() - 1)])
		"FOUL_PLAY":
			# 诈骗：用对手的攻击力来算
			p = int(p * (float(defender["stats"].get("atk", 1)) / maxf(1.0, float(attacker["stats"].get("atk", 1)))))
		"IVY_CUDGEL":
			# 藤蔓鞭击：对手能力越高越痛
			var up_sum := 0
			for kk7 in (defender["stages"] as Dictionary).keys():
				if int(defender["stages"][kk7]) > 0:
					up_sum += int(defender["stages"][kk7])
			p += 20 * up_sum
		"HYDRO_STEAM":
			# 水蒸气：下雨时威力翻倍
			if String(field.weather) == "rain":
				p *= 2
		"LOW_KICK", "GRASS_KNOT":
			# 踢倒：对手越重越痛（没有体重数据，按等级估算）
			p = clampi(20 + int(defender["level"]), 20, 120)
		"ELECTRO_BALL":
			# 电球：自己比对手越快越痛
			var my_sp := float(_speed(attacker))
			var foe_sp := float(maxi(1, _speed(defender)))
			var ratio_sp := my_sp / foe_sp
			if ratio_sp >= 4.0:
				p = 150
			elif ratio_sp >= 3.0:
				p = 120
			elif ratio_sp >= 2.0:
				p = 80
			elif ratio_sp >= 1.0:
				p = 60
			else:
				p = 40
		"GYRO_BALL":
			# 陀螺球：自己越慢越痛
			var g_my := float(_speed(attacker))
			var g_foe := float(maxi(1, _speed(defender)))
			var g_ratio := g_foe / maxf(1.0, g_my)
			p = clampi(int(25.0 * g_ratio), 25, 150)
		"ACROBATICS":
			# 杂技：没带道具时威力翻倍
			if String(attacker.get("held", "")) == "":
				p *= 2
		"FACADE":
			# 硬撑：中了异常状态威力翻倍
			if String(attacker.get("status", "")) != "":
				p *= 2
		"BRINE":
			# 盐水：对手体力不足一半时翻倍
			if int(defender["hp"]) * 2 <= int(defender["max_hp"]):
				p *= 2
		"RETALIATE":
			# 报复：上回合有同伴倒下时翻倍（单打按本回合挨过打算）
			if int(attacker.get("hit_this_turn", 0)) > 0:
				p *= 2
		"LASH_OUT":
			# 泄愤：本回合能力被降过就翻倍
			if bool(attacker.get("stat_dropped", false)):
				p *= 2
		"FURY_CUTTER", "ECHOED_VOICE", "ROUND":
			# 连续使用同一招，威力逐次上升
			var streak := int(attacker.get("streak", 0))
			p = int(p * (1.0 + 0.0 * streak))
			p = p * mini(4, 1 + streak)
		"ROLLOUT":
			# 滚动：连续使用威力翻倍
			var roll := int(attacker.get("rollout", 0))
			p = p * mini(8, 1 << mini(3, roll))
		"FUSION_COMBO", "COLLISION_COURSE", "PHOTON_GEYSER":
			# 合体招式 / 光子喷涌：与自身属性一致时威力提升
			if (attacker["types"] as Array).has(String(move.get("type", ""))):
				p = int(p * 1.5)
		"PSYWAVE":
			# 精神波：按等级随机
			p = 1
		"PRESENT":
			# 礼物：威力随机
			p = [40, 80, 120][rng.randi_range(0, 2)]
		"PUNISHMENT":
			# 惩罚：对手强化越多越痛
			var boost_sum := 0
			for kk5 in (defender["stages"] as Dictionary).keys():
				var vv5 := int(defender["stages"][kk5])
				if vv5 > 0:
					boost_sum += vv5
			p = mini(200, p + 20 * boost_sum)
		"RAGE_FIST":
			# 愤怒之拳：自己掉的血越多越痛
			var lost := int(int(attacker["max_hp"]) - int(attacker["hp"]))
			p = clampi(50 + int(lost / maxi(1, int(attacker["max_hp"])) * 100), 50, 150)
		"LAST_RESPECTS":
			# 拜拜：队伍倒下的越多越痛
			var my_team2: Array = team_a if _side_of(attacker) == "a" else team_b
			var dead2 := 0
			for m5 in my_team2:
				if bool((m5 as Dictionary).get("fainted", false)):
					dead2 += 1
			p = 50 * maxi(1, dead2)
		"HIDDEN_POWER":
			p = 60
		"FICKLE_BEAM":
			p = maxi(p, int(p * rng.randf_range(0.5, 2.0)))
		"TERRAIN_BOOST":
			var terr := String(field.terrain)
			if terr != "" and String(move.get("type", "")) == String({"electric": "electric", "grassy": "grass",
					"misty": "fairy", "psychic": "psychic"}.get(terr, "")):
				p = int(p * 1.5)
		"EARTHQUAKE":
			# 对手在挖洞时威力翻倍
			if bool(defender.get("semi_invuln", false)) and String(defender.get("digging", "") if defender.get("digging") != null else "") != "":
				p *= 2
		"SOLAR_BEAM":
			# 大晴天不用蓄力，其它天气威力减半
			if String(field.weather) in ["rain", "sandstorm", "snow"]:
				p = int(p / 2.0)
	if p <= 0:
		return 0
	return p

## 破格类特性：攻击方无视对方特性
## 灾祸类特性：场上有人带着就把对应能力整体削弱
func _ruin_mult(stat: String) -> float:
	if team_a.is_empty() or team_b.is_empty():
		return 1.0
	var m := 1.0
	for c in [cur_a(), cur_b()]:
		var rs: Dictionary = Data.ability_effect(_ab(c)).get("ruin_stat", {})
		if not rs.is_empty() and String(rs.get("stat", "")) == stat:
			m *= float(rs.get("mult", 0.75))
	return m

## 特性对攻击/特攻等能力值的条件倍率
func _boost_mult(c: Dictionary, stat: String) -> float:
	var ae: Dictionary = Data.ability_effect(_ab(c))
	var m := 1.0
	# 慢启动：上场五回合内攻击减半
	if bool(ae.get("slow_start", false)) and int(c.get("turns_on_field", 0)) < 5 \
			and (stat == "atk" or stat == "spe"):
		m *= 0.5
	# 软弱：血不满一半时攻击与特攻减半
	if bool(ae.get("defeatist", false)) and int(c["hp"]) * 2 < int(c["max_hp"]) \
			and (stat == "atk" or stat == "spa"):
		m *= 0.5
	# 一猩一意：攻击 1.5 倍
	if bool(ae.get("gorilla", false)) and stat == "atk":
		m *= 1.5
	# 大将：每倒一只同伴 +10%
	if bool(ae.get("supreme_overlord", false)):
		var my: Array = team_a if _side_of(c) == "a" else team_b
		var dead := 0
		for m2 in my:
			if bool((m2 as Dictionary).get("fainted", false)):
				dead += 1
		m *= 1.0 + 0.1 * float(maxi(0, dead - 1))
	# 古代活性 / 夸克充能：天气或场地时最高能力 1.3 倍
	if bool(ae.get("sun_boost", false)) and String(field.weather) == "sun":
		m *= 1.3
	if bool(ae.get("terrain_boost", false)) and String(field.terrain) == "electric":
		m *= 1.3
	return m

## 这一下算不算接触（远隔、电气浮游这类不接触）
func _is_contact(attacker: Dictionary, move: Dictionary) -> bool:
	if bool(Data.ability_effect(_ab(attacker)).get("no_contact", false)):
		return false
	return bool((move.get("flags", {}) as Dictionary).get("contact", false))

func _ignores_ability(attacker: Dictionary) -> bool:
	if bool(Data.ability_effect(_ab(attacker)).get("ignore_ability_foe", false)):
		return true
	return _ab(attacker) in ["破格", "涡轮火焰", "涡轮火花", "兆级电压"]

func damage(attacker: Dictionary, defender: Dictionary, move: Dictionary) -> int:
	# 皮肤类特性：招式属性被改写（一般皮肤之外还会略微增强）
	var skin := String(Data.ability_effect(_ab(attacker)).get("skin_type", ""))
	var skin_boost := 1.0
	if skin != "" and int(move.get("power", 0)) > 0 and String(move.get("type", "")) != skin:
		var mvc: Dictionary = (move as Dictionary).duplicate(true)
		mvc["type"] = skin
		move = mvc
		if skin != "normal":
			skin_boost = 1.2
	var power := _power_of(attacker, defender, move)
	if power <= 0:
		return 0

	var cat := String(move.get("category", "physical"))
	var atk_stat := "atk" if cat == "physical" else "spa"
	var def_stat := "def" if cat == "physical" else "spd"
	# 精神冲击、神秘之剑：按物理结算，但看特攻、比物理防御
	if String(move.get("effect", "")) == "PSYSHOCK":
		atk_stat = "spa"

	var atk_stage := int(attacker["stages"][atk_stat])
	# 对手有纯朴时，自己的强化对它不起作用
	if bool(Data.ability_effect(_ab(defender)).get("ignore_stages", false)):
		atk_stage = 0
	var a: float = attacker["stats"][atk_stat] * _stage_mult(atk_stage) * _boost_mult(attacker, atk_stat)
	a *= _ruin_mult(atk_stat)
	# 特性对能力值本身的修正
	var ae0: Dictionary = Data.ability_effect(_ab(attacker))
	var sm: Dictionary = ae0.get("stat_mult", {})
	if sm.has(atk_stat):
		a *= float(sm[atk_stat])
	var sb: Dictionary = ae0.get("status_boost", {})
	if String(sb.get("stat", "")) == atk_stat and (sb.get("status", []) as Array).has(String(attacker.get("status", ""))):
		a *= float(sb.get("mult", 1.5))
	var ws: Dictionary = ae0.get("weather_stat", {})
	if ws.has(String(field.weather)):
		var wd0: Dictionary = ws[String(field.weather)]
		if String(wd0.get("stat", "")) == atk_stat:
			a *= float(wd0.get("mult", 1.5))
	# 灼伤让物理攻击减半
	if String(attacker.get("status", "")) == "brn" and cat == "physical":
		a *= 0.5
	var d: float = defender["stats"][def_stat] * _stage_mult(defender["stages"][def_stat]) * _ruin_mult(def_stat)
	if d <= 0:
		d = 1.0

	var lvl := float(attacker["level"])
	var base := ((2.0 * lvl / 5.0 + 2.0) * power * a / d) / 50.0 + 2.0

	# 本系加成：太晶化后打太晶属性是 2 倍，跟原属性一致也吃 2 倍
	var mtype := String(move.get("type", "normal"))
	var stab := 1.5 if attacker["types"].has(mtype) else 1.0
	# 适应力：本系加成抬到 2 倍
	var atk_eff: Dictionary = Data.ability_effect(_ab(attacker))
	var def_eff: Dictionary = Data.ability_effect(_ab(defender))
	if atk_eff.has("stab"):
		stab = maxf(stab, float(atk_eff["stab"]))
	if bool(attacker.get("tera_active", false)) and mtype == String(attacker.get("tera_type", "")):
		stab = 2.0
	# 属性克制（重力期间地面招式能打到飞行系）
	var ign := _ignores_ability(attacker) or bool(attacker.get("ignore_ability", false))
	var eff := 0.0
	if gravity_on() and mtype == "ground":
		# 重力期间飞行系与漂浮也踩在地上，地面招式照打
		eff = effectiveness("ground", defender["types"])
		if eff == 0.0:
			eff = 1.0
	else:
		eff = effectiveness_on(mtype, defender, ign)
	if eff == 0.0 and bool(atk_eff.get("scrappy", false)) and (mtype == "normal" or mtype == "fighting"):
		eff = 1.0
	if eff == 0.0:
		return 0
	# 随机浮动 0.85 ~ 1.0
	var roll := rng.randf_range(0.85, 1.0)
	# 必中必会心的招式（狙击、激光聚焦）
	var eff_now := String(move.get("effect", ""))
	if eff_now == "SNIPE_SHOT" or bool(attacker.get("laser_focus", false)):
		last_crit = true
	# 会心一击：1/16，1.5 倍；会心一击专属招式把它提到 1/2
	var crit_chance := 0.0625
	var cs := int(attacker.get("crit_stage", 0)) + int(atk_eff.get("crit_stage", 0))
	if str(attacker.get("held", "")) == "LUCKY_PUNCH" and int(attacker.get("species_id", 0)) == 113:
		cs += 2
	if bool(attacker.get("dire_hit", false)): cs += 2
	if cs > 0:
		crit_chance = [0.0625, 0.125, 0.25, 0.33, 0.5][mini(cs, 4)]
	if int(attacker.get("crit_up", 0)) > 0:
		crit_chance = 0.5
	var crit := 1.0
	var force_crit := bool(atk_eff.get("crit_on_status", false)) and String(defender.get("status", "")) != ""
	if not bool(def_eff.get("no_crit_taken", false)) and (force_crit or rng.randf() < crit_chance):
		crit = 1.5
		if atk_eff.has("crit_mult"):
			crit = float(atk_eff["crit_mult"])
		last_crit = true
	else:
		last_crit = false

	# 特性：硬爪（接触招式威力 1.3）、威力档位（技术高手）、属性与天气加成、满血减伤（多重鳞片）
	if float(atk_eff.get("contact_power", 0.0)) != 0.0:
		if _is_contact(attacker, move):
			base *= float(atk_eff["contact_power"])
	if atk_eff.has("weak_power") and power <= int(atk_eff["weak_power"]):
		base *= float(atk_eff.get("mult", 1.5))
	var tb: Dictionary = atk_eff.get("type_boost", {})
	if tb.has(mtype):
		base *= float(tb[mtype])
	var wb: Dictionary = atk_eff.get("weather_type_boost", {})
	if not wb.is_empty() and wb.has(String(field.weather)):
		var wd: Dictionary = wb[String(field.weather)]
		if (wd.get("types", []) as Array).has(mtype):
			base *= float(wd.get("mult", 1.3))
	# 属性吸收：这类特性让该属性招式完全打不进来，还回血或升能力
	var absorb: Dictionary = def_eff.get("absorb", {})
	if not ign and String(absorb.get("type", "")) == mtype:
		var heal_amt: int = int(int(defender["max_hp"]) * float(absorb.get("heal", 0.0)))
		if heal_amt > 0 and int(defender["hp"]) < int(defender["max_hp"]):
			var before_hp := int(defender["hp"])
			_set_hp(defender, mini(int(defender["max_hp"]), int(defender["hp"]) + heal_amt))
			log.append("%s 的%s吸收了招式，回复了 %d 点体力。" % [defender["name"], _ab(defender), int(defender["hp"]) - before_hp])
		else:
			log.append("%s 的%s让招式失效了！" % [defender["name"], _ab(defender)])
		var bt: Dictionary = absorb.get("boost", {})
		if not bt.is_empty():
			var bstat := String(bt.get("stat", "spa"))
			var bd := int(bt.get("delta", 1))
			var c0 := int(defender["stages"].get(bstat, 0))
			if c0 < 6:
				defender["stages"][bstat] = clampi(c0 + bd, -6, 6)
				log.append("%s 的%s上升了！" % [defender["name"], _stat_name(bstat)])
		return 0
	# 分析：后出手时威力 1.3 倍
	if bool(atk_eff.get("analyze", false)) and not bool(attacker.get("moved_first", true)):
		base *= 1.3
	# 蹲守：对手刚换上场的回合伤害翻倍
	if bool(atk_eff.get("stakeout", false)) and bool(defender.get("just_switched", false)):
		base *= 2.0
	# 舍身：反作用力招式威力 1.2 倍
	if bool(atk_eff.get("reckless", false)) and String(move.get("effect", "")) == "RECOIL":
		base *= 1.2
	# 脑核之力：效果拔群时再乘 1.3
	if float(atk_eff.get("super_effective_boost", 0.0)) != 0.0 and eff > 1.0:
		base *= float(atk_eff["super_effective_boost"])
	if skin_boost != 1.0:
		base *= skin_boost
	# 强行：招式威力 1.3 倍（附加效果不再发动）
	if bool(atk_eff.get("sheer_force", false)) and (move.get("extra", {}) as Dictionary).size() > 0:
		base *= 1.3
	# 拳类 / 啃咬类 / 切割类招式加成
	var fp: Dictionary = atk_eff.get("flag_power", {})
	if not fp.is_empty() and bool((move.get("flags", {}) as Dictionary).get(String(fp.get("flag", "")), false)):
		base *= float(fp.get("mult", 1.2))
	# 体力不足时属性招式变强（茂盛/猛火/激流/虫之预感）
	var pb: Dictionary = atk_eff.get("pinch_boost", {})
	if not pb.is_empty():
		var ratio := float(int(attacker["hp"])) / float(maxi(1, int(attacker["max_hp"])))
		if ratio <= float(pb.get("hp", 0.34)) and (pb.get("types", []) as Array).has(mtype):
			base *= float(pb.get("mult", 1.5))
	# 有色眼镜：效果不好时翻倍
	if float(atk_eff.get("tinted_lens", 0.0)) != 0.0 and eff < 1.0:
		base *= float(atk_eff["tinted_lens"])
	if bool(def_eff.get("full_hp_halve", false)) and int(defender["hp"]) >= int(defender["max_hp"]):
		base *= 0.5
	# 物理 / 特殊伤害减半（毛皮大衣、冰鳞粉）
	if bool(def_eff.get("halve_physical", false)) and cat == "physical":
		base *= 0.5
	if bool(def_eff.get("halve_special", false)) and cat == "special":
		base *= 0.5
	# 耐性类特性：按招式属性减免
	var dt: Dictionary = def_eff.get("damage_taken", {})
	if dt.has(mtype):
		base *= float(dt[mtype])
	# 神奇守护：只有效果拔群才打得进去
	if bool(def_eff.get("wonder_guard", false)) and eff <= 1.0:
		return 0
	# 过滤：效果拔群的招式伤害打七五折
	if float(def_eff.get("super_effective_reduce", 0.0)) != 0.0 and eff > 1.0:
		base *= float(def_eff["super_effective_reduce"])

	# 携带道具：讲究头带/眼镜、生命宝珠、突击背心（笨拙时全部失效）
	var klutz := bool(atk_eff.get("ignore_own_item", false))
	match "" if klutz else String(attacker.get("held", "")):
		"CHARCOAL":
			if mtype == "fire": base *= 1.1
		"CHOICE_BAND":
			if cat == "physical":
				base *= 1.5
		"SOUL_DEW":
			if cat=="special" and int(attacker.species_id) in [380,381]:base*=1.5
		"CHOICE_SPECS":
			if cat == "special":
				base *= 1.5
		"LIFE_ORB":
			base *= 1.3
	if defender.get("held","")=="SOUL_DEW" and int(defender.species_id) in [380,381] and cat=="special" and not def_eff.get("ignore_own_item",false):base/=1.5
	if String(defender.get("held", "")) == "ASSAULT_VEST" and cat == "special":
		base *= 0.667

	var held := str(attacker.get("held", ""))
	var held_info: Dictionary = Data.held_items.get(held,{})
	var type_bonus := 1.1 if not klutz and held_info.get("type_boost","") == mtype else 1.0
	if (held == "NEVER_MELT_ICE" and mtype == "ice") or (held == "SILK_SCARF" and mtype == "normal") or (held == "BLACK_GLASSES" and mtype == "dark"):
		type_bonus = 1.1
	elif held == "SEA_INCENSE" and mtype == "water":
		type_bonus = 1.05
	var dmg := int(base * stab * eff * roll * crit * type_bonus)
	# 天气 / 场地 / 屏障
	var mod: float = float(field.damage_mod(mtype, cat, _side_of(attacker), _side_of(defender)))
	dmg = int(dmg * mod)
	# 超极巨极光旋律：几回合内受到伤害减半
	if int(defender.get("shield_turns", 0)) > 0:
		dmg = int(dmg / 2.0)
	# 抗性果：体力已过半时被克制的那个属性打中，伤害减半
	var bd: Dictionary = Data.berry_def(String(defender.get("berry", "")))
	if String(bd.get("kind", "")) == "resist" and String(bd.get("type", "")) == mtype \
			and int(defender["hp"]) * 2 <= int(defender["max_hp"]):
		dmg = maxi(1, int(dmg / 2.0))
		defender["berry"] = ""
		last_berry = String(bd.get("name", ""))
	return maxi(1, dmg)

## 招式打完之后的效果：状态、能力升降、回复、反伤、一击必杀这些
func _apply_effect(attacker: Dictionary, defender: Dictionary, move: Dictionary, dealt: int = 0) -> String:
	var effect := String(move.get("effect", ""))
	var extra: Dictionary = move.get("extra", {})
	var out: Array = []

	# 反伤
	if effect == "RECOIL" and dealt > 0 and not bool(Data.ability_effect(_ab(attacker)).get("no_recoil", false)):
		var back: int = maxi(1, int(dealt / 3.0))
		_set_hp(attacker, maxi(0, int(attacker["hp"]) - back))
		out.append("%s 受到了 %d 点反作用力伤害。" % [attacker["name"], back])

	# 回复类
	if effect in ["RESTORE_HP", "SOFTBOILED", "HEAL_HALF"]:
		if int(attacker.get("heal_block", 0)) > 0:
			out.append("%s 被封锁了回复，没有效果。" % attacker["name"])
		elif int(attacker["hp"]) >= int(attacker["max_hp"]):
			out.append("但是没有效果……")
		else:
			var heal: int = int(attacker["max_hp"] / 2)
			var before: int = attacker["hp"]
			_set_hp(attacker, mini(attacker["max_hp"], int(attacker["hp"]) + heal))
			out.append("%s 回复了 %d 点体力。" % [attacker["name"], int(attacker["hp"]) - before])

	# 强行：带了附加效果的招式虽然更痛，但附加效果不再发动
	if bool(Data.ability_effect(_ab(attacker)).get("sheer_force", false)) and not extra.is_empty():
		extra = {}
	# 鳞粉：附加效果一律无效
	if bool(Data.ability_effect(_ab(defender)).get("no_secondary", false)):
		extra = {}

	# 替身挡着的时候，异常状态与降能力都伤不到本体
	var sub_guard := int(defender.get("sub_hp", 0)) > 0
	if sub_guard and (extra.has("status") or (extra.has("stat") and int(extra.get("delta", 0)) < 0)):
		out.append("%s 的替身挡下了效果。" % defender["name"])
		extra = {}

	# 魔法镜：把对手的变化招式弹回给使用者
	if (extra.has("status") or extra.has("stat")) and String(move.get("category", "")) == "status" \
			and bool(Data.ability_effect(_ab(defender)).get("reflect_status", false)):
		out.append("%s 的%s把变化招式弹了回来！" % [defender["name"], _ab(defender)])
		var swap := attacker
		attacker = defender
		defender = swap

	# 附加状态：按概率上
	if extra.has("status"):
		var st := String(extra["status"])
		var chance := _effect_chance(attacker, int(extra.get("chance", 100)))
		if rng.randi_range(1, 100) <= chance:
			if String(defender.get("status", "")) != "":
				out.append("%s 已经中了状态，没有效果。" % defender["name"])
			elif bool(Data.ability_effect(_ab(attacker)).get("corrode", false)) and (st == "psn" or st == "tox") \
					or not _status_immune(st, String(defender["types"][0] if not defender["types"].is_empty() else ""),
						defender["types"], _ab(defender)):
				defender["status"] = st
				defender["status_turns"] = rng.randi_range(1, 3) if st == "slp" else 0
				# 同步：把状态原样弹回给出手的人
				if bool(Data.ability_effect(_ab(defender)).get("status_reflect", false)) \
						and String(attacker.get("status", "")) == "" and st != "cfu" and st != "inf":
					attacker["status"] = st
					attacker["status_turns"] = int(defender["status_turns"])
					out.append("%s 的同步把%s也传染给了 %s！" % [defender["name"],
						_status_name(st), attacker["name"]])
				if st == "slp" and bool(Data.ability_effect(_ab(defender)).get("sleep_half", false)):
					defender["status_turns"] = maxi(1, int(int(defender["status_turns"]) / 2.0))
				out.append(_status_text(String(defender["name"]), st))
			else:
				out.append("对 %s 没有效果……" % defender["name"])

	# 能力升降
	if extra.has("stat"):
		var st2 := String(extra["stat"])
		var delta := int(extra.get("delta", 0))
		var chance2 := _effect_chance(attacker, int(extra.get("chance", 100)))
		var target: Dictionary = defender if delta < 0 else attacker
		if rng.randi_range(1, 100) <= chance2:
			var blocked_mist := delta < 0 and bool(target.get("mist", false))
			if blocked_mist:
				out.append("%s 被白雾保护，能力没有下降。" % target["name"])
			else:
				_apply_stage(target, st2, delta, out)

	# 超极巨专属招式的额外机制
	if bool(extra.get("flinch", false)) and not bool(defender["fainted"]):
		if rng.randi_range(1, 100) <= _effect_chance(attacker, int(extra.get("chance", 100))):
			defender["flinch"] = true
			out.append("%s 畏缩了！" % defender["name"])
			var ofb: Dictionary = Data.ability_effect(_ab(defender)).get("on_flinch_boost", {})
			if not ofb.is_empty():
				_apply_stage(defender, String(ofb.get("stat", "spe")), int(ofb.get("delta", 1)), out)

	var ge: Dictionary = move.get("gmax_effect", {})
	if not ge.is_empty():
		var gtxt := _gmax_effect(attacker, defender, ge, dealt)
		if gtxt != "":
			out.append(gtxt)

	# 一击必杀
	if effect == "OHKO":
		if int(defender["level"]) <= int(attacker["level"]):
			_set_hp(defender, 0)
			defender["fainted"] = true
			out.append("一击命中！%s 倒下了！" % defender["name"])
		else:
			out.append("但是没有命中……")

	# 固定伤害（地球上投/龙之怒这类）
	if effect == "LEVEL_DAMAGE":
		var dmg: int = int(attacker["level"])
		_set_hp(defender, maxi(0, int(defender["hp"]) - dmg))
		out.append("对 %s 造成了 %d 点伤害。" % [defender["name"], dmg])
		if int(defender["hp"]) <= 0:
			defender["fainted"] = true
			out.append("%s 倒下了！" % defender["name"])
	if effect in ["FIXED_PERCENT_DAMAGE", "SUPER_FANG"]:
		var half: int = maxi(1, int(int(defender["hp"]) / 2.0))
		_set_hp(defender, maxi(0, int(defender["hp"]) - half))
		out.append("对 %s 造成了 %d 点伤害。" % [defender["name"], half])
		if int(defender["hp"]) <= 0:
			defender["fainted"] = true
			out.append("%s 倒下了！" % defender["name"])

	# 混乱：真的让对手有概率打自己
	if effect == "CONFUSE" or (effect == "SWAGGER" and not bool(defender["fainted"])):
		if int(defender.get("sub_hp", 0)) > 0:
			out.append("%s 的替身挡下了混乱。" % defender["name"])
		elif String(defender.get("status", "")) == "":
			defender["status"] = "cfu"
			defender["status_turns"] = rng.randi_range(2, 4)
			out.append("%s 陷入了混乱！" % defender["name"])
		else:
			out.append("但是没有效果……")

	# 浸水 / 第三属性 / 按携带物改属性
	if effect == "THIRD_TYPE" and not bool(defender["fainted"]):
		var add_t := String(extra.get("type", "normal"))
		var tl: Array = defender["types"]
		if not tl.has(add_t):
			tl.append(add_t)
			out.append("%s 增加了 %s 属性！" % [defender["name"], Data.type_name(add_t)])

	# 自然之力：按场地换成不同招式
	if effect == "NATURE_POWER":
		var np_map := {"electric": "十万伏特", "grassy": "能量球", "misty": "月亮之力", "psychic": "精神强念"}
		out.append("%s 借由自然之力使出了%s！" % [attacker["name"], String(np_map.get(String(field.terrain), "地震"))])

	# 拍落 / 毒丝 / 沥青射击：降速度
	if effect in ["TOXIC_THREAD", "TAR_SHOT"]:
		_apply_stage(defender, "spe", -1, out)

	# 清雾：清掉撒菱并降低对手闪避
	if effect == "DEFOG":
		var hz3: Dictionary = field.hazards.get(_side_of(defender), {})
		for k5 in hz3.keys():
			if typeof(hz3[k5]) == TYPE_BOOL:
				hz3[k5] = false
			else:
				hz3[k5] = 0
		_apply_stage(defender, "eva", -1, out)
		out.append("雾气散去了！")

	# 奇迹空间：交换防御与特防
	if effect == "WONDER_ROOM":
		for m3 in [attacker, defender]:
			var d1 := int((m3 as Dictionary)["stats"].get("def", 1))
			var d2 := int((m3 as Dictionary)["stats"].get("spd", 1))
			(m3 as Dictionary)["stats"]["def"] = d2
			(m3 as Dictionary)["stats"]["spd"] = d1
		out.append("奇迹空间展开了，防御与特防被交换！")

	# 电磁浮游：对手浮起来，容易被打中
	if effect == "TELEKINESIS" and not bool(defender["fainted"]):
		defender["telekinesis"] = 3
		out.append("%s 浮在了空中！" % defender["name"])

	# 猛撞 / 舍身冲撞这类：反伤一半
	if effect == "MAX_HP_50_RECOIL" and dealt > 0:
		var half2: int = maxi(1, int(int(attacker["max_hp"]) / 2.0))
		_set_hp(attacker, maxi(0, int(attacker["hp"]) - half2))
		out.append("%s 受到了 %d 点反作用力伤害。" % [attacker["name"], half2])
		if int(attacker["hp"]) <= 0:
			attacker["fainted"] = true
			out.append("%s 倒下了！" % attacker["name"])

	# 羽栖：回一半体力并暂时失去飞行属性
	if effect == "ROOST":
		var rh: int = maxi(1, int(int(attacker["max_hp"]) / 2.0))
		_set_hp(attacker, mini(int(attacker["max_hp"]), int(attacker["hp"]) + rh))
		attacker["roosting"] = true
		out.append("%s 落在地上休息，回复了体力。" % attacker["name"])

	# 生蛋 / 喝牛奶：回一半
	if effect in ["MILK_DRINK", "SHORE_UP", "FLORAL_HEALING", "LIFE_DEW"]:
		var heal3: int = maxi(1, int(int(attacker["max_hp"]) / 2.0))
		if effect == "SHORE_UP" and String(field.weather) == "sandstorm":
			heal3 = int(int(attacker["max_hp"]) * 0.66)
		_set_hp(attacker, mini(int(attacker["max_hp"]), int(attacker["hp"]) + heal3))
		out.append("%s 回复了体力。" % attacker["name"])

	# 花粉团：对对手造成伤害，对自己人回血（这里按对手处理）
	if effect == "POLLEN_PUFF" and not bool(defender["fainted"]):
		out.append("花粉团炸开了！")

	# 睡觉时也能用的招式
	if effect in ["SLEEP_TALK", "SNORE"]:
		out.append("%s 在梦里使出了招式！" % attacker["name"])

	# 击落：把对手打落到地面
	if effect == "SMACK_DOWN" and not bool(defender["fainted"]):
		defender["grounded"] = true
		out.append("%s 被击落到了地面！" % defender["name"])

	# 点到为止：留 1 点体力
	if effect == "FALSE_SWIPE" and int(defender["hp"]) <= 0:
		_set_hp(defender, 1)
		defender["fainted"] = false
		out.append("%s 撑住了，还剩 1 点体力！" % defender["name"])

	# 吹飞 / 吼叫：把对手赶下场（野生对战直接结束）
	if effect == "ROAR":
		if bool(Data.ability_effect(_ab(defender)).get("no_forced_switch", false)) \
				or bool(Data.ability_effect(_ab(defender)).get("guard_dog", false)):
			out.append("%s 的%s让它纹丝不动！" % [defender["name"], _ab(defender)])
			return "\n".join(out)
		var foe_side := _side_of(defender)
		var foe_team: Array = team_a if foe_side == "a" else team_b
		var nxt2 := _next_alive(foe_side, active_a if foe_side == "a" else active_b)
		if nxt2 < 0:
			out.append("但是没有可以换上来的宝可梦。")
		else:
			_do_switch(foe_side, nxt2, true)
			out.append("%s 被赶下场了！" % defender["name"])

	# 抢夺对手的携带物
	if effect == "STEAL_ITEM" and not bool(defender["fainted"]):
		var got := String(defender.get("held", ""))
		if got != "" and bool(Data.ability_effect(_ab(defender)).get("prevent_steal", false)):
			out.append("%s 的%s粘得太牢，抢不走。" % [defender["name"], _ab(defender)])
			got = ""
		if got == "":
			out.append("%s 身上没有可抢的东西。" % defender["name"])
		else:
			defender["held"] = ""
			attacker["held"] = got
			out.append("%s 抢走了 %s！" % [attacker["name"], Data.item_name(got)])

	# 急速折返、伏特替换和快速折返在命中后让同队伙伴上场。
	if effect == "HIT_ESCAPE" and not attacker.get("fainted",false) and not over:
		var own_side := _side_of(attacker)
		var reserve := _next_alive(own_side,active_a if own_side=="a" else active_b)
		if reserve>=0:
			_do_switch(own_side,reserve,true)
			out.append("%s 回到了训练家身边！" % attacker.name)

	# 束缚：对手换不下去
	if effect in ["MEAN_LOOK", "FAIRY_LOCK", "OCTOLOCK"] and not bool(defender["fainted"]):
		defender["trapped"] = true
		out.append("%s 被束缚住了，换不了人！" % defender["name"])

	# 治愈铃声：全队解除异常状态
	if effect == "HEAL_BELL":
		var my_team: Array = team_a if _side_of(attacker) == "a" else team_b
		var cured := 0
		for m in my_team:
			if String((m as Dictionary).get("status", "")) != "":
				(m as Dictionary)["status"] = ""
				(m as Dictionary)["status_turns"] = 0
				cured += 1
		out.append("治愈铃声响起，解除了 %d 只的异常状态。" % cured)

	# 高速旋转 / 冰旋：清掉自己这边的撒菱与屏障外的干扰
	if effect in ["RAPID_SPIN", "ICE_SPINNER"]:
		var my_side := _side_of(attacker)
		var hz: Dictionary = field.hazards.get(my_side, {})
		var cleared := false
		for k in hz.keys():
			if k == "stealth_rock" or k == "steel_rocks" or k == "sticky_web":
				if bool(hz[k]):
					hz[k] = false
					cleared = true
			elif int(hz.get(k, 0)) > 0:
				hz[k] = 0
				cleared = true
		if cleared:
			out.append("%s 把场地上的陷阱清干净了！" % attacker["name"])
		if effect == "RAPID_SPIN":
			var sp_up := int(attacker["stages"].get("spe", 0))
			if sp_up < 6:
				attacker["stages"]["spe"] = sp_up + 1
				out.append("%s 的速度上升了！" % attacker["name"])

	# 预知未来：两回合后落下
	if effect == "FUTURE_SIGHT":
		attacker["future"] = {"turns": 3, "damage": maxi(1, dealt if dealt > 0 else int(attacker["stats"].get("spa", 20)) * 2)}
		out.append("%s 预见了未来的攻击！" % attacker["name"])

	# 锁定：下一次一定命中
	if effect == "LOCK_ON":
		attacker["lock_on"] = true
		out.append("%s 锁定了 %s！" % [attacker["name"], defender["name"]])

	# 识破：无视对方的属性免疫
	if effect == "FORESIGHT":
		defender["identified"] = true
		out.append("%s 被识破了！" % defender["name"])

	# 挺住：这一回合不会倒下
	if effect == "ENDURE":
		attacker["endure"] = true
		out.append("%s 摆出了挺住的架势！" % attacker["name"])

	# 同命：一起倒下
	if effect == "DESTINY_BOND":
		attacker["destiny_bond"] = true
		out.append("%s 拉上了对手一起上路！" % attacker["name"])

	# 灭亡之歌：三回合后倒下
	if effect == "PERISH_SONG":
		for m in [attacker, defender]:
			if int(m.get("perish", 0)) <= 0:
				m["perish"] = 4
		out.append("灭亡之歌响起了！双方都开始倒数。")

	# 怨恨：扣掉对手刚用过招式的 PP
	if effect == "GRUDGE":
		var last_id := int(defender.get("last_move", 0))
		if last_id > 0:
			out.append("%s 的怨念缠住了 %s。" % [attacker["name"], defender["name"]])

	# 恨意 / 恨：扣对手 4 点 PP
	if effect == "SPITE":
		var mv_list: Array = defender["moves"]
		var pp_list: Array = defender["pp"]
		for i3 in mv_list.size():
			if int(pp_list[i3]) > 0:
				pp_list[i3] = maxi(0, int(pp_list[i3]) - 4)
				out.append("%s 的 %s PP 被削减了！" % [defender["name"], String((Data.move_of(int(mv_list[i3])) as Dictionary).get("name", "招式"))])
				break

	# 恶梦：睡着的每回合掉 1/4
	if effect == "NIGHTMARE":
		if String(defender.get("status", "")) == "slp":
			defender["nightmare"] = true
			out.append("%s 被恶梦缠住了！" % defender["name"])
		else:
			out.append("但是没有效果……")

	# 诅咒：每回合掉 1/4，对手的物理伤害变高（简化成持续伤害）
	if effect == "CURSE":
		defender["cursed"] = true
		out.append("%s 被诅咒了！" % defender["name"])

	# 寄生种子：每回合被吸 1/8
	if effect == "LEECH_SEED":
		if (defender["types"] as Array).has("grass"):
			out.append("对草属性没有效果……")
		else:
			defender["leech_seed"] = true
			out.append("%s 被种下了寄生种子！" % defender["name"])

	# 挑衅 / 再来一次 / 定身法
	if effect == "TAUNT":
		defender["taunt"] = 3
		out.append("%s 被挑衅了，不能再用变化招式！" % defender["name"])
	if effect == "ENCORE":
		defender["encore"] = 3
		out.append("%s 被要求再来一次！" % defender["name"])
	if effect == "DISABLE":
		defender["disabled"] = {"move": int(defender.get("last_move", 0)), "turns": 4}
		out.append("%s 的招式被封印了！" % defender["name"])

	# 黑雾：所有能力变化清空
	if effect == "HAZE":
		for m in [attacker, defender]:
			for k in (m["stages"] as Dictionary).keys():
				m["stages"][k] = 0
		out.append("黑雾弥漫，所有能力变化都复原了。")

	# 白雾：自己这边不被降能力
	if effect == "MIST":
		attacker["mist"] = true
		out.append("%s 被白雾保护了！" % attacker["name"])

	# 腹鼓：掉一半血，攻击拉满
	if effect == "BELLY_DRUM":
		var cost2: int = maxi(1, int(int(attacker["max_hp"]) / 2))
		if int(attacker["hp"]) <= cost2:
			out.append("体力不够，腹鼓失败了。")
		else:
			_set_hp(attacker, int(attacker["hp"]) - cost2)
			attacker["stages"]["atk"] = 6
			out.append("%s 敲响腹鼓，攻击提升到最大！" % attacker["name"])

	# 破壳：防御特防下降，攻击特攻速度上升
	if effect == "SHELL_TRAP":
		attacker["stages"]["def"] = clampi(int(attacker["stages"]["def"]) - 1, -6, 6)
		attacker["stages"]["spd"] = clampi(int(attacker["stages"]["spd"]) - 1, -6, 6)
		out.append("%s 的防御和特防下降了。" % attacker["name"])

	# 着迷：对手有概率不动
	if effect == "ATTRACT":
		defender["attract"] = true
		out.append("%s 着迷了！" % defender["name"])

	# 回复封锁：几回合内不能回血
	if effect == "HEAL_BLOCK":
		defender["heal_block"] = 3
		out.append("%s 暂时无法回复体力了！" % defender["name"])

	# 痛平分：把双方体力拉平均
	if effect == "PAIN_SPLIT":
		var total := int(attacker["hp"]) + int(defender["hp"])
		var avg := int(total / 2)
		_set_hp(attacker, mini(int(attacker["max_hp"]), avg))
		_set_hp(defender, mini(int(defender["max_hp"]), avg))
		out.append("双方的体力被平分了。")

	# 击退类（龙尾）：打完把对手换下去
	if effect == "HIT_SWITCH_TARGET" and not bool(defender["fainted"]):
		var fs := _side_of(defender)
		var nt := _next_alive(fs, active_a if fs == "a" else active_b)
		if nt >= 0:
			_do_switch(fs, nt, true)
			out.append("%s 被击退了！" % defender["name"])

	# 颠倒：把能力变化倒过来
	if effect == "TOPSY_TURVY" and not bool(defender["fainted"]):
		for k3 in (defender["stages"] as Dictionary).keys():
			defender["stages"][k3] = clampi(-int(defender["stages"][k3]), -6, 6)
		out.append("%s 的能力变化被颠倒了过来！" % defender["name"])

	# 清理：清掉自己场地的陷阱并提升速度
	if effect == "TIDY_UP":
		var hz2: Dictionary = field.hazards.get(_side_of(attacker), {})
		for k4 in hz2.keys():
			if typeof(hz2[k4]) == TYPE_BOOL:
				hz2[k4] = false
			else:
				hz2[k4] = 0
		_apply_stage(attacker, "spe", 1, out)
		out.append("%s 把场地收拾干净了！" % attacker["name"])

	# 哈欠：让对手下一回合睡过去
	if effect == "YAWN" and String(defender.get("status", "")) == "":
		defender["yawn"] = 2
		out.append("%s 打了个哈欠，快要睡着了……" % defender["name"])

	# 吸取力量：按对手攻击力回复
	if effect == "STRENGTH_SAP" and not bool(defender["fainted"]):
		var sap: int = maxi(1, int(defender["stats"].get("atk", 20)))
		var gain: int = mini(int(attacker["max_hp"]) - int(attacker["hp"]), sap)
		_set_hp(attacker, mini(int(attacker["max_hp"]), int(attacker["hp"]) + gain))
		_apply_stage(defender, "atk", -1, out)
		out.append("%s 吸取了 %d 点力量。" % [attacker["name"], gain])

	# 丛林治疗：回复自己并铺开青草场地
	if effect == "JUNGLE_HEALING":
		var jh: int = maxi(1, int(int(attacker["max_hp"]) / 2.0))
		_set_hp(attacker, mini(int(attacker["max_hp"]), int(attacker["hp"]) + jh))
		out.append(field.set_terrain("grassy"))
		out.append("%s 借助丛林的治疗回复了体力。" % attacker["name"])

	# 顺风：己方速度在四回合内翻倍
	if effect == "TAILWIND":
		field.set_screen(_side_of(attacker), "tailwind")
		out.append("%s 这边刮起了顺风！" % attacker["name"])

	# 撒菱 / 毒菱 / 黏黏网
	if effect == "SPIKES":
		field.add_hazard("b" if _side_of(attacker) == "a" else "a", "spikes")
		out.append("对手的场地撒满了菱！")
	if effect == "TOXIC_SPIKES":
		field.add_hazard("b" if _side_of(attacker) == "a" else "a", "toxic_spikes")
		out.append("对手的场地撒下了毒菱！")
	if effect == "STICKY_WEB":
		field.add_hazard("b" if _side_of(attacker) == "a" else "a", "sticky_web")
		out.append("对手的场地张开了黏黏网！")

	# 折磨：对手不能连续使用同一招式
	if effect == "TORMENT":
		defender["no_repeat"] = 99
		out.append("%s 被折磨，不能连续使用同一招式！" % defender["name"])

	# 浸水：把对手变成水属性
	if effect == "SOAK" and not bool(defender["fainted"]):
		defender["types"] = ["water"]
		out.append("%s 变成了水属性！" % defender["name"])

	# 改写特性
	if effect == "OVERWRITE_ABILITY" and not bool(defender["fainted"]):
		defender["ability_name"] = "无"
		out.append("%s 的特性被抹掉了！" % defender["name"])

	# 聚气：会心等级提升
	if effect == "FOCUS_ENERGY":
		attacker["crit_stage"] = clampi(int(attacker.get("crit_stage", 0)) + 2, 0, 4)
		out.append("%s 集中精神，容易击中要害了！" % attacker["name"])

	# 光合作用 / 晨光 / 月光：按天气回血
	if effect == "SYNTHESIS":
		var ratio2 := 0.5
		if String(field.weather) == "sun":
			ratio2 = 0.66
		elif String(field.weather) in ["rain", "sandstorm", "snow"]:
			ratio2 = 0.25
		var sh2: int = maxi(1, int(int(attacker["max_hp"]) * ratio2))
		_set_hp(attacker, mini(int(attacker["max_hp"]), int(attacker["hp"]) + sh2))
		out.append("%s 回复了 %d 点体力。" % [attacker["name"], sh2])

	# 蓄力 / 喷出 / 吞下
	if effect == "STOCKPILE":
		attacker["stockpile"] = mini(3, int(attacker.get("stockpile", 0)) + 1)
		_apply_stage(attacker, "def", 1, out)
		_apply_stage(attacker, "spd", 1, out)
		out.append("%s 蓄力了（%d 层）。" % [attacker["name"], int(attacker["stockpile"])])
	if effect == "SPIT_UP":
		var layers := int(attacker.get("stockpile", 0))
		if layers <= 0:
			out.append("但是没有蓄力，什么也没发生。")
		else:
			out.append("%s 把蓄的力喷了出去！" % attacker["name"])
	if effect == "SWALLOW":
		var layers2 := int(attacker.get("stockpile", 0))
		if layers2 <= 0:
			out.append("但是没有蓄力，什么也没发生。")
		else:
			var heal2: int = int(int(attacker["max_hp"]) * (0.25 * layers2))
			_set_hp(attacker, mini(int(attacker["max_hp"]), int(attacker["hp"]) + heal2))
			attacker["stockpile"] = 0
			out.append("%s 吞了下去，回复了 %d 点体力。" % [attacker["name"], heal2])

	# 其余五花八门的招式行为统一交给总表
	_extra_effect(effect, attacker, defender, move, dealt, out)

	# 交换持有物（戏法 / 掉包）
	if effect == "TRICK":
		var a_item := String(attacker.get("held", ""))
		var d_item := String(defender.get("held", ""))
		attacker["held"] = d_item
		defender["held"] = a_item
		out.append("%s 和 %s 交换了携带物。" % [attacker["name"], defender["name"]])

	# 交换特性（特性互换）
	if effect == "SKILL_SWAP":
		var a_ab := String(attacker.get("ability_name", ""))
		attacker["ability_name"] = String(defender.get("ability_name", ""))
		defender["ability_name"] = a_ab
		out.append("%s 和 %s 交换了特性。" % [attacker["name"], defender["name"]])

	# 力量互换 / 防守互换 / 速度互换 / 心灵互换
	if effect in ["POWER_SWAP", "GUARD_SWAP", "SPEED_SWAP", "HEART_SWAP"]:
		var keys_a: Array = []
		var keys_b: Array = []
		match effect:
			"POWER_SWAP":
				keys_a = ["atk", "spa"]
			"GUARD_SWAP":
				keys_a = ["def", "spd"]
			"SPEED_SWAP":
				keys_a = ["spe"]
			"HEART_SWAP":
				keys_a = ["atk", "def", "spa", "spd", "spe", "acc", "eva"]
		for k in keys_a:
			var va := int(attacker["stages"].get(k, 0))
			var vb := int(defender["stages"].get(k, 0))
			attacker["stages"][k] = vb
			defender["stages"][k] = va
		out.append("%s 和 %s 交换了能力变化。" % [attacker["name"], defender["name"]])

	# 力量戏法：交换攻击与防御
	if effect == "POWER_TRICK":
		var sa := int(attacker["stats"].get("atk", 0))
		var sd := int(attacker["stats"].get("def", 0))
		attacker["stats"]["atk"] = sd
		attacker["stats"]["def"] = sa
		out.append("%s 交换了自己的攻击与防御。" % attacker["name"])

	# 戏法空间：五回合内速度慢的先出手
	if effect == "TRICK_ROOM":
		field.trick_room = not bool(field.trick_room)
		field.trick_room_turns = 5 if bool(field.trick_room) else 0
		out.append("戏法空间%s了！" % ("展开" if bool(field.trick_room) else "解除"))

	# 撒隐形岩
	if effect == "STEALTH_ROCK":
		field.add_hazard("b" if _side_of(attacker) == "a" else "a", "stealth_rock")
		out.append("对手的场地被撒下了隐形岩！")

	# 反作用力只在没打中时生效（飞踢、飞膝踢）
	if effect == "RECOIL_IF_MISS" and dealt <= 0:
		var miss_dmg: int = maxi(1, int(int(attacker["max_hp"]) / 2))
		_set_hp(attacker, maxi(0, int(attacker["hp"]) - miss_dmg))
		out.append("%s 摔了一跤，损失了 %d 点体力。" % [attacker["name"], miss_dmg])
		if int(attacker["hp"]) <= 0:
			attacker["fainted"] = true
			out.append("%s 倒下了！" % attacker["name"])


	return "\n".join(out)

static func _stat_name(k: String) -> String:
	match k:
		"atk": return "攻击"
		"def": return "防御"
		"spa": return "特攻"
		"spd": return "特防"
		"spe": return "速度"
		"acc": return "命中率"
		"eva": return "闪避率"
	return k

static func _status_name(st: String) -> String:
	match st:
		"psn": return "中毒"
		"tox": return "剧毒"
		"par": return "麻痹"
		"brn": return "灼伤"
		"frz": return "冰冻"
		"slp": return "睡眠"
		"cfu": return "混乱"
		"inf": return "着迷"
	return "异常状态"

static func _status_text(who: String, st: String) -> String:
	match st:
		"psn": return "%s 中毒了！" % who
		"tox": return "%s 中了剧毒！" % who
		"par": return "%s 麻痹了，可能无法行动！" % who
		"brn": return "%s 被灼伤了！" % who
		"frz": return "%s 被冻住了！" % who
		"slp": return "%s 睡着了！" % who
	return "%s 的状态变了。" % who

## 特性免疫状态：免疫/柔软/水幕/不眠/干劲/魔术防守
const ABILITY_BLOCKS := {
	"psn": ["免疫"], "tox": ["免疫"],
	"par": ["柔软"], "brn": ["水幕"], "slp": ["不眠", "干劲"],
}

## 属性免疫：火不会烧、电不会麻、毒和钢不会中毒、冰不会冻
static func _status_immune(st: String, _first: String, types: Array, ability: String = "") -> bool:
	if ABILITY_BLOCKS.has(st) and ABILITY_BLOCKS[st].has(ability):
		return true
	var ae: Dictionary = Data.ability_effect(ability)
	var si: Array = ae.get("status_immune", [])
	if si.has(st):
		return true
	match st:
		"brn":
			return types.has("fire")
		"par":
			return types.has("electric")
		"psn", "tox":
			return types.has("poison") or types.has("steel")
		"frz":
			return types.has("ice")
	return false

## 这一招的行动优先度：换人 6，用药 6，招式用自己的 priority
func _priority(side: String, choice: String) -> int:
	if choice.begins_with("switch:") or choice == "item":
		return 6
	if choice == "none" or choice == "":
		return 0
	var c: Dictionary = cur_a() if side == "a" else cur_b()
	var idx := int(choice.split(":")[1]) if choice.contains(":") else 0
	var mv: Dictionary = {}
	# 挣扎的基础优先度为零，不继承耗尽招式的先制效果。
	if idx >= 0 and idx < c.moves.size() and int(c.pp[idx]) > 0:
		mv = Data.move_of(int(c.moves[idx]))
	var pr := int(mv.get("priority", 0))
	var ae: Dictionary = Data.ability_effect(_ab(c))
	if bool(ae.get("triage_priority", false)) and String(mv.get("effect", "")) in ["RESTORE_HP", "SOFTBOILED", "HEAL_HALF", "DRAIN"]:
		pr += 3
	if float(ae.get("quick_draw", 0.0)) > 0.0 and rng.randf() < float(ae["quick_draw"]):
		pr += 1
	if bool(ae.get("slow_priority", false)):
		pr -= 7
	return pr

const X_STAGES := {"X_ATTACK":"atk", "X_DEFEND":"def", "X_SPECIAL":"spa", "X_SPEED":"spe", "X_ACCURACY":"acc"}

func use_battle_item(side: String, key: String) -> bool:
	var mon := cur_a() if side == "a" else cur_b()
	if over or bool(mon.get("fainted", false)): return false
	if key == "GUARD_SPEC":
		if int(guard_turns[side]) > 0: return false
		guard_turns[side] = 5
		log.append("能力防守将在五回合内保护我方能力。")
	elif key == "DIRE_HIT":
		if bool(mon.get("dire_hit", false)): return false
		mon["dire_hit"] = true
		log.append("%s 瞄准了对手的要害！" % str(mon.name))
	elif X_STAGES.has(key):
		var stat := str(X_STAGES[key])
		if int(mon.stages.get(stat, 0)) >= 6: return false
		_apply_stage(mon, stat, 1, log)
	else:
		return false
	return true

func _clear_round_hits() -> void:
	for mon in team_a + team_b:
		mon["hit_this_turn"] = 0
		mon.erase("acted_this_turn")

func run_turn(a_choice: String, b_choice: String) -> void:
	if over:
		return

	_clear_round_hits()
	var pa := _speed(cur_a())
	var pb := _speed(cur_b())
	var prio_a := _priority("a", a_choice)
	var prio_b := _priority("b", b_choice)

	# 戏法空间：五回合内速度慢的先动
	if bool(field.trick_room):
		var tmp := pa
		pa = -pb
		pb = -tmp
	var first := "a"
	if prio_b > prio_a:
		first = "b"
	elif prio_a == prio_b:
		var claw_a := str(cur_a().get("held", "")) == "QUICK_CLAW" and a_choice.begins_with("move:") and rng.randf() < 0.2
		var claw_b := str(cur_b().get("held", "")) == "QUICK_CLAW" and b_choice.begins_with("move:") and rng.randf() < 0.2
		if claw_a != claw_b:
			first = "a" if claw_a else "b"
			log.append("%s 的先制之爪发动了！" % str((cur_a() if claw_a else cur_b()).name))
		elif pb > pa:
			first = "b"
		elif pa == pb and rng.randi_range(0, 1) == 1:
			first = "b"

	cur_a()["moved_first"] = first == "a"
	cur_b()["moved_first"] = first != "a"
	if first == "a":
		_take_action("a", a_choice)
		if not over and not cur_b()["fainted"]:
			_take_action("b", b_choice)
	else:
		_take_action("b", b_choice)
		if not over and not cur_a()["fainted"]:
			_take_action("a", a_choice)

	acting_side = ""
	_end_of_turn()
	_end_of_turn_volatile()
	_end_of_turn_gmax()
	_end_of_turn_field()
	for side in guard_turns:
		guard_turns[side] = maxi(0, int(guard_turns[side]) - 1)
	_check_end()

## 追加效果的判定概率：天恩翻倍
func _effect_chance(mon: Dictionary, base: int) -> int:
	var abe: Dictionary = Data.ability_effect(_ab(mon))
	if abe.has("chance_mult"):
		return mini(100, int(base * float(abe["chance_mult"])))
	return base

## 接触类招式打到身上，可能被静电/火焰之躯/毒刺/孢子反制
func _contact_ability_effect(attacker: Dictionary, defender: Dictionary, move: Dictionary) -> void:
	if not _is_contact(attacker, move):
		return
	if String(attacker.get("status", "")) != "":
		return
	var ab := _ab(defender)
	var abe: Dictionary = Data.ability_effect(ab)
	if abe.has("contact_recoil"):
		var back: int = maxi(1, int(int(attacker["max_hp"]) * float(abe["contact_recoil"])))
		_set_hp(attacker, maxi(0, int(attacker["hp"]) - back))
		log.append("%s 的粗糙皮肤让 %s 损失了 %d 点体力。" % [defender["name"], attacker["name"], back])
		if int(attacker["hp"]) <= 0:
			attacker["fainted"] = true
			log.append("%s 倒下了！" % attacker["name"])
	# 数据表里的接触类特性：迷人之躯、诅咒之躯、黏滑
	var ci: Dictionary = abe.get("contact_inflict", {})
	if not ci.is_empty() and rng.randi_range(1, 100) <= int(ci.get("chance", 30)):
		if bool(ci.get("disable", false)) and int(attacker.get("last_move", 0)) > 0:
			attacker["disabled"] = {"move": int(attacker["last_move"]), "turns": 3}
			log.append("%s 的%s封印了 %s 的招式！" % [defender["name"], ab, attacker["name"]])
		elif String(ci.get("status", "")) != "":
			var stx := String(ci["status"])
			if String(attacker.get("status", "")) == "" and not _status_immune(stx,
					String(attacker["types"][0] if not attacker["types"].is_empty() else ""),
					attacker["types"], _ab(attacker)):
				attacker["status"] = stx
				attacker["status_turns"] = rng.randi_range(2, 4)
				log.append("%s 的%s让 %s 陷入了%s！" % [defender["name"], ab, attacker["name"],
					"混乱" if stx == "cfu" else "着迷"])
	var csd := int(abe.get("contact_speed_drop", 0))
	if csd > 0:
		_apply_stage(attacker, "spe", -csd, log)
	# 挨打才生效的特性：正义之心、胆怯、遇水凝固、持久力
	var ohb: Dictionary = abe.get("on_hit_type_boost", {})
	if not ohb.is_empty() and String(ohb.get("type", "")) == String(move.get("type", "")):
		_apply_stage(defender, String(ohb.get("stat", "atk")), int(ohb.get("delta", 1)), log)
	elif not ohb.is_empty() and String(ohb.get("type", "")) in ["dark", "bug", "ghost"] \
			and String(move.get("type", "")) in ["dark", "bug", "ghost"]:
		_apply_stage(defender, String(ohb.get("stat", "spe")), int(ohb.get("delta", 1)), log)
	var ohs: Dictionary = abe.get("on_hit_stage", {})
	if not ohs.is_empty():
		_apply_stage(defender, String(ohs.get("stat", "def")), int(ohs.get("delta", 1)), log)

	var table := {"静电": "par", "火焰之躯": "brn", "毒刺": "psn", "孢子": "psn"}
	if not table.has(ab):
		return
	if rng.randf() < 0.3:
		var st := String(table[ab])
		attacker["status"] = st
		log.append("%s 的特性 %s 让 %s %s！" % [defender["name"], ab, attacker["name"],
			"麻痹了" if st == "par" else ("被灼伤了" if st == "brn" else "中毒了")])

## 体力过半以下自动退场（跃跃欲逃、危险回避）
func _check_emergency_exit(side: String) -> void:
	var c: Dictionary = cur_a() if side == "a" else cur_b()
	if bool(c.get("fainted", false)) or bool(c.get("exit_used", false)):
		return
	if not bool(Data.ability_effect(_ab(c)).get("switch_low_hp", false)):
		return
	if int(c["hp"]) * 2 > int(c["max_hp"]):
		return
	var nxt := _next_alive(side, active_a if side == "a" else active_b)
	if nxt < 0:
		return
	c["exit_used"] = true
	log.append("%s 的%s让它退回了队伍！" % [c["name"], _ab(c)])
	_do_switch(side, nxt, true)

## 受击后的被动特性：变色、复制特性、偷道具、灭亡之躯、吐沙、撒陷阱、怒气类
func _after_hit_passive(attacker: Dictionary, defender: Dictionary, move: Dictionary, dealt: int) -> void:
	if bool(defender.get("fainted", false)):
		if _ab(attacker) == "牵绊变身":
			attacker["kos"] = int(attacker.get("kos", 0)) + 1
		return
	var dabe: Dictionary = Data.ability_effect(_ab(defender))
	var mtype := String(move.get("type", "normal"))
	# 一口导弹：吞着猎物时被打，反咬对手一口
	if String(dabe.get("gulp_missile", "")) != "" or _ab(defender) == "一口导弹":
		if int(defender.get("species_id", 0)) == 845 and String(defender.get("form", "")) != "":
			var bite: int = maxi(1, int(int(attacker["max_hp"]) / 4.0))
			_set_hp(attacker, maxi(0, int(attacker["hp"]) - bite))
			log.append("%s 嘴里的猎物反击，%s 损失了 %d 点体力！" % [defender["name"], attacker["name"], bite])
			if int(attacker["hp"]) <= 0:
				attacker["fainted"] = true
				log.append("%s 倒下了！" % attacker["name"])
			switch_form(_side_of(defender), "", "%s 把猎物吐了出来。" % defender["name"])
	# 变色：被打中后属性变成招式属性
	if bool(dabe.get("color_change", false)) and not (defender["types"] as Array).has(mtype):
		defender["types"] = [mtype]
		log.append("%s 的属性变成了 %s！" % [defender["name"], Data.type_name(mtype)])
	# 木乃伊 / 甩不掉的气味：接触后改写对手特性
	var new_ab := String(dabe.get("ability_change_on_contact", ""))
	if new_ab != "" and _is_contact(attacker, move):
		if String(attacker.get("ability_name", "")) != new_ab:
			attacker["ability_name"] = new_ab
			log.append("%s 的特性变成了%s！" % [attacker["name"], new_ab])
	# 游魂：接触后交换特性
	if bool(dabe.get("ability_swap_on_contact", false)) and _is_contact(attacker, move):
		var tmp_ab := String(attacker.get("ability_name", ""))
		attacker["ability_name"] = String(defender.get("ability_name", ""))
		defender["ability_name"] = tmp_ab
		log.append("%s 和 %s 交换了特性！" % [attacker["name"], defender["name"]])
	# 顺手牵羊：被打时偷走对手的携带物
	if bool(dabe.get("steal_on_contact", false)) and _is_contact(attacker, move):
		var it := String(attacker.get("held", ""))
		if it != "" and String(defender.get("held", "")) == "" \
				and not bool(Data.ability_effect(_ab(attacker)).get("prevent_steal", false)):
			defender["held"] = it
			attacker["held"] = ""
			log.append("%s 顺手牵羊拿走了 %s！" % [defender["name"], Data.item_name(it)])
	# 灭亡之躯：双方开始倒数
	if bool(dabe.get("perish_on_contact", false)) and _is_contact(attacker, move):
		for m in [attacker, defender]:
			if int((m as Dictionary).get("perish", 0)) <= 0:
				(m as Dictionary)["perish"] = 4
		log.append("%s 的灭亡之躯让双方开始倒数！" % defender["name"])
	# 吐沙：被打就刮沙暴
	var woh := String(dabe.get("weather_on_hit", ""))
	if woh != "" and String(field.weather) != woh:
		log.append(field.set_weather(woh))
		log.append("%s 的%s引起了天气变化！" % [defender["name"], _ab(defender)])
	# 掉出种子 / 毒满地：在对手场地撒陷阱
	var haz := String(dabe.get("hazard_on_hit", ""))
	if haz != "" and haz != "grassy_seed":
		field.add_hazard(_side_of(attacker), haz)
		log.append("%s 在对手的场地上撒下了陷阱！" % defender["name"])
	# 愤怒穴位 / 能量点 / 不屈之心这类：被会心或畏缩时提升
	var ocb: Dictionary = dabe.get("on_crit_boost", {})
	if not ocb.is_empty() and bool(last_crit):
		_apply_stage(defender, String(ocb.get("stat", "atk")), int(ocb.get("delta", 1)), log)
	# 愤怒甲壳：血过半时双防降、速度拉满
	if bool(dabe.get("anger_shell", false)) and not bool(defender.get("anger_shell_used", false)) \
			and int(defender["hp"]) * 2 <= int(defender["max_hp"]):
		defender["anger_shell_used"] = true
		_apply_stage(defender, "def", -1, log)
		_apply_stage(defender, "spd", -1, log)
		_apply_stage(defender, "spe", 6, log)
	# 怒火冲天：血量掉到一半以下时特攻 +1
	var hdb: Dictionary = dabe.get("on_hp_drop_boost", {})
	if not hdb.is_empty() and not bool(defender.get("hp_boost_used", false)) \
			and int(defender["hp"]) * 2 <= int(defender["max_hp"]):
		defender["hp_boost_used"] = true
		_apply_stage(defender, String(hdb.get("stat", "spa")), int(hdb.get("delta", 1)), log)
	# 引爆 / 飞出的内在物：被打倒时反伤
	if int(defender["hp"]) <= 0:
		var ofd := float(dabe.get("on_faint_damage", 0.0))
		if ofd > 0.0 and not bool(attacker["fainted"]):
			var dmg3: int = maxi(1, int(int(attacker["max_hp"]) * ofd))
			_set_hp(attacker, maxi(0, int(attacker["hp"]) - dmg3))
			log.append("%s 的%s让 %s 损失了 %d 点体力。" % [defender["name"], _ab(defender), attacker["name"], dmg3])
			if int(attacker["hp"]) <= 0:
				attacker["fainted"] = true
				log.append("%s 倒下了！" % attacker["name"])


## 招式附加行为总表：剩下那些五花八门的 effect 都收在这里，一个地方管完
func _extra_effect(effect: String, attacker: Dictionary, defender: Dictionary, move: Dictionary, dealt: int, out: Array) -> void:
	if effect == "":
		return
	var heal_half := func(who: Dictionary) -> void:
		if int(who["hp"]) >= int(who["max_hp"]):
			out.append("%s 的体力已经满了。" % who["name"])
		else:
			var h: int = maxi(1, int(int(who["max_hp"]) / 2.0))
			_set_hp(who, mini(int(who["max_hp"]), int(who["hp"]) + h))
			out.append("%s 回复了 %d 点体力。" % [who["name"], h])
	match effect:
		# ---------------- 回复类 ----------------
		"REST":
			attacker["status"] = "slp"
			attacker["status_turns"] = 2
			_set_hp(attacker, int(attacker["max_hp"]))
			out.append("%s 睡着了，体力完全恢复了。" % attacker["name"])
		"MORNING_SUN", "MOONLIGHT":
			var r := 0.5
			if String(field.weather) == "sun":
				r = 0.66
			elif String(field.weather) in ["rain", "sandstorm", "snow"]:
				r = 0.25
			var hh: int = maxi(1, int(int(attacker["max_hp"]) * r))
			_set_hp(attacker, mini(int(attacker["max_hp"]), int(attacker["hp"]) + hh))
			out.append("%s 回复了 %d 点体力。" % [attacker["name"], hh])
		"REVIVAL_BLESSING", "HEALING_WISH", "LUNAR_DANCE":
			var my_team: Array = team_a if _side_of(attacker) == "a" else team_b
			var revived := false
			for m in my_team:
				if not revived and bool((m as Dictionary).get("fainted", false)):
					(m as Dictionary)["fainted"] = false
					(m as Dictionary)["hp"] = maxi(1, int(int((m as Dictionary)["max_hp"]) / 2))
					(m as Dictionary)["status"] = ""
					revived = true
					out.append("%s 重新站了起来！" % (m as Dictionary)["name"])
			if not revived:
				out.append("但是没有需要复活的同伴。")
			if effect == "HEALING_WISH" or effect == "LUNAR_DANCE":
				_set_hp(attacker, 0)
				attacker["fainted"] = true
				out.append("%s 用尽了自己。" % attacker["name"])
		"PURIFY":
			if String(attacker.get("status", "")) != "":
				attacker["status"] = ""
				attacker["status_turns"] = 0
				out.append("%s 的异常状态被净化了。" % attacker["name"])
			heal_half.call(attacker)
		"TAKE_HEART":
			attacker["status"] = ""
			attacker["status_turns"] = 0
			_apply_stage(attacker, "spa", 1, out)
			_apply_stage(attacker, "spd", 1, out)
		"REFRESH":
			if String(attacker.get("status", "")) in ["psn", "tox", "par", "brn"]:
				attacker["status"] = ""
				attacker["status_turns"] = 0
				out.append("%s 的状态恢复了。" % attacker["name"])
			else:
				out.append("但是没有效果……")
		"RECYCLE":
			if String(attacker.get("eaten_berry", "")) != "":
				attacker["berry"] = String(attacker["eaten_berry"])
				out.append("%s 找回了%s。" % [attacker["name"], Data.berry_name(String(attacker["eaten_berry"]))])
			else:
				out.append("但是没有可以拿回来的东西。")
		"INGRAIN":
			attacker["aqua_ring"] = true
			out.append("%s 把根扎进了地面！" % attacker["name"])
		# ---------------- 能力类 ----------------
		"GROWTH":
			var gd := 2 if String(field.weather) == "sun" else 1
			_apply_stage(attacker, "atk", gd, out)
			_apply_stage(attacker, "spa", gd, out)
		"DEFENSE_CURL":
			_apply_stage(attacker, "def", 1, out)
		"MINIMIZE":
			_apply_stage(attacker, "eva", 2, out)
		"AUTOTOMIZE":
			_apply_stage(attacker, "spe", 2, out)
			attacker["weight_light"] = true
		"GEOMANCY":
			_apply_stage(attacker, "spa", 2, out)
			_apply_stage(attacker, "spd", 2, out)
			_apply_stage(attacker, "spe", 2, out)
		"NO_RETREAT":
			for st9 in ["atk", "def", "spa", "spd", "spe"]:
				_apply_stage(attacker, String(st9), 1, out)
			attacker["trapped"] = true
		"CLANGOROUS_SOUL":
			for st8 in ["atk", "def", "spa", "spd", "spe"]:
				_apply_stage(attacker, String(st8), 1, out)
			var cost8: int = maxi(1, int(int(attacker["max_hp"]) / 3.0))
			_set_hp(attacker, maxi(1, int(attacker["hp"]) - cost8))
		"FLOWER_SHIELD":
			_apply_stage(attacker, "def", 1, out)
		"ACUPRESSURE":
			var pool8 := ["atk", "def", "spa", "spd", "spe"]
			_apply_stage(attacker, String(pool8[rng.randi_range(0, pool8.size() - 1)]), 2, out)
		"PSYCH_UP":
			for k8 in (defender["stages"] as Dictionary).keys():
				attacker["stages"][k8] = int(defender["stages"][k8])
			out.append("%s 复制了对手的能力变化！" % attacker["name"])
		"POWER_SPLIT", "GUARD_SPLIT":
			var ka := "atk" if effect == "POWER_SPLIT" else "def"
			var kb := "spa" if effect == "POWER_SPLIT" else "spd"
			for kk in [ka, kb]:
				var avg2 := int((int(attacker["stats"][kk]) + int(defender["stats"][kk])) / 2)
				attacker["stats"][kk] = avg2
				defender["stats"][kk] = avg2
			out.append("双方的能力被平分了。")
		# ---------------- 特性与招式复制 ----------------
		"ROLE_PLAY", "DOODLE":
			attacker["ability_name"] = String(defender.get("ability_name", ""))
			out.append("%s 复制了 %s 的特性！" % [attacker["name"], defender["name"]])
		"ENTRAINMENT":
			defender["ability_name"] = String(attacker.get("ability_name", ""))
			out.append("%s 把特性分享给了 %s！" % [attacker["name"], defender["name"]])
		"GASTRO_ACID":
			defender["ability_name"] = "无"
			out.append("%s 的特性被溶解了！" % defender["name"])
		"TRANSFORM", "MIMIC", "SKETCH", "COPYCAT", "ME_FIRST", "MIRROR_MOVE", "ASSIST", "METRONOME":
			var their: Array = defender["moves"]
			if their.is_empty():
				out.append("但是没有可以借用的招式。")
			else:
				var borrowed := int(their[rng.randi_range(0, their.size() - 1)])
				out.append("%s 借用了招式：%s！" % [attacker["name"],
					String((Data.move_of(borrowed) as Dictionary).get("name", "?"))])
		"CONVERSION", "CONVERSION_2", "CAMOUFLAGE":
			attacker["types"] = ["normal"]
			out.append("%s 变成了一般属性。" % attacker["name"])
		"REFLECT_TYPE":
			attacker["types"] = (defender["types"] as Array).duplicate()
			out.append("%s 变成了和对手一样的属性！" % attacker["name"])
		"INSTRUCT":
			out.append("%s 指挥 %s 再来一次！" % [attacker["name"], defender["name"]])
		"IMPRISON":
			out.append("%s 封住了共通的招式！" % attacker["name"])
		# ---------------- 道具类 ----------------
		"KNOCK_OFF":
			var knocked := String(defender.get("held", ""))
			if knocked != "" and not bool(Data.ability_effect(_ab(defender)).get("prevent_steal", false)):
				defender["held"] = ""
				out.append("%s 打掉了 %s 的%s！" % [attacker["name"], defender["name"], Data.item_name(knocked)])
		"FLING":
			var flung := String(attacker.get("held", ""))
			if flung != "":
				attacker["held"] = ""
				out.append("%s 扔出了%s！" % [attacker["name"], Data.item_name(flung)])
			else:
				out.append("但是没有可以扔的东西。")
		"BESTOW":
			if String(attacker.get("held", "")) != "" and String(defender.get("held", "")) == "":
				defender["held"] = String(attacker["held"])
				attacker["held"] = ""
				out.append("%s 把携带物交给了 %s。" % [attacker["name"], defender["name"]])
			else:
				out.append("但是没有交出去。")
		"CORROSIVE_GAS":
			if String(defender.get("held", "")) != "":
				defender["held"] = ""
				out.append("%s 的携带物被腐蚀了！" % defender["name"])
			else:
				out.append("但是没有效果……")
		"EMBARGO":
			defender["embargo"] = 5
			out.append("%s 暂时不能用携带物了！" % defender["name"])
		"NATURAL_GIFT":
			out.append("%s 用携带物使出了自然之恩。" % attacker["name"])
		# ---------------- 场地与屏障 ----------------
		"REFLECT":
			out.append(field.set_screen(_side_of(attacker), "reflect"))
		"LIGHT_SCREEN":
			out.append(field.set_screen(_side_of(attacker), "light_screen"))
		"AURORA_VEIL":
			out.append(field.set_screen(_side_of(attacker), "aurora_veil"))
		"SAFEGUARD":
			attacker["safeguard"] = 5
			out.append("%s 这边被神秘守护罩住了！" % attacker["name"])
		"LUCKY_CHANT":
			attacker["lucky_chant"] = 5
			out.append("%s 这边不会被会心了！" % attacker["name"])
		"MAGIC_COAT":
			attacker["magic_coat"] = 1
			out.append("%s 披上了魔法反射！" % attacker["name"])
		"MAT_BLOCK":
			attacker["mat_block"] = 1
			out.append("%s 铺开了垫子！" % attacker["name"])
		"GRAVITY":
			out.append(field.set_gravity())
		"MAGIC_ROOM":
			attacker["magic_room"] = 5
			out.append("魔法空间展开了，携带物暂时失效。")
		"COURT_CHANGE":
			var tmp_screens: Dictionary = (field.screens["a"] as Dictionary).duplicate()
			field.screens["a"] = (field.screens["b"] as Dictionary).duplicate()
			field.screens["b"] = tmp_screens
			out.append("双方的场地效果被交换了！")
		"ION_DELUGE":
			attacker["ion_deluge"] = 5
			out.append("电离场地展开了，电属性招式变强！")
		"ELECTRIFY":
			defender["electrified"] = 1
			out.append("%s 的下一招会变成电属性！" % defender["name"])
		"WATER_SPORT":
			attacker["water_sport"] = 5
			out.append("四周被水幕包围，火属性招式变弱了。")
		"MUD_SPORT":
			attacker["mud_sport"] = 5
			out.append("四周被泥浆包围，电属性招式变弱了。")
		"MAGNET_RISE":
			attacker["levitating"] = 5
			out.append("%s 浮在了空中！" % attacker["name"])
		# ---------------- 换人与牺牲 ----------------
		"TELEPORT", "SHED_TAIL":
			var nxt5 := _next_alive(_side_of(attacker), active_a if _side_of(attacker) == "a" else active_b)
			if nxt5 >= 0:
				_do_switch(_side_of(attacker), nxt5)
				out.append("%s 换下了场。" % attacker["name"])
			else:
				out.append("但是没有可以换上的同伴。")
		"PARTING_SHOT":
			_apply_stage(defender, "atk", -1, out)
			_apply_stage(defender, "spa", -1, out)
			var nxt6 := _next_alive(_side_of(attacker), active_a if _side_of(attacker) == "a" else active_b)
			if nxt6 >= 0:
				_do_switch(_side_of(attacker), nxt6)
		"U_TURN", "VOLT_SWITCH", "FLIP_TURN":
			var nxt7 := _next_alive(_side_of(attacker), active_a if _side_of(attacker) == "a" else active_b)
			if nxt7 >= 0:
				_do_switch(_side_of(attacker), nxt7)
		"MEMENTO":
			_apply_stage(defender, "atk", -2, out)
			_apply_stage(defender, "spa", -2, out)
			_set_hp(attacker, 0)
			attacker["fainted"] = true
			out.append("%s 倒下了，%s 的能力大幅下降！" % [attacker["name"], defender["name"]])
		"FINAL_GAMBIT":
			var my_hp := int(attacker["hp"])
			_set_hp(defender, maxi(0, int(defender["hp"]) - my_hp))
			_set_hp(attacker, 0)
			attacker["fainted"] = true
			if int(defender["hp"]) <= 0:
				defender["fainted"] = true
			out.append("双方都倒下了！")
		"BIDE":
			attacker["bide"] = 2
			out.append("%s 开始忍耐！" % attacker["name"])
		"LASER_FOCUS":
			attacker["laser_focus"] = true
			out.append("%s 集中精神，下一招必定击中要害！" % attacker["name"])
		"POLTERGEIST":
			if String(defender.get("held", "")) == "":
				out.append("但是没有效果……对手身上没有东西。")
		"SECRET_POWER":
			var pool9 := ["atk", "def", "spe", "spd", "spa"]
			_apply_stage(defender, String(pool9[rng.randi_range(0, pool9.size() - 1)]), -1, out)
		"SUCKER_PUNCH":
			# 突袭：对手上回合没出攻击招式就失败
			var their_mv: Dictionary = Data.move_of(int(defender.get("last_move", 0)))
			if String(their_mv.get("category", "")) != "physical" and String(their_mv.get("category", "")) != "special":
				out.append("%s 没有出手，突袭落空了！" % defender["name"])
		"UPPER_HAND":
			# 上勾拳：对手出攻击招式时让它畏缩
			var their2: Dictionary = Data.move_of(int(defender.get("last_move", 0)))
			if String(their2.get("category", "")) != "status":
				defender["flinch"] = true
				out.append("%s 被上勾拳打中，畏缩了！" % defender["name"])
		"ENDEAVOR":
			# 舍身冲撞：把对手体力拉到和自己一样
			if int(defender["hp"]) > int(attacker["hp"]):
				_set_hp(defender, int(attacker["hp"]))
				out.append("%s 的体力被拉平了！" % defender["name"])
		"FIXED_HP_DAMAGE":
			var fixed := int((move.get("extra", {}) as Dictionary).get("value", 20))
			_set_hp(defender, maxi(0, int(defender["hp"]) - fixed))
			out.append("对 %s 造成了 %d 点伤害。" % [defender["name"], fixed])
			if int(defender["hp"]) <= 0:
				defender["fainted"] = true
				out.append("%s 倒下了！" % defender["name"])
		"DREAM_EATER":
			if String(defender.get("status", "")) == "slp" and dealt > 0:
				var dh: int = maxi(1, int(dealt / 2))
				_set_hp(attacker, mini(int(attacker["max_hp"]), int(attacker["hp"]) + dh))
				out.append("%s 吃掉了对手的梦，回复了 %d 点体力。" % [attacker["name"], dh])
			elif String(defender.get("status", "")) != "slp":
				out.append("但是没有效果……对手没有睡着。")
		"EXTREME_EVOBOOST":
			for st7 in ["atk", "def", "spa", "spd", "spe"]:
				_apply_stage(attacker, String(st7), 2, out)
		"SCALE_SHOT":
			_apply_stage(attacker, "spe", 1, out)
			_apply_stage(attacker, "def", -1, out)
		"POPULATION_BOMB", "BEAT_UP":
			out.append("连续攻击了多次！")
		"FELL_STINGER":
			if bool(defender["fainted"]):
				_apply_stage(attacker, "atk", 3, out)
		"STONE_AXE", "CEASELESS_EDGE":
			field.add_hazard("b" if _side_of(attacker) == "a" else "a", "stealth_rock")
			out.append("尖锐的岩石撒满了对手的场地！")
		"STEEL_ROLLER":
			for sd2 in ["a", "b"]:
				var hz5: Dictionary = field.hazards.get(sd2, {})
				for k6 in hz5.keys():
					if typeof(hz5[k6]) == TYPE_BOOL:
						hz5[k6] = false
					else:
						hz5[k6] = 0
			if String(field.terrain) != "":
				field.set_terrain("")
			out.append("场地被碾平了！")
		"RAGING_BULL":
			attacker["protected"] = false
			out.append("%s 撞碎了所有的屏障！" % attacker["name"])
		"HYPERSPACE_FURY", "HYPERSPACE_HOLE":
			out.append("直接打穿了空间，守不住！")
		"PURSUIT":
			out.append("%s 追了上去！" % attacker["name"])
		"PSYCHO_SHIFT":
			if String(attacker.get("status", "")) != "" and String(defender.get("status", "")) == "":
				defender["status"] = String(attacker["status"])
				defender["status_turns"] = int(attacker.get("status_turns", 0))
				attacker["status"] = ""
				attacker["status_turns"] = 0
				out.append("%s 把状态推给了 %s！" % [attacker["name"], defender["name"]])
			else:
				out.append("但是没有效果……")
		"POWDER":
			defender["powdered"] = 1
			out.append("%s 身上沾满了粉末！" % defender["name"])
		"MIRACLE_EYE":
			defender["identified"] = true
			out.append("%s 被奇迹之眼看穿了！" % defender["name"])
		"ODOR_SLEUTH":
			defender["identified"] = true
		"TEATIME":
			for m8 in [attacker, defender]:
				if String((m8 as Dictionary).get("berry", "")) != "":
					var bkey := String((m8 as Dictionary)["berry"])
					(m8 as Dictionary)["berry"] = ""
					out.append("%s 吃掉了%s。" % [(m8 as Dictionary)["name"], Data.berry_name(bkey)])
		"STUFF_CHEEKS":
			if String(attacker.get("berry", "")) != "":
				var bk2 := String(attacker["berry"])
				attacker["berry"] = ""
				_apply_stage(attacker, "def", 1, out)
				out.append("%s 吃掉了%s，防御提升了！" % [attacker["name"], Data.berry_name(bk2)])
			else:
				out.append("但是没有树果可以吃。")
		"BELCH":
			if bool(attacker.get("ate_berry", false)):
				out.append("%s 打了一个响嗝！" % attacker["name"])
			else:
				out.append("但是没有吃东西，打不出来。")
		"LAST_RESORT":
			out.append("%s 使出了最后的撒娇！" % attacker["name"])
		"SNATCH":
			out.append("%s 准备好抢招了！" % attacker["name"])
		"PLEDGE":
			out.append("合击招式威力提升了！")
		"REVELATION_DANCE", "AURA_WHEEL", "TWO_TYPED_MOVE":
			pass
		"WEATHER_AND_SWITCH":
			out.append(field.set_weather(String((move.get("extra", {}) as Dictionary).get("weather", "sun"))))
		"STAT_CHANGE_MAGNETIC":
			_apply_stage(defender, "spe", -1, out)
		"STAT_CHANGE_ON_STATUS":
			if String(defender.get("status", "")) != "":
				_apply_stage(defender, "spe", -1, out)
		"STAT_CHANGE_HALF_HP":
			if int(attacker["hp"]) * 2 <= int(attacker["max_hp"]):
				_apply_stage(attacker, "atk", 1, out)
		"FAIL_IF_NOT_ARG_TYPE":
			var want_t := String((move.get("extra", {}) as Dictionary).get("type", ""))
			if want_t != "" and not (defender["types"] as Array).has(want_t):
				out.append("但是没有效果……")
		"SUPER_EFFECTIVE_ON_ARG":
			out.append("效果拔群！")
		"FOLLOW_ME", "HELPING_HAND", "AFTER_YOU", "QUASH", "ALLY_SWITCH", "ROTOTILLER", "DRAGON_CHEER", "HOLD_HANDS", "SKY_DROP", "HIT_ENEMY_HEAL_ALLY", "HEAL_PULSE":
			out.append("这是双打招式，单人战斗里帮不上忙。")
		"HAPPY_HOUR", "CELEBRATE", "DO_NOTHING", "SPECIES_POWER_OVERRIDE", "DYNAMAX_DOUBLE_DMG":
			pass
		"CHLOROBLAST", "BEAK_BLAST":
			pass
		"CAPTIVATE":
			_apply_stage(defender, "spa", -2, out)
		"GRAV_APPLE":
			_apply_stage(defender, "def", -1, out)
		"GRASSY_GLIDE":
			pass
		"FRUSTRATION":
			pass
		"TERA_BLAST", "TERA_STARSTORM":
			if bool(attacker.get("tera_active", false)):
				out.append("太晶爆发强化了！")
		"DARK_VOID":
			# 暗黑洞：直接让对方睡着
			if String(defender.get("status", "")) == "":
				defender["status"] = "slp"
				defender["status_turns"] = rng.randi_range(1, 3)
				out.append("%s 睡着了！" % defender["name"])
		"STOMPING_TANTRUM":
			# 大怒暴走：上回合没打成，这回合威力翻倍
			if bool(attacker.get("last_failed", false)):
				out.append("%s 的怒火让威力翻倍了！" % attacker["name"])
		# 下面这些由通用逻辑处理（附加状态/能力变化/场地/极巨招式），这里只占位
		"HIT", "STAT_CHANGE", "NON_VOLATILE_STATUS", "MAX_MOVE", "WEATHER", "TERRAIN":
			pass
		"STRUGGLE":
			# 挣扎：固定伤害并反伤（内核里有专门处理，这里占位）
			pass
		_:
			pass

## 回合末结算：中毒/灼伤扣血 + 特性带来的回合末效果
func _end_of_turn() -> void:
	completed_turns+=1
	for c in [cur_a(), cur_b()]:
		if c["fainted"] or int(c["hp"]) <= 0:
			continue
		# 靠血量/天气/回合驱动的形态切换（达摩模式、鱼群、界限盾壳、群聚变形、饱了又饿、阴晴不定）
		_form_switch_end_turn(c)
		var ae: Dictionary = Data.ability_effect(_ab(c))
		c["turns_on_field"] = int(c.get("turns_on_field", 0)) + 1
		# 心情不定：随机 +2、随机 -1
		if bool(ae.get("moody", false)):
			var pool := ["atk", "def", "spa", "spd", "spe", "acc", "eva"]
			var up := String(pool[rng.randi_range(0, pool.size() - 1)])
			_apply_stage(c, up, 2, log)
			var down := String(pool[rng.randi_range(0, pool.size() - 1)])
			if down != up:
				_apply_stage(c, down, -1, log)
		# 阴晴不定：每回合随机提升一项
		if bool(ae.get("weather_stat_any", false)):
			var pool2 := ["atk", "def", "spa", "spd", "spe"]
			_apply_stage(c, String(pool2[rng.randi_range(0, pool2.size() - 1)]), 1, log)
		# 捡拾 / 采蜜：给个可感知的结果
		if bool(ae.get("pickup", false)) and rng.randf() < 0.3:
			log.append("%s 的%s捡到了点东西。" % [c["name"], _ab(c)])
		# 加速：每回合速度 +1
		var tb: Dictionary = ae.get("turn_boost", {})
		if not tb.is_empty():
			_apply_stage(c, String(tb.get("stat", "spe")), int(tb.get("delta", 1)), log)
		# 蜕皮：一定概率治好异常
		if float(ae.get("cure_chance", 0.0)) > 0.0 and String(c.get("status", "")) != "":
			if rng.randf() < float(ae["cure_chance"]):
				log.append("%s 靠%s治好了%s！" % [c["name"], _ab(c), _status_name(String(c["status"]))])
				c["status"] = ""
				c["status_turns"] = 0
		# 湿润之躯：下雨时治好异常
		var wcure := String(ae.get("weather_cure", ""))
		if wcure != "" and wcure == String(field.weather) and String(c.get("status", "")) != "":
			log.append("%s 靠%s治好了%s！" % [c["name"], _ab(c), _status_name(String(c["status"]))])
			c["status"] = ""
			c["status_turns"] = 0
		# 收获：把吃掉的树果捡回来
		if bool(ae.get("harvest", false)) and String(c.get("berry", "")) == "" \
				and String(c.get("eaten_berry", "")) != "" and rng.randf() < 0.5:
			c["berry"] = String(c["eaten_berry"])
			c["eaten_berry"] = ""
			log.append("%s 的%s把%s捡了回来！" % [c["name"], _ab(c), Data.berry_name(String(c["berry"]))])
		# 梦魇：对手睡着时掉血
		if bool(ae.get("nightmare", false)):
			var foe3: Dictionary = cur_b() if c == cur_a() else cur_a()
			if String(foe3.get("status", "")) == "slp" and not bool(foe3["fainted"]):
				var nd3: int = maxi(1, int(int(foe3["max_hp"]) / 8.0))
				_set_hp(foe3, maxi(0, int(foe3["hp"]) - nd3))
				log.append("%s 的%s让睡着的 %s 损失了 %d 点体力。" % [c["name"], _ab(c), foe3["name"], nd3])
				if int(foe3["hp"]) <= 0:
					foe3["fainted"] = true
					log.append("%s 倒下了！" % foe3["name"])
		if c["fainted"] or int(c["hp"]) <= 0:
			continue
		var st := String(c.get("status", ""))
		if bool(Data.ability_effect(_ab(c)).get("poison_heal", false)) and (st == "psn" or st == "tox"):
			var ph: int = maxi(1, int(int(c["max_hp"]) / 8.0))
			_set_hp(c, mini(int(c["max_hp"]), int(c["hp"]) + ph))
			log.append("%s 靠%s回复了 %d 点体力。" % [c["name"], _ab(c), ph])
		elif st == "psn" or st == "tox" or st == "brn":
			var dmg: int = maxi(1, int(int(c["max_hp"]) / 8.0))
			_set_hp(c, maxi(0, int(c["hp"]) - dmg))
			log.append("%s 受到了%s的伤害。" % [c["name"], "剧毒" if st == "tox" else ("灼伤" if st == "brn" else "中毒")])
			if int(c["hp"]) <= 0:
				c["fainted"] = true
				log.append("%s 倒下了！" % c["name"])

## 回合末结算之二：超极巨缠住类招式的持续伤害、护盾回合数
func _end_of_turn_gmax() -> void:
	for c in [cur_a(), cur_b()]:
		if c["fainted"] or int(c["hp"]) <= 0:
			continue
		var r = c.get("residual", {})
		if r is Dictionary and not (r as Dictionary).is_empty():
			var rd: Dictionary = r
			var frac := maxi(1, int(rd.get("frac", 6)))
			var dmg2: int = maxi(1, int(int(c["max_hp"]) / frac))
			_set_hp(c, maxi(0, int(c["hp"]) - dmg2))
			log.append("%s 受到了持续伤害 %d 点。" % [c["name"], dmg2])
			rd["turns"] = int(rd.get("turns", 0)) - 1
			if int(rd["turns"]) <= 0:
				c["residual"] = {}
				log.append("%s 摆脱了束缚。" % c["name"])
			if int(c["hp"]) <= 0:
				c["fainted"] = true
				log.append("%s 倒下了！" % c["name"])
		if int(c.get("shield_turns", 0)) > 0:
			c["shield_turns"] = int(c["shield_turns"]) - 1
			if int(c["shield_turns"]) <= 0:
				log.append("%s 身边的极光消失了。" % c["name"])

## 回合末结算之二半：寄生种子、诅咒、恶梦、灭亡之歌、预知未来
func _end_of_turn_volatile() -> void:
	for c in [cur_a(), cur_b()]:
		if bool(c["fainted"]):
			continue
		var who := String(c["name"])
		# 寄生种子：掉 1/8，给对面
		if bool(c.get("leech_seed", false)):
			var stolen: int = maxi(1, int(int(c["max_hp"]) / 8.0))
			_set_hp(c, maxi(0, int(c["hp"]) - stolen))
			log.append("%s 的体力被寄生种子吸走了 %d 点。" % [who, stolen])
			var other: Dictionary = cur_b() if c == cur_a() else cur_a()
			if not bool(other["fainted"]):
				_set_hp(other, mini(int(other["max_hp"]), int(other["hp"]) + stolen))
		# 诅咒
		if bool(c.get("cursed", false)):
			var cd: int = maxi(1, int(int(c["max_hp"]) / 4.0))
			_set_hp(c, maxi(0, int(c["hp"]) - cd))
			log.append("%s 被诅咒折磨，损失了 %d 点体力。" % [who, cd])
		# 恶梦：睡着才掉
		if bool(c.get("nightmare", false)):
			if String(c.get("status", "")) != "slp":
				c["nightmare"] = false
			else:
				var nd: int = maxi(1, int(int(c["max_hp"]) / 4.0))
				_set_hp(c, maxi(0, int(c["hp"]) - nd))
				log.append("%s 做了恶梦，损失了 %d 点体力。" % [who, nd])
		# 灭亡之歌倒数
		if int(c.get("perish", 0)) > 0:
			c["perish"] = int(c["perish"]) - 1
			if int(c["perish"]) <= 0:
				_set_hp(c, 0)
				log.append("%s 随着灭亡之歌倒下了！" % who)
			else:
				log.append("%s 的灭亡倒计时还剩 %d。" % [who, int(c["perish"])])
		# 预知未来
		var fut: Dictionary = c.get("future", {})
		if not fut.is_empty():
			var turns_left := int(fut.get("turns", 0)) - 1
			fut["turns"] = turns_left
			if turns_left <= 0:
				var fd := int(fut.get("damage", 0))
				var foe2: Dictionary = cur_b() if c == cur_a() else cur_a()
				if not bool(foe2["fainted"]) and fd > 0:
					_set_hp(foe2, maxi(0, int(foe2["hp"]) - fd))
					log.append("预知未来的攻击命中了 %s，造成 %d 点伤害！" % [foe2["name"], fd])
				c["future"] = {}
		# 哈欠：倒数到 0 就睡着
		if int(c.get("yawn", 0)) > 0:
			c["yawn"] = int(c["yawn"]) - 1
			if int(c["yawn"]) <= 0 and String(c.get("status", "")) == "":
				c["status"] = "slp"
				c["status_turns"] = rng.randi_range(1, 3)
				log.append("%s 睡着了！" % who)
		# 各种回合标记递减
		if int(c.get("taunt", 0)) > 0:
			c["taunt"] = int(c["taunt"]) - 1
		if int(c.get("encore", 0)) > 0:
			c["encore"] = int(c["encore"]) - 1
		if int(c.get("heal_block", 0)) > 0:
			c["heal_block"] = int(c["heal_block"]) - 1
		var dis: Dictionary = c.get("disabled", {})
		if not dis.is_empty():
			dis["turns"] = int(dis.get("turns", 0)) - 1
			if int(dis["turns"]) <= 0:
				c["disabled"] = {}
		if int(c["hp"]) <= 0:
			_set_hp(c, 0)
			c["fainted"] = true
			log.append("%s 倒下了！" % who)

## 回合末结算之三：天气掉血、青草场地回血、各种回合数递减
func _end_of_turn_field(tick_field := true) -> void:
	# 守住只维持这一回合
	for c in [cur_a(), cur_b()]:
		c["protected"] = false
		c["flinch"] = false
		c["roosting"] = false
	# 水流环
	for c in [cur_a(), cur_b()]:
		if bool(c.get("aqua_ring", false)) and not c["fainted"]:
			if int(c["hp"]) < int(c["max_hp"]):
				var h: int = maxi(1, int(int(c["max_hp"]) / 16.0))
				_set_hp(c, mini(int(c["max_hp"]), int(c["hp"]) + h))
				log.append("%s 借水环回复了体力。" % c["name"])
	# 许愿
	if tick_field:
		for line in field.tick_wish([cur_a(), cur_b()]):
			log.append(String(line))
		for line in field.end_turn([cur_a(), cur_b()]):
			log.append(String(line))
	# 携带道具：剩饭回血
	for c in [cur_a(), cur_b()]:
		for line in held_end_turn(c):
			log.append(String(line))
	# 树果：规则全在 content/berries.json，这里只管什么时候问它
	for c in [cur_a(), cur_b()]:
		for line in _weather_ability_end_turn(c):
			log.append(String(line))
		for line in _try_berry(c):
			log.append(String(line))

## 树果：数据在 content/berries.json，这里只按 kind 分流，不为每颗果写 if
## cat：被什么分类的招式打中（physical / special），只有"挨打才生效"的果会用到
func _try_berry(c: Dictionary, cat: String = "") -> Array:
	var out: Array = []
	var key := String(c.get("berry", ""))
	if key == "" or bool(c.get("fainted", false)):
		return out
	var d: Dictionary = Data.berry_def(key)
	if d.is_empty():
		return out
	# 紧张感：在场时对手吃不了树果
	var foe_of_c: Dictionary = cur_b() if c == cur_a() else cur_a()
	if bool(Data.ability_effect(_ab(foe_of_c)).get("block_foe_berry", false)):
		return out
	var nam := String(d.get("name", key))
	var hp := int(c["hp"])
	var mx := int(c["max_hp"])
	match String(d.get("kind", "")):
		"heal":
			if hp * 2 > mx:
				return out
			var heal := 0
			match String(d.get("mode", "flat")):
				"flat":
					heal = int(d.get("value", 10))
				"half":
					heal = int(mx / 2.0)
				_:
					heal = int(mx / 3.0)
			heal = maxi(1, heal)
			if bool(Data.ability_effect(_ab(c)).get("berry_double", false)):
				heal *= 2
			var bonus := float(Data.ability_effect(_ab(c)).get("berry_bonus", 0.0))
			if bonus > 0.0:
				heal += maxi(1, int(mx * bonus))
			_set_hp(c, mini(mx, hp + heal))
			out.append("%s 吃掉了%s，回复了 %d 点体力。" % [c["name"], nam, int(c["hp"]) - hp])
		"pp":
			var idx := -1
			for i in (c["pp"] as Array).size():
				if int(c["pp"][i]) <= 0:
					idx = i
					break
			if idx < 0:
				return out
			var mv_id := int((c["moves"] as Array)[idx])
			var mx_pp := int((Data.move_of(mv_id) as Dictionary).get("pp", 10))
			var pbonus = c.get("pp_bonus", {})
			if pbonus is Dictionary:
				mx_pp += int((pbonus as Dictionary).get(str(mv_id), 0))
			var before := int(c["pp"][idx])
			c["pp"][idx] = mini(mx_pp, before + int(d.get("value", 10)))
			out.append("%s 吃掉了%s，%s 回复了 %d 点 PP。" % [c["name"], nam,
				String((Data.move_of(mv_id) as Dictionary).get("name", "招式")),
				int(c["pp"][idx]) - before])
		"cure":
			var want: Array = d.get("status", [])
			if not (String(c.get("status", "")) in want):
				return out
			c["status"] = ""
			c["status_turns"] = 0
			out.append("%s 吃掉了%s，状态恢复了！" % [c["name"], nam])
		"cure_all":
			if String(c.get("status", "")) == "":
				return out
			c["status"] = ""
			c["status_turns"] = 0
			out.append("%s 吃掉了%s，异常状态全部解除！" % [c["name"], nam])
		"boost":
			if hp * 4 > mx:
				return out
			var st := String(d.get("stat", "atk"))
			if st == "random":
				var pool := ["atk", "def", "spa", "spd", "spe"]
				st = String(pool[rng.randi_range(0, pool.size() - 1)])
			var cur := int(c["stages"].get(st, 0))
			if cur >= 6:
				return out
			c["stages"][st] = clampi(cur + int(d.get("stages", 1)), -6, 6)
			out.append("%s 吃掉了%s，%s提升了！" % [c["name"], nam, _stat_name(st)])
		"crit":
			if hp * 4 > mx:
				return out
			c["crit_stage"] = clampi(int(c.get("crit_stage", 0)) + int(d.get("stages", 2)), 0, 4)
			out.append("%s 吃掉了%s，会心等级提升了！" % [c["name"], nam])
		"boost_on_hit":
			if cat == "" or cat != String(d.get("cat", "")):
				return out
			var st2 := String(d.get("stat", "def"))
			var cur2 := int(c["stages"].get(st2, 0))
			if cur2 >= 6:
				return out
			c["stages"][st2] = clampi(cur2 + int(d.get("stages", 1)), -6, 6)
			out.append("%s 吃掉了%s，%s提升了！" % [c["name"], nam, _stat_name(st2)])
		_:
			return out
	c["berry"] = ""
	# 反刍：树果留着还能再吃一次
	if bool(Data.ability_effect(_ab(c)).get("berry_twice", false)) and not bool(c.get("berry_twice_used", false)):
		c["berry"] = key
		c["berry_twice_used"] = true
	c["eaten_berry"] = key
	return out

## 回合末的特性结算：雨盘回血、太阳之力掉血
func _weather_ability_end_turn(mon: Dictionary) -> Array:
	var out: Array = []
	if bool(mon.get("fainted", false)):
		return out
	var abe: Dictionary = Data.ability_effect(_ab(mon))
	var heal_map: Dictionary = abe.get("weather_heal", {})
	if heal_map.has(String(field.weather)):
		var h: int = maxi(1, int(int(mon["max_hp"]) * float(heal_map[String(field.weather)])))
		if int(mon["hp"]) < int(mon["max_hp"]):
			_set_hp(mon, mini(int(mon["max_hp"]), int(mon["hp"]) + h))
			out.append("%s 的%s回复了 %d 点体力。" % [mon["name"], _ab(mon), h])
	var rec_map: Dictionary = abe.get("weather_recoil", {})
	if rec_map.has(String(field.weather)):
		var r: int = maxi(1, int(int(mon["max_hp"]) * float(rec_map[String(field.weather)])))
		_set_hp(mon, maxi(0, int(mon["hp"]) - r))
		out.append("%s 被%s反噬，损失了 %d 点体力。" % [mon["name"], _ab(mon), r])
		if int(mon["hp"]) <= 0:
			mon["fainted"] = true
			out.append("%s 倒下了！" % mon["name"])
	return out

## 回合末的携带道具结算：剩饭回血、生命宝珠反伤
func held_end_turn(mon: Dictionary) -> Array:
	var out: Array = []
	if bool(mon.get("fainted", false)):
		return out
	# 笨拙：携带物完全不起作用
	if bool(Data.ability_effect(_ab(mon)).get("ignore_own_item", false)):
		return out
	match String(mon.get("held", "")):
		"LEFTOVERS":
			if int(mon["hp"]) < int(mon["max_hp"]):
				var h: int = maxi(1, int(int(mon["max_hp"]) / 16.0))
				_set_hp(mon, mini(int(mon["max_hp"]), int(mon["hp"]) + h))
				out.append("%s 靠吃剩的东西回复了 %d 点体力。" % [mon["name"], h])
	return out

## 结实：满血时被一击打倒会留下 1 点体力
func _sturdy_save(mon: Dictionary, dealt: int, move_line: int) -> bool:
	if not bool(Data.ability_effect(_ab(mon)).get("survive_full", false)):
		return false
	if int(mon["hp"]) < int(mon["max_hp"]):
		return false
	if int(mon["hp"]) - dealt > 0:
		return false
	_set_hp(mon, 1, move_line)
	return true

## 气势披带：满血被一击打倒时留 1 点
func _focus_sash_save(mon: Dictionary, dealt: int, move_line: int) -> bool:
	if String(mon.get("held", "")) != "FOCUS_SASH":
		return false
	if int(mon["hp"]) - dealt > 0:
		return false
	if int(mon["hp"]) < int(mon["max_hp"]):
		return false
	mon["held"] = ""
	_set_hp(mon, 1, move_line)
	return true

## 天气带来的速度加成与免疫
func _weather_speed_mult(c: Dictionary) -> float:
	var wsd: Dictionary = Data.ability_effect(_ab(c)).get("weather_speed", {})
	if not wsd.is_empty() and String(wsd.get("weather", "")) == String(field.weather):
		return float(wsd.get("mult", 2.0))
	match _ab(c):
		"悠游自如":
			return 2.0 if field.weather == "rain" else 1.0
		"拨沙":
			return 2.0 if field.weather == "sandstorm" else 1.0
		"拨雪":
			return 2.0 if field.weather == "snow" else 1.0
		"叶绿素":
			return 2.0 if field.weather == "sun" else 1.0
	return 1.0

## 不受天气伤害的特性
func _weather_immune_by_ability(c: Dictionary) -> bool:
	var ab := _ab(c)
	if ab in ["防尘", "沙隐", "沙之力", "拨沙", "雪隐", "冰冻之躯", "拨雪"]:
		return true
	if bool(Data.ability_effect(ab).get("weather_immune", false)):
		return true
	return false

func _speed(c: Dictionary) -> int:
	var sp := float(c["stats"]["spe"]) * _stage_mult(c["stages"]["spe"])
	sp *= _weather_speed_mult(c)
	if String(c.get("held", "")) == "MACHO_BRACE": sp *= 0.5
	if String(c.get("held", "")) == "CHOICE_SCARF":
		sp *= 1.5
	# 顺风：四回合内速度翻倍
	var my_side2 := _side_of(c)
	if int((field.screens.get(my_side2, {}) as Dictionary).get("tailwind", 0)) > 0:
		sp *= 2.0
	# 轻装：失去携带物后速度翻倍
	if bool(Data.ability_effect(_ab(c)).get("unburden", false)) and String(c.get("held", "")) == "":
		sp *= 2.0
	# 场地加速（冲浪之尾这类）
	var ts: Dictionary = Data.ability_effect(_ab(c)).get("terrain_stat", {})
	if not ts.is_empty() and String(ts.get("terrain", "")) == String(field.terrain) \
			and String(ts.get("stat", "")) == "spe":
		sp *= float(ts.get("mult", 1.5))
	# 异常状态下的速度特性：飞毛腿
	if String(c.get("status", "")) != "":
		var sm2: Dictionary = Data.ability_effect(_ab(c)).get("stat_mult", {})
		if bool(Data.ability_effect(_ab(c)).get("status_only", false)) and sm2.has("spe"):
			sp *= float(sm2["spe"])
	# 麻痹速度减半
	if String(c.get("status", "")) == "par":
		sp *= 0.5
	return int(sp)

## 防御侧的回避修正（沙隐、雪隐这类）
func _evasion_mult(c: Dictionary) -> float:
	if bool(Data.ability_effect(_ab(c)).get("evasion_when_confused", false)) \
			and String(c.get("status", "")) == "cfu":
		return 1.5
	var we: Dictionary = Data.ability_effect(_ab(c)).get("weather_evasion", {})
	if not we.is_empty() and String(we.get("weather", "")) == String(field.weather):
		return float(we.get("mult", 1.0))
	return 1.0

## 统一的能力变化入口：防护、反转、翻倍都在这里
func _apply_stage(mon: Dictionary, stat: String, delta: int, logref: Array) -> void:
	if delta == 0:
		return
	var ae: Dictionary = Data.ability_effect(_ab(mon))
	if delta < 0:
		var side := _side_of(mon)
		if int(guard_turns[side]) > 0 and acting_side != side:
			logref.append("能力防守保护了%s。" % str(mon.name))
			return
		var prot = ae.get("protect_stat", null)
		if bool(ae.get("no_stat_drop", false)) or bool(ae.get("stat_mirror", false)):
			prot = "all"
		var blocked := false
		if prot is String:
			blocked = String(prot) == "all"
		elif prot is Array:
			blocked = (prot as Array).has(stat)
		if blocked:
			logref.append("%s 的%s不会被降低。" % [mon["name"], _stat_name(stat)])
			return
	var d := delta
	if bool(ae.get("invert_stages", false)):
		d = -d
	if bool(ae.get("double_stages", false)):
		d *= 2
	var cur := int(mon["stages"].get(stat, 0))
	if (d < 0 and cur <= -6) or (d > 0 and cur >= 6):
		logref.append("%s 的%s已经到极限了。" % [mon["name"], _stat_name(stat)])
		return
	mon["stages"][stat] = clampi(cur + d, -6, 6)
	logref.append("%s 的%s%s了！" % [mon["name"], _stat_name(stat), "下降" if d < 0 else "上升"])
	# 跟风：对手提升时自己也跟着提升
	if d > 0 and not team_a.is_empty() and not team_b.is_empty():
		var foe5: Dictionary = cur_b() if mon == cur_a() else cur_a()
		if bool(Data.ability_effect(_ab(foe5)).get("boost_on_foe_boost", false)):
			var fc := int(foe5["stages"].get(stat, 0))
			foe5["stages"][stat] = clampi(fc + d, -6, 6)
			logref.append("%s 的%s跟着提升了！" % [foe5["name"], _stat_name(stat)])
	# 被降低能力时的反击型特性：不服输、好胜
	if delta < 0:
		var db: Dictionary = ae.get("drop_boost", {})
		if not db.is_empty():
			var bs := String(db.get("stat", "atk"))
			mon["stages"][bs] = clampi(int(mon["stages"].get(bs, 0)) + int(db.get("delta", 2)), -6, 6)
			logref.append("%s 的%s因为%s大幅提升了！" % [mon["name"], _stat_name(bs), _ab(mon)])

## 开打前先看状态：睡着的不能动，麻痹有概率动不了，冰冻有概率自己解
func _blocked_by_status(c: Dictionary) -> bool:
	var st := String(c.get("status", ""))
	match st:
		"slp":
			var left := int(c.get("status_turns", 0))
			if left > 0:
				c["status_turns"] = left - 1
				log.append("%s 正在睡觉，无法行动。" % c["name"])
				return true
			c["status"] = ""
			log.append("%s 醒过来了！" % c["name"])
			return false
		"frz":
			if rng.randf() < 0.2:
				c["status"] = ""
				log.append("%s 身上的冰融化了！" % c["name"])
				return false
			log.append("%s 被冻住了，无法行动。" % c["name"])
			return true
		"par":
			if rng.randf() < 0.25:
				log.append("%s 麻痹了，无法行动！" % c["name"])
				return true
		"cfu":
			var left2 := int(c.get("status_turns", 0))
			if left2 <= 0:
				c["status"] = ""
				log.append("%s 的混乱解除了！" % c["name"])
				return false
			c["status_turns"] = left2 - 1
			if rng.randf() < 0.33:
				var self_dmg: int = maxi(1, int(int(c["max_hp"]) / 8.0))
				_set_hp(c, maxi(0, int(c["hp"]) - self_dmg))
				log.append("%s 混乱了，打了自己 %d 点伤害！" % [c["name"], self_dmg])
				if int(c["hp"]) <= 0:
					c["fainted"] = true
					log.append("%s 倒下了！" % c["name"])
				return true
			return false
		"inf":
			var left3 := int(c.get("status_turns", 0))
			if left3 <= 0:
				c["status"] = ""
				log.append("%s 不再着迷了。" % c["name"])
				return false
			c["status_turns"] = left3 - 1
			if rng.randf() < 0.5:
				log.append("%s 着迷了，无法行动！" % c["name"])
				return true
	# 着迷（招式附带的那个标记）
	if bool(c.get("attract", false)) and rng.randf() < 0.5:
		log.append("%s 看得入迷，忘了行动！" % c["name"])
		return true
	return false

func _take_action(side: String, choice: String) -> void:
	if choice=="palace_wait":
		log.append("这只宝可梦没能使出合适的招式。")
		return
	acting_side = side
	var attacker: Dictionary = cur_a() if side == "a" else cur_b()
	var defender: Dictionary = cur_b() if side == "a" else cur_a()
	if attacker["fainted"]:
		return

	attacker.acted_this_turn=true
	if side=="b" and attacker.get("fr_roaming",false) and not attacker.get("trapped",false) and attacker.get("status","") not in ["slp","frz"] and _ab(defender) not in ["踩影","沙穴"]:
		fled=true
		over=true
		winner="fled"
		log.append("%s逃走了！"%attacker.name)
		return
	if choice == "item" or choice == "none" or choice == "":
		# 用药、投球这类不消耗行动的攻击段：只留给对手打
		return
	if choice.begins_with("switch:"):
		_do_switch(side, int(choice.split(":")[1]))
		return

	# 畏缩：上一位出手的招式让这只缩了一下，这回合动不了
	if bool(attacker.get("flinch", false)):
		attacker["flinch"] = false
		if not bool(Data.ability_effect(_ab(attacker)).get("flinch_immune", false)):
			log.append("%s 畏缩了，无法行动！" % attacker["name"])
			return

	var idx := int(choice.split(":")[1]) if choice.contains(":") else 0
	if idx < 0 or idx >= (attacker["moves"] as Array).size():
		idx = 0
	if attacker.moves.is_empty() or int(attacker.pp[idx]) <= 0:
		_struggle(side)
		return
	# 精神场地：先制招式在这边打不出来
	var mprio := int((Data.move_of(int(attacker["moves"][idx])) as Dictionary).get("priority", 0))
	var foe_side_ab: Dictionary = cur_b() if side == "a" else cur_a()
	if mprio > 0 and bool(Data.ability_effect(_ab(foe_side_ab)).get("priority_block", false)):
		log.append("%s 的%s封住了先制招式！" % [foe_side_ab["name"], _ab(foe_side_ab)])
		return
	if field.blocks_priority(mprio, true):
		log.append("%s 的先制招式被精神场地挡下了！" % attacker["name"])
		return

	# 状态挡住行动：睡/冻/麻，扣不扣 PP 按原版是不扣的
	if _blocked_by_status(attacker):
		return

	# 被超极巨液金熔击封住时，不能连着用同一招
	if int(attacker.get("no_repeat", 0)) > 0:
		attacker["no_repeat"] = int(attacker["no_repeat"]) - 1
		if int(attacker.get("last_move", 0)) == int(attacker["moves"][idx]):
			log.append("%s 被限制，无法连续使用同一招式！" % attacker["name"])
			return

	var base_id := int(attacker["moves"][idx])
	if int(attacker.get("metronome_move",0))!=base_id or attacker.get("held","")!="METRONOME":
		attacker.erase("metronome_chain")
		attacker.erase("metronome_move")
	# 挑衅：不能用变化招式
	var mv_pre: Dictionary = Data.move_of(base_id)
	if int(attacker.get("taunt", 0)) > 0 and String(mv_pre.get("category", "")) == "status":
		log.append("%s 被挑衅了，用不出变化招式！" % attacker["name"])
		return
	# 定身法：被封的招式不能用
	var dis0: Dictionary = attacker.get("disabled", {})
	if not dis0.is_empty() and int(dis0.get("move", 0)) == base_id:
		log.append("%s 的这招被封印了！" % attacker["name"])
		return
	var ch: Dictionary = attacker.get("charging", {})
	var releasing := false
	if not ch.is_empty() and int(ch.get("move", 0)) == base_id:
		# 上一回合已经蓄好力，这一回合是放出来的那一下（不再扣 PP）
		attacker["charging"] = {}
		attacker["semi_invuln"] = false
		releasing = true
	else:
		attacker["charging"] = {}
		var pp_cost := 2 if bool(Data.ability_effect(_ab(defender)).get("pp_pressure", false)) else 1
		attacker["pp"][idx] = int(attacker["pp"][idx]) - pp_cost
		attacker["last_move"] = base_id
	var mv: Dictionary = Data.move_of(base_id)
	# 上回合才上场才能用的招式（击掌奇袭这类）
	if String(mv.get("effect", "")) == "FIRST_TURN_ONLY" and int(attacker.get("turns_on_field", 0)) > 0:
		log.append("但是没有效果……这招只有刚上场时才好使。")
		return
	# 懒惰：每两回合才能动一次
	if bool(Data.ability_effect(_ab(attacker)).get("loaf", false)):
		attacker["loaf_skip"] = not bool(attacker.get("loaf_skip", false))
		if bool(attacker["loaf_skip"]):
			log.append("%s 懒洋洋地不想动……" % attacker["name"])
			return
	# 战斗切换：坚盾剑怪攻击时变成刀剑形态
	if _ab(attacker) == "战斗切换" and int(attacker.get("species_id", 0)) == 681 \
			and String(attacker.get("form", "")) != "AEGISLASH_BLADE" \
			and String(mv.get("category", "")) != "status":
		switch_form(side, "AEGISLASH_BLADE", "%s 切换成了刀剑形态！" % attacker["name"])
	# 变幻自如 / 自由者：出招前把自己变成该招式的属性
	if bool(Data.ability_effect(_ab(attacker)).get("type_change_on_move", false)) \
			and String(mv.get("category", "")) != "status":
		var newt := String(mv.get("type", "normal"))
		if not (attacker["types"] as Array).has(newt):
			attacker["types"] = [newt]
			log.append("%s 变成了 %s 属性！" % [attacker["name"], Data.type_name(newt)])
	# Z 招式：这一回合按 Z 版本打
	if choice.begins_with("z:"):
		var zd: Dictionary = z_move_data(attacker, base_id)
		if zd.is_empty():
			log.append("%s 的 %s 没能变成 Z 招式。" % [attacker["name"], String(mv.get("name", "?"))])
		else:
			mv = zd
			attacker["z_used"] = int(attacker.get("z_used", 0)) + 1
	# 极巨化 / 超极巨：攻击招式换成极巨招式
	elif bool(attacker.get("gmax_active", false)) and String(mv.get("category", "")) != "status" \
			and int(mv.get("power", 0)) > 0:
		mv = _max_move_data(attacker, mv)
	# 两回合招式：第一回合只是蓄力，第二回合才打出来
	var eff0 := String(mv.get("effect", ""))
	if eff0 == "FOCUS_PUNCH" and int(attacker.get("hit_this_turn", 0)) > 0:
		log.append("%s 受到攻击，无法集中精神！" % attacker.name)
		return
	if not releasing and eff0 in ["TWO_TURNS_ATTACK", "SEMI_INVULNERABLE", "SOLAR_BEAM", "FLY", "DIG", "DIVE"]:
		attacker["charging"] = {"move": base_id}
		# 半无敌：蓄力这一回合打不到它（飞翔、挖洞、潜水、潜灵奇袭这些）
		attacker["semi_invuln"] = eff0 == "SEMI_INVULNERABLE"
		match eff0:
			"SEMI_INVULNERABLE":
				log.append("%s 消失了身影！" % attacker["name"])
			"SOLAR_BEAM":
				log.append("%s 开始吸收光线！" % attacker["name"])
			_:
				log.append("%s 正在蓄力！" % attacker["name"])
		return

	# 太晶爆发：属性跟着太晶属性走，物特取更高的那一项
	if String((mv.get("field", {}) as Dictionary).get("kind", "")) == "tera_blast":
		if bool(attacker.get("tera_active", false)):
			mv = (mv as Dictionary).duplicate(true)
			mv["type"] = String(attacker.get("tera_type", "normal"))
			var atk_v := float(attacker["stats"].get("atk", 0))
			var spa_v := float(attacker["stats"].get("spa", 0))
			mv["category"] = "physical" if atk_v >= spa_v else "special"

	var move_line := log.size()
	log.append("%s 使用了 %s！" % [attacker["name"], mv.get("name", "?")])
	# 一口导弹：用完冲浪/潜水就吞了猎物，进入吞形态
	if _ab(attacker) == "一口导弹" and int(attacker.get("species_id", 0)) == 845 \
			and String(mv.get("key", "")) in ["SURF", "DIVE"]:
		var gulp_form := "CRAMORANT_GORGING" if float(int(attacker["hp"])) <= float(int(attacker["max_hp"])) * 0.5 else "CRAMORANT_GULPING"
		switch_form(side, gulp_form, "%s 一口吞下了猎物！" % attacker["name"])

	# 舞步形态：美洛耶塔用了古老之歌就切换
	if int(attacker.get("species_id", 0)) == 648 and String(mv.get("key", "")) == "RELIC_SONG":
		switch_form(side, "MELOETTA_PIROUETTE", "%s 随着歌声转成了舞步形态！" % attacker["name"])

	# 湿气：谁都不能自爆
	if eff0 == "SELFDESTRUCT" or eff0 == "EXPLOSION":
		for g in [cur_a(), cur_b()]:
			if bool(Data.ability_effect(_ab(g)).get("block_selfdestruct", false)):
				log.append("%s 的湿气让这一招用不出来！" % g["name"])
				return

	# 守住：这一回合挡下所有攻击
	if eff0 == "PROTECT":
		attacker["protected"] = true
		log.append("%s 保护住了自己！" % attacker["name"])
		if _ab(attacker) == "战斗切换" and int(attacker.get("species_id", 0)) == 681:
			switch_form(side, "", "%s 变回了盾牌形态。" % attacker["name"])
		return

	# 替身：扣 1/4 体力做一个挡箭牌
	if eff0 == "SUBSTITUTE":
		if int(attacker.get("sub_hp", 0)) > 0:
			log.append("%s 已经有替身了。" % attacker["name"])
			return
		var cost: int = maxi(1, int(int(attacker["max_hp"]) / 4.0))
		if int(attacker["hp"]) <= cost:
			log.append("体力不够，替身没有做出来。")
			return
		_set_hp(attacker, int(attacker["hp"]) - cost)
		attacker["sub_hp"] = cost
		log.append("%s 做出了替身！" % attacker["name"])
		return

	# 接力棒：换人并把能力变化带过去
	if eff0 == "BATON_PASS":
		var nxt := _next_alive(side, idx)
		if nxt < 0:
			log.append("没有可以接力上场的同伴。")
			return
		var carry_stages: Dictionary = (attacker["stages"] as Dictionary).duplicate()
		var carry_sub := int(attacker.get("sub_hp", 0))
		attacker["charging"] = {}
		attacker["sub_hp"] = 0
		_do_switch(side, nxt)
		var inc: Dictionary = team_a[active_a] if side == "a" else team_b[active_b]
		for k in carry_stages.keys():
			inc["stages"][k] = int(carry_stages[k])
		inc["sub_hp"] = carry_sub
		log.append("%s 接过了接力棒！" % inc["name"])
		return

	# 充电：下一发电系招式威力翻倍
	if eff0 == "CHARGE":
		attacker["charge"] = true
		log.append("%s 开始充电！" % attacker["name"])
		return

	# 许愿：两回合后回复一半体力
	if eff0 == "WISH":
		field.set_wish(_side_of(attacker))
		log.append("%s 许下了愿望！" % attacker["name"])
		return

	# 水流环：每回合回复 1/16
	if eff0 == "AQUA_RING":
		attacker["aqua_ring"] = true
		log.append("%s 被水环包围了！" % attacker["name"])
		return

	# 场地类招式（天气/场地/屏障/撒菱/重力）：设置完就不再打了
	var fr: Dictionary = mv.get("field", {})
	if not fr.is_empty() and String(fr.get("kind", "")) != "tera_blast":
		_apply_field_move(side, defender, fr)
		return

	# 防尘：粉末类招式无效
	if bool((mv.get("flags", {}) as Dictionary).get("powder", false)) \
			and bool(Data.ability_effect(_ab(defender)).get("powder_immune", false)):
		log.append("%s 的%s不吃粉末类招式！" % [defender["name"], _ab(defender)])
		return

	# 防音 / 防弹：整类招式直接无效
	var mvflags: Dictionary = mv.get("flags", {})
	var dabe0: Dictionary = Data.ability_effect(_ab(defender))
	var bflag := String(dabe0.get("block_flag", ""))
	if bflag != "" and bool(mvflags.get(bflag, false)):
		log.append("%s 的%s挡下了这一招！" % [defender["name"], _ab(defender)])
		return

	# 黄金之躯：完全不吃变化招式
	if String(mv.get("category", "")) == "status" \
			and bool(Data.ability_effect(_ab(defender)).get("immune_status_moves", false)):
		log.append("%s 的%s无视了变化招式！" % [defender["name"], _ab(defender)])
		return

	# 命中判定
	var acc: float = float(mv.get("accuracy", 100)) * float(field.accuracy_mod())
	var aabe0: Dictionary = Data.ability_effect(_ab(attacker))
	if bool(aabe0.get("no_miss", false)) or bool(dabe0.get("no_miss", false)):
		acc = 0.0
	else:
		if str(defender.get("held", "")) == "LAX_INCENSE": acc *= 0.95
		if not aabe0.get("ignore_own_item",false):
			if attacker.get("held","")=="WIDE_LENS":acc*=1.1
			elif attacker.get("held","")=="ZOOM_LENS" and defender.get("acted_this_turn",false):acc*=1.2
		acc *= float(aabe0.get("accuracy_mult", 1.0))
		acc *= _acc_mult(int(attacker["stages"].get("acc", 0)))
		acc /= _evasion_mult(defender)
		acc /= _acc_mult(int(defender["stages"].get("eva", 0)))
	if String(mv.get("category", "")) == "status":
		acc *= float(Data.ability_effect(_ab(defender)).get("status_move_resist", 1.0))
	if acc > 0 and acc < 100 and rng.randf_range(1, 100) > acc:
		log.append("但是没有命中……")
		return

	# 乘风 / 风力发电：风类招式无效
	var mflag0: Dictionary = mv.get("flags", {})
	var dabe_w: Dictionary = Data.ability_effect(_ab(defender))
	if bool(mflag0.get("wind", false)):
		if bool(dabe_w.get("wind_immune", false)):
			log.append("%s 的%s把风挡了下来！" % [defender["name"], _ab(defender)])
			_apply_stage(defender, "atk", 1, log)
			return
		if bool(dabe_w.get("wind_charge", false)):
			log.append("%s 的%s借着风充了电！" % [defender["name"], _ab(defender)])
			defender["charge"] = true

	# 头之冰：挡下一次物理伤害后冰碎，变成解冻形态
	if _ab(defender) == "头之冰" and not bool(defender.get("ice_face_used", false)) \
			and String(mv.get("category", "")) == "physical":
		defender["ice_face_used"] = true
		log.append("%s 的冰头挡下了这一击！" % defender["name"])
		if int(defender.get("species_id", 0)) == 875:
			switch_form(_side_of(defender), "EISCUE_NOICE", "%s 的冰头碎掉了！" % defender["name"])
		return

	# 画皮：用外皮挡下一次伤害，外皮破了就换成破损形态
	if bool(dabe_w.get("disguise", false)) and not bool(defender.get("disguise_used", false)):
		defender["disguise_used"] = true
		log.append("%s 的画皮替它挡下了这一击！" % defender["name"])
		if int(defender.get("species_id", 0)) == 778:
			switch_form(_side_of(defender), "MIMIKYU_BUSTED", "%s 的画皮破掉了！" % defender["name"])
		else:
			_set_hp(defender, maxi(0, int(defender["hp"]) - maxi(1, int(int(defender["max_hp"]) / 8.0))))
		return

	# 半无敌：蓄力消失的那一回合打不到
	if bool(defender.get("semi_invuln", false)):
		log.append("没有打中消失的 %s……" % defender["name"])
		return

	# 守住：挡下这一下
	if bool(defender.get("protected", false)) and not bool(Data.ability_effect(_ab(attacker)).get("no_protect", false)):
		log.append("%s 保护住了自己，没有受到伤害。" % defender["name"])
		return

	# 预知未来 / 破灭之愿：当回合不造成伤害，挂到两回合后
	var eff_fs := String(mv.get("effect", ""))
	if eff_fs in ["FUTURE_SIGHT", "DOOM_DESIRE"]:
		var fdeal := damage(attacker, defender, mv)
		attacker["future"] = {"turns": 3, "damage": maxi(1, fdeal)}
		log.append("%s 预见了未来的攻击！" % attacker["name"])
		return

	# Gen IV increases Metronome by 10% after each consecutive successful hit.
	var repeat_scale:=1.0
	if attacker.get("held","")=="METRONOME" and not aabe0.get("ignore_own_item",false):
		repeat_scale+=0.1*int(attacker.get("metronome_chain",0))
	var dealt := int(damage(attacker, defender, mv)*repeat_scale)
	if dealt>0 and attacker.get("held","")=="METRONOME" and not aabe0.get("ignore_own_item",false):
		attacker.metronome_move=base_id
		attacker.metronome_chain=mini(10,int(attacker.get("metronome_chain",0))+1)
	# 镜面反射、返拳、金属爆破：还回去的是上一回合受到的伤害的两倍
	if String(mv.get("effect", "")) == "REFLECT_DAMAGE":
		var back2 := int(attacker.get("last_damage", 0))
		if back2 <= 0:
			log.append("但是没有效果……")
			return
		dealt = back2 * 2
	# 充电：电系招式威力翻倍
	if bool(attacker.get("charge", false)) and String(mv.get("type", "")) == "electric":
		dealt = int(dealt * 2.0)
		attacker["charge"] = false
		log.append("充电让电系招式的威力提升了！")
	# 替身：伤害先打在替身上
	if int(defender.get("sub_hp", 0)) > 0 and dealt > 0 \
			and not bool(Data.ability_effect(_ab(attacker)).get("bypass_sub", false)):
		var sub: int = int(defender["sub_hp"])
		if dealt >= sub:
			defender["sub_hp"] = 0
			log.append("%s 的替身被打碎了！" % defender["name"])
		else:
			defender["sub_hp"] = sub - dealt
			log.append("%s 的替身承受了伤害。" % defender["name"])
		return
	if dealt > 0:
		if last_crit:
			log.append("击中了要害！")
		var hp_before_hit := int(defender["hp"])
		if hp_before_hit > 1 or not bool(defender.get("endure", false)):
			defender["hit_this_turn"] = int(defender.get("hit_this_turn", 0)) + 1
		defender["last_damage"] = dealt
		# 挺住：这一回合不会被打倒
		if bool(defender.get("endure", false)) and int(defender["hp"]) - dealt <= 0:
			_set_hp(defender, 1, move_line)
			defender["endure"] = false
			log.append("%s 靠挺住撑了下来！" % defender["name"])
			return
		if _sturdy_save(defender, dealt, move_line):
			log.append("%s 靠结实撑住了！" % defender["name"])
		elif not _focus_sash_save(defender, dealt, move_line):
			var before_hp := int(defender["hp"])
			_set_hp(defender, maxi(0, before_hp - dealt), move_line)
			if eff_fs == "FALSE_SWIPE" and int(defender["hp"]) <= 0:
				_set_hp(defender, 1, move_line)
				defender["fainted"] = false
				log.append("%s 撑住了，还剩 1 点体力！" % defender["name"])
		else:
			log.append("%s 靠气势披带撑住了！" % defender["name"])
		var eff := effectiveness_on(String(mv.get("type", "normal")), defender)
		if eff > 1.5:
			log.append("效果绝佳！")
		elif eff < 1.0 and eff > 0.0:
			log.append("效果不太好……")
		if last_berry != "":
			log.append("%s 吃掉了%s，伤害减弱了！" % [defender["name"], last_berry])
			last_berry = ""
		log.append("对 %s 造成了 %d 点伤害。" % [defender["name"], dealt])
		if str(attacker.get("held",""))=="SHELL_BELL" and int(attacker.hp)>0 and int(attacker.hp)<int(attacker.max_hp):
			var lost_hp:=hp_before_hit-int(defender.hp)
			if lost_hp>0:
				_set_hp(attacker,mini(int(attacker.max_hp),int(attacker.hp)+maxi(1,lost_hp/8)))
				log.append("%s的贝壳之铃恢复了体力。" % attacker.name)
		if String(attacker.get("held", "")) == "LIFE_ORB":
			var rec: int = maxi(1, int(int(attacker["max_hp"]) / 10.0))
			_set_hp(attacker, maxi(0, int(attacker["hp"]) - rec))
			log.append("%s 被生命宝珠反噬，损失了 %d 点体力。" % [attacker["name"], rec])
			if int(attacker["hp"]) <= 0:
				attacker["fainted"] = true
		for bmsg in _try_berry(defender, String(mv.get("category", ""))):
			log.append(String(bmsg))
		if String(mv.get("effect", "")) == "DRAIN":
			var back: int = maxi(1, int(dealt / 2))
			_set_hp(attacker, mini(int(attacker["max_hp"]), int(attacker["hp"]) + back))
			log.append("%s 吸取了体力。" % attacker["name"])
		_type_on_item(attacker, mv)
		if int(defender["hp"]) <= 0:
			defender["fainted"] = true
			log.append("%s 倒下了！" % defender["name"])
			# 牵绊变身：亲手打倒对手后羁绊加深
			if _ab(attacker) == "牵绊变身":
				attacker["kos"] = int(attacker.get("kos", 0)) + 1
			# 清场地类招式即使把对手打倒也要生效
			if not eff_fs in ["RAPID_SPIN", "ICE_SPINNER"]:
				return

	# 魔术师：命中就顺走对手的携带物
	if bool(Data.ability_effect(_ab(attacker)).get("steal_on_hit", false)) and dealt > 0 \
			and String(attacker.get("held", "")) == "" and String(defender.get("held", "")) != "" \
			and not bool(Data.ability_effect(_ab(defender)).get("prevent_steal", false)):
		var m_item := String(defender["held"])
		defender["held"] = ""
		attacker["held"] = m_item
		log.append("%s 的魔术师拿走了 %s！" % [attacker["name"], Data.item_name(m_item)])
	# 毒锁链：必定中毒
	if bool(Data.ability_effect(_ab(attacker)).get("poison_always", false)) and dealt > 0 \
			and String(defender.get("status", "")) == "" and not bool(defender["fainted"]):
		defender["status"] = "psn"
		log.append("%s 中毒了！" % defender["name"])

	# 连击类招式：再补几下（每下按独立伤害算，命中判定略过）
	var hits := 1
	match String(mv.get("effect", "")):
		"TRIPLE_KICK":
			hits = 3
		"DOUBLE_HIT":
			hits = 2
	if bool(Data.ability_effect(_ab(attacker)).get("double_hit", false)) and int(mv.get("power", 0)) > 0:
		hits = maxi(hits, 2)
	if bool(Data.ability_effect(_ab(attacker)).get("always_max_hits", false)) and String(mv.get("effect", "")) in ["DOUBLE_HIT", "TRIPLE_KICK"]:
		hits = maxi(hits, 5)
	if hits > 1 and not bool(defender["fainted"]):
		for i in range(hits - 1):
			var extra_hit := int(damage(attacker, defender, mv)*repeat_scale)
			if extra_hit <= 0:
				break
			_set_hp(defender, maxi(0, int(defender["hp"]) - extra_hit))
			log.append("第 %d 下，对 %s 造成了 %d 点伤害。" % [i + 2, defender["name"], extra_hit])
			if int(defender["hp"]) <= 0:
				defender["fainted"] = true
				log.append("%s 倒下了！" % defender["name"])
				break

	_contact_ability_effect(attacker, defender, mv)
	_after_hit_passive(attacker, defender, mv, dealt)

	var extra := _apply_effect(attacker, defender, mv, dealt)
	if extra != "":
		log.append(extra)
	# 低血自动退场（跃跃欲逃、危险回避）
	_check_emergency_exit("a")
	_check_emergency_exit("b")

## 场地类招式落地：天气、场地、屏障、撒菱、重力
func _apply_field_move(side: String, defender: Dictionary, fr: Dictionary) -> void:
	var foe_side := "b" if side == "a" else "a"
	var text := ""
	match String(fr.get("kind", "")):
		"weather":
			text = field.set_weather(String(fr.get("weather", "")))
		"terrain":
			text = field.set_terrain(String(fr.get("terrain", "")))
		"gravity":
			text = field.set_gravity()
		"screen":
			text = field.set_screen(side, String(fr.get("screen", "")))
		"hazard":
			text = field.add_hazard(foe_side, String(fr.get("hazard", "")))
		"clear_screens":
			text = field.clear_screens(foe_side)
	if text != "":
		log.append(text)

## 超极巨专属招式的额外机制：能实现的当场结算，实现不了的当场说明
func _gmax_effect(attacker: Dictionary, defender: Dictionary, ge: Dictionary, dealt: int) -> String:
	var kind := String(ge.get("kind", ""))
	match kind:
		"status":
			return _try_status(defender, String(ge.get("status", "")))
		"status_any":
			var opts: Array = ge.get("opts", [])
			if opts.is_empty():
				return ""
			return _try_status(defender, String(opts[rng.randi_range(0, opts.size() - 1)]))
		"stat":
			var st2 := String(ge.get("stat", ""))
			var delta := int(ge.get("delta", -1))
			if st2 == "acc" or st2 == "eva":
				return "%s 的%s没有变化。" % [defender["name"], _stat_name(st2)]
			var cur2 := int(defender["stages"].get(st2, 0))
			if (delta < 0 and cur2 <= -6) or (delta > 0 and cur2 >= 6):
				return "%s 的%s已经到极限了。" % [defender["name"], _stat_name(st2)]
			defender["stages"][st2] = clampi(cur2 + delta, -6, 6)
			return "%s 的%s%s了！" % [defender["name"], _stat_name(st2), "下降" if delta < 0 else "上升"]
		"crit_up":
			attacker["crit_up"] = 2
			return "%s 变得容易击中要害了！" % attacker["name"]
		"heal":
			var frac := maxi(1, int(ge.get("frac", 2)))
			if int(attacker["hp"]) >= int(attacker["max_hp"]):
				return "%s 的体力已经是满的。" % attacker["name"]
			var before2: int = attacker["hp"]
			_set_hp(attacker, mini(int(attacker["max_hp"]), int(attacker["hp"]) + int(int(attacker["max_hp"]) / frac)))
			return "%s 回复了 %d 点体力。" % [attacker["name"], int(attacker["hp"]) - before2]
		"heal_status":
			if String(attacker.get("status", "")) == "":
				return ""
			var was := String(attacker["status"])
			attacker["status"] = ""
			attacker["status_turns"] = 0
			return "%s 的%s痊愈了！" % [attacker["name"], _status_text(attacker["name"], was).split(" ")[-1]]
		"residual":
			var turns := int(ge.get("turns", 4))
			defender["residual"] = {"turns": turns, "frac": maxi(1, int(ge.get("frac", 6)))}
			return "%s 被缠住了，会在 %d 回合内持续受伤！" % [defender["name"], turns]
		"shield":
			attacker["shield_turns"] = int(ge.get("turns", 5))
			return "%s 被极光护住了，接下来受到的伤害减半。" % attacker["name"]
		"pp_drain":
			var mv: Array = defender.get("moves", [])
			var pp: Array = defender.get("pp", [])
			var amt := int(ge.get("amount", 2))
			var hit := false
			for i in pp.size():
				if int(pp[i]) > 0:
					pp[i] = maxi(0, int(pp[i]) - amt)
					hit = true
			if hit:
				return "%s 的招式 PP 被削减了。" % defender["name"]
			return ""
		"gravity":
			return field.set_gravity()
		"hazard":
			return field.add_hazard("b" if _side_of(attacker) == "a" else "a", String(ge.get("hazard", "")))
		"weather":
			return field.set_weather(String(ge.get("weather", "")))
		"clear_screens":
			return field.clear_screens("b" if _side_of(attacker) == "a" else "a")
		"berry_restore":
			if String(attacker.get("berry", "")) == "":
				attacker["berry"] = String(attacker.get("eaten_berry", "oran"))
				return "%s 的树果恢复了！" % attacker["name"]
			return ""
		"no_repeat":
			defender["no_repeat"] = int(ge.get("turns", 2))
			return "%s 暂时无法连续使用同一招式。" % defender["name"]
		"ignore_ability":
			attacker["ignore_ability"] = true
			return "%s 无视了对手的特性。" % attacker["name"]
		"noop":
			return ""
	return ""

## 统一的异常状态施加入口（带免疫判断）
func _try_status(defender: Dictionary, st: String) -> String:
	if st == "":
		return ""
	if int(defender.get("sub_hp", 0)) > 0:
		return "%s 的替身挡下了状态变化。" % defender["name"]
	if field.blocks_status(st) and st in ["psn", "tox", "par", "brn", "slp", "frz"]:
		return "场地保护了 %s，状态没有生效。" % defender["name"]
	if String(defender.get("status", "")) != "":
		return "%s 已经中了状态，没有效果。" % defender["name"]
	if st in ["cfu", "inf"]:
		defender["status"] = st
		defender["status_turns"] = rng.randi_range(2, 4)
		return "%s 陷入了%s状态！" % [defender["name"], "混乱" if st == "cfu" else "着迷"]
	if _status_immune(st, String(defender["types"][0] if not defender["types"].is_empty() else ""),
			defender["types"], _ab(defender)):
		return "对 %s 没有效果……" % defender["name"]
	defender["status"] = st
	defender["status_turns"] = rng.randi_range(1, 3) if st == "slp" else 0
	# 同步：把状态弹回给对面
	if bool(Data.ability_effect(_ab(defender)).get("status_reflect", false)):
		var foe4: Dictionary = cur_b() if defender == cur_a() else cur_a()
		if String(foe4.get("status", "")) == "" and not bool(foe4.get("fainted", false)):
			foe4["status"] = st
			foe4["status_turns"] = int(defender["status_turns"])
			return "%s！%s 的同步把%s也传染了回去。" % [_status_text(String(defender["name"]), st),
				defender["name"], _status_name(st)]
	return _status_text(String(defender["name"]), st)

## 极巨化后的招式：属性不变，威力按档换算；超极巨专属招式优先
func _max_move_data(c: Dictionary, base: Dictionary) -> Dictionary:
	var ty := String(base.get("type", "normal"))
	var sp: Dictionary = Data.species_of(int(c.get("species_id", 0)))
	var key := String(sp.get("key", ""))
	# 超极巨形态用的是形态自己的键（CHARIZARD_GMAX）
	var form_key := String(c.get("form", ""))
	var gid := Data.gmax_move_for(form_key, ty)
	if gid <= 0:
		gid = Data.gmax_move_for(key, ty)
	var mid := gid if gid > 0 else Data.max_move_for_type(ty)
	var out: Dictionary = (Data.move_of(mid) as Dictionary).duplicate(true)
	if out.is_empty():
		return base
	out["power"] = Data.max_power(int(base.get("power", 60)), ty)
	out["type"] = ty
	out["category"] = String(base.get("category", "physical"))
	# 超极巨专属招式的额外机制跟着招式一起带出去
	var eff := Data.gmax_effect(mid)
	if not eff.is_empty():
		out["gmax_effect"] = eff
	return out

## 无技能可用时的挣扎
func _struggle(side: String) -> void:
	var attacker: Dictionary = cur_a() if side == "a" else cur_b()
	var defender: Dictionary = cur_b() if side == "a" else cur_a()
	if _blocked_by_status(attacker):
		return
	log.append("%s 没有技能可用了，使出了挣扎！" % attacker["name"])
	var lvl := float(attacker["level"])
	var a := float(attacker["stats"]["atk"])
	var d := maxf(1.0, float(defender["stats"]["def"]))
	var dmg: int = maxi(1, int(((2.0 * lvl / 5.0 + 2.0) * 50.0 * a / d) / 50.0 + 2.0))
	_set_hp(defender, maxi(0, int(defender["hp"]) - dmg))
	log.append("对 %s 造成了 %d 点伤害。" % [defender["name"], dmg])
	var back: int = maxi(1, int(int(attacker["max_hp"]) / 4.0))
	_set_hp(attacker, maxi(0, int(attacker["hp"]) - back))
	log.append("%s 受到了反作用力伤害。" % attacker["name"])
	if int(defender["hp"]) <= 0:
		defender["fainted"] = true
		log.append("%s 倒下了！" % defender["name"])
	if int(attacker["hp"]) <= 0:
		attacker["fainted"] = true
		log.append("%s 倒下了！" % attacker["name"])

## 接力棒用：找一只不是自己、还活着的同伴
func _next_alive(side: String, exclude: int) -> int:
	var team: Array = team_a if side == "a" else team_b
	for i in range(team.size()):
		if i != exclude and not team[i]["fainted"] and int(team[i]["hp"]) > 0:
			return i
	return -1

func _do_switch(side: String, index: int, forced: bool = false) -> void:
	var team: Array = team_a if side == "a" else team_b
	if index < 0 or index >= team.size() or team[index]["fainted"] or int(team[index]["hp"]) <= 0:
		return
	# 被束缚时换不了人（被吹飞、击退除外）
	var stuck: Dictionary = cur_a() if side == "a" else cur_b()
	if not forced and bool(stuck.get("trapped", false)):
		log.append("%s 被束缚住，换不了人！" % stuck["name"])
		return
	# 换下去的那只：自然回复解异常、再生力回血
	var old: Dictionary = cur_a() if side == "a" else cur_b()
	if not bool(old.get("fainted", false)):
		var oe: Dictionary = Data.ability_effect(_ab(old))
		if (bool(oe.get("recover_on_switch", false)) or bool(oe.get("cure_on_switch", false))) \
				and String(old.get("status", "")) != "":
			old["status"] = ""
			old["status_turns"] = 0
			log.append("%s 靠%s解除了异常状态。" % [old["name"], _ab(old)])
		var sh := float(oe.get("switch_heal", 0.0))
		if sh > 0.0 and int(old["hp"]) < int(old["max_hp"]):
			var hl: int = maxi(1, int(int(old["max_hp"]) * sh))
			var b0 := int(old["hp"])
			_set_hp(old, mini(int(old["max_hp"]), int(old["hp"]) + hl))
			log.append("%s 靠%s回复了 %d 点体力。" % [old["name"], _ab(old), int(old["hp"]) - b0])
		# 全能变身：换下场时变成全能形态，再上场就是英雄姿态
		if bool(oe.get("form_on_switch_out", false)) and int(old.get("species_id", 0)) == 964 \
				and String(old.get("form", "")) != "PALAFIN_HERO":
			switch_form(side, "PALAFIN_HERO", "%s 换下场后变成了全能形态！" % old["name"])
	old["dire_hit"] = false
	# X items affect the current stint in battle, like other temporary stat stages.
	for stat in old["stages"]:
		old["stages"][stat] = 0
	old["trapped"] = false
	if side == "a":
		active_a = index
	else:
		active_b = index
	health_changed.emit(log.size(), side, index, team[index])
	log.append("%s 上场了！" % team[index]["name"])
	_apply_hazards(side, team[index])
	_on_send_out(side)

func _check_end() -> void:
	var a_alive := _any_alive(team_a)
	var b_alive := _any_alive(team_b)
	if not a_alive or not b_alive:
		over = true
		if a_alive:
			winner = "a"
		elif b_alive:
			winner = "b"
		else:
			winner = "draw"
		return

	if cur_a()["fainted"]:
		active_a = _first_alive(team_a)
		health_changed.emit(log.size(), "a", active_a, cur_a())
		log.append("%s 上场了！" % cur_a().name)
		_on_send_out("a")
	if cur_b()["fainted"]:
		active_b = _first_alive(team_b)
		health_changed.emit(log.size(), "b", active_b, cur_b())
		log.append("%s 上场了！" % cur_b().name)
		_on_send_out("b")

func _any_alive(team: Array) -> bool:
	for c in team:
		if not c["fainted"]:
			return true
	return false

func _first_alive(team: Array) -> int:
	for i in team.size():
		if not team[i]["fainted"]:
			return i
	return 0
