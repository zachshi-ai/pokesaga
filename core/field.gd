extends RefCounted
## 场地状态：天气、场地、屏障、撒菱、重力。
##
## 这些东西以前是散在招式里各自模拟的（甚至干脆没做），现在统一放这里：
##   - 谁设置的、剩几回合、对伤害有没有加成，全由 Field 说了算
##   - battle.gd 只负责问「这一下打多少」「回合末掉不掉血」
## 这样加新天气/新场地只要改这个文件，不用再往战斗内核里塞 if。

const WEATHER_TURNS := 5
const TERRAIN_TURNS := 5
const SCREEN_TURNS := 5
const GRAVITY_TURNS := 5

var weather := ""          # sun / rain / sandstorm / snow / fog
var weather_turns := 0
var terrain := ""          # electric / grassy / misty / psychic
var terrain_turns := 0
var gravity_turns := 0
var trick_room := false
var trick_room_turns := 0
var wish := {"a": 0, "b": 0}
# 屏障：side -> {"reflect": turns, "light_screen": turns, "aurora_veil": turns}
var screens := {"a": {}, "b": {}}
# 撒菱：side -> {"spikes": 层数, "stealth_rock": bool, "toxic_spikes": 层数, "sticky_web": bool}
var hazards := {
	"a": {"spikes": 0, "stealth_rock": false, "steel_rocks": false, "toxic_spikes": 0, "sticky_web": false},
	"b": {"spikes": 0, "stealth_rock": false, "steel_rocks": false, "toxic_spikes": 0, "sticky_web": false},
}

func reset() -> void:
	weather = ""
	weather_turns = 0
	terrain = ""
	terrain_turns = 0
	gravity_turns = 0
	trick_room = false
	trick_room_turns = 0
	wish = {"a": 0, "b": 0}
	screens = {"a": {}, "b": {}}
	hazards = {
		"a": {"spikes": 0, "stealth_rock": false, "steel_rocks": false, "toxic_spikes": 0, "sticky_web": false},
		"b": {"spikes": 0, "stealth_rock": false, "steel_rocks": false, "toxic_spikes": 0, "sticky_web": false},
	}

# ---------------- 设置 ----------------

func set_weather(kind: String, turns := WEATHER_TURNS) -> String:
	if kind == "":
		weather = ""
		weather_turns = 0
		return "天气恢复了正常。"
	weather = kind
	weather_turns = turns
	return "天气变成了%s！" % weather_name(kind)

func set_terrain(kind: String, turns := TERRAIN_TURNS) -> String:
	if kind == "":
		terrain = ""
		terrain_turns = 0
		return "场地恢复了正常。"
	terrain = kind
	terrain_turns = turns
	return "脚下的地面变成了%s！" % terrain_name(kind)

func set_wish(side: String) -> void:
	wish[side] = 2

## 许愿：两回合后给这一边回复一半体力
func tick_wish(sides: Array) -> Array:
	var out: Array = []
	for i in range(2):
		var sd: String = "a" if i == 0 else "b"
		if int(wish.get(sd, 0)) > 0:
			wish[sd] = int(wish[sd]) - 1
			if int(wish[sd]) == 0:
				var c: Dictionary = sides[i]
				if not c.get("fainted", false):
					var heal: int = maxi(1, int(int(c["max_hp"]) / 2.0))
					c["hp"] = mini(int(c["max_hp"]), int(c["hp"]) + heal)
					out.append("许下的愿望实现了，%s 回复了体力。" % c.get("name", "?"))
	return out

func set_gravity(turns := GRAVITY_TURNS) -> String:
	gravity_turns = turns
	return "重力变得异常了！"

func set_screen(side: String, kind: String, turns := SCREEN_TURNS) -> String:
	var t := clampi(int(screens.get(side, {}).get(kind, 0)), 0, 99)
	screens[side][kind] = maxi(t, turns)
	match kind:
		"reflect":
			return "反射壁保护住了这一边！"
		"light_screen":
			return "光墙保护住了这一边！"
		"tailwind":
			return "顺风刮起来了！"
		"aurora_veil":
			return "极光幕保护住了这一边！"
	return ""

func add_hazard(side: String, kind: String) -> String:
	var h: Dictionary = hazards[side]
	match kind:
		"spikes":
			h["spikes"] = mini(3, int(h.get("spikes", 0)) + 1)
			return "尖刺撒在了对方脚下！"
		"toxic_spikes":
			h["toxic_spikes"] = mini(2, int(h.get("toxic_spikes", 0)) + 1)
			return "毒菱撒在了对方脚下！"
		"stealth_rock":
			h["stealth_rock"] = true
			return "隐形岩浮在了对方周围！"
		"steel_rocks":
			h["steel_rocks"] = true
			return "锐利钢刺浮在了对方周围！"
		"sticky_web":
			h["sticky_web"] = true
			return "黏网铺在了对方脚下！"
	return ""

func clear_screens(side: String) -> String:
	var had: bool = not (screens[side] as Dictionary).is_empty()
	screens[side] = {}
	return "对方的屏障被清除了！" if had else ""

# ---------------- 查询 ----------------

func weather_name(kind: String) -> String:
	match kind:
		"sun": return "大晴天"
		"rain": return "下雨"
		"sandstorm": return "沙暴"
		"snow": return "下雪"
		"fog": return "浓雾"
	return kind

func terrain_name(kind: String) -> String:
	match kind:
		"electric": return "电气场地"
		"grassy": return "青草场地"
		"misty": return "薄雾场地"
		"psychic": return "精神场地"
	return kind

func has_screen(side: String, kind: String) -> bool:
	return int((screens.get(side, {}) as Dictionary).get(kind, 0)) > 0

## 伤害倍率：天气、场地、屏障。attacker_side / defender_side 是 "a" / "b"
func damage_mod(atk_type: String, category: String, attacker_side: String, defender_side: String, grounded := true) -> float:
	var mult := 1.0

	# 天气
	match weather:
		"sun":
			if atk_type == "fire":
				mult *= 1.5
			elif atk_type == "water":
				mult *= 0.5
		"rain":
			if atk_type == "water":
				mult *= 1.5
			elif atk_type == "fire":
				mult *= 0.5
	# 场地只对站在地面上的有效
	if grounded:
		match terrain:
			"electric":
				if atk_type == "electric":
					mult *= 1.3
			"grassy":
				if atk_type == "grass":
					mult *= 1.3
			"psychic":
				if atk_type == "psychic":
					mult *= 1.3
			"misty":
				if atk_type == "dragon":
					mult *= 0.5

	# 屏障：物理被反射壁挡，特殊被光墙挡，极光幕两者都挡
	var sc: Dictionary = screens.get(defender_side, {})
	if int(sc.get("aurora_veil", 0)) > 0:
		mult *= 0.5
	elif category == "physical" and int(sc.get("reflect", 0)) > 0:
		mult *= 0.5
	elif category != "physical" and int(sc.get("light_screen", 0)) > 0:
		mult *= 0.5

	return mult

## 命中率倍率：浓雾会降低命中
func accuracy_mod() -> float:
	return 0.6 if weather == "fog" else 1.0

## 重力期间地面招式能打到飞行系与漂浮
func gravity_active() -> bool:
	return gravity_turns > 0

## 入场时踩到的钉子伤害与状态：返回 {"damage": int, "status": String, "text": [...]}
func on_switch_in(side: String, mon: Dictionary, rock_eff: float) -> Dictionary:
	var h: Dictionary = hazards.get(side, {})
	var out := {"damage": 0, "status": "", "stages": {}, "text": []}
	var max_hp: int = maxi(1, int(mon.get("max_hp", 1)))
	var grounded := _grounded(mon)

	if grounded and int(h.get("spikes", 0)) > 0:
		var layers := int(h["spikes"])
		var fr_list: Array = [0.125, 0.1667, 0.25]
		var frac: float = float(fr_list[clampi(layers - 1, 0, 2)])
		var dmg: int = maxi(1, int(max_hp * frac))
		out["damage"] = int(out["damage"]) + dmg
		out["text"].append("%s 被尖刺扎伤了！" % mon.get("name", "?"))

	if bool(h.get("stealth_rock", false)):
		var dmg2: int = maxi(1, int(max_hp * 0.125 * maxf(0.25, rock_eff)))
		out["damage"] = int(out["damage"]) + dmg2
		out["text"].append("%s 被隐形岩割伤了！" % mon.get("name", "?"))

	if bool(h.get("steel_rocks", false)):
		var ttable: Dictionary = Data.types.get("steel", {})
		var steel_eff: float = 1.0
		for t2 in mon.get("types", []):
			steel_eff *= float(ttable.get(String(t2), 1.0))
		var dmg3: int = maxi(1, int(max_hp * 0.125 * maxf(0.25, steel_eff)))
		out["damage"] = int(out["damage"]) + dmg3
		out["text"].append("%s 被钢刺扎伤了！" % mon.get("name", "?"))

	if grounded and int(h.get("toxic_spikes", 0)) > 0 and String(mon.get("status", "")) == "":
		var st: String = "tox" if int(h["toxic_spikes"]) >= 2 else "psn"
		if not (mon.get("types", []) as Array).has("poison") and not (mon.get("types", []) as Array).has("steel"):
			out["status"] = st
			out["text"].append("%s 踩到了毒菱！" % mon.get("name", "?"))

	if grounded and bool(h.get("sticky_web", false)):
		out["stages"]["spe"] = -1
		out["text"].append("%s 被黏网缠住了！" % mon.get("name", "?"))

	return out

## 回合末结算：天气持续伤害、青草场地回血、回合数递减
func end_turn(sides: Array) -> Array:
	var out: Array = []

	for c in sides:
		if c.get("fainted", false) or int(c.get("hp", 0)) <= 0:
			continue
		var types: Array = c.get("types", [])
		match weather:
			"sandstorm":
				if not (types.has("rock") or types.has("ground") or types.has("steel")) \
						and not _weather_immune(String(c.get("ability_name", ""))) and (c.get("held","")!="SAFETY_GOGGLES" or c.get("ability_name","")=="笨拙"):
					var dmg: int = maxi(1, int(int(c["max_hp"]) / 16.0))
					c["hp"] = maxi(0, int(c["hp"]) - dmg)
					out.append("%s 被沙暴刮伤了。" % c.get("name", "?"))
			"snow":
				pass
		# 青草场地：站在地上的每回合回 1/16
		if terrain == "grassy" and _grounded(c):
			if int(c.get("hp", 0)) < int(c.get("max_hp", 1)):
				var heal: int = maxi(1, int(int(c["max_hp"]) / 16.0))
				c["hp"] = mini(int(c["max_hp"]), int(c["hp"]) + heal)
				out.append("%s 借助青草场地回复了体力。" % c.get("name", "?"))
		if int(c.get("hp", 0)) <= 0:
			c["fainted"] = true
			out.append("%s 倒下了！" % c.get("name", "?"))

	# 回合数递减
	if weather_turns > 0:
		weather_turns -= 1
		if weather_turns == 0 and weather != "":
			out.append("%s 停了。" % weather_name(weather))
			weather = ""
	if terrain_turns > 0:
		terrain_turns -= 1
		if terrain_turns == 0 and terrain != "":
			out.append("%s 消失了。" % terrain_name(terrain))
			terrain = ""
	if gravity_turns > 0:
		gravity_turns -= 1
		if gravity_turns == 0:
			out.append("重力恢复了正常。")
	if trick_room_turns > 0:
		trick_room_turns -= 1
		if trick_room_turns == 0:
			trick_room = false
			out.append("戏法空间解除了。")
	for side in ["a", "b"]:
		var sc: Dictionary = screens[side]
		for k in sc.keys():
			if int(sc[k]) > 0:
				sc[k] = int(sc[k]) - 1
			if int(sc[k]) <= 0:
				sc.erase(k)
				out.append("%s 的屏障消失了。" % side)
	return out

## 薄雾场地：不让上异常状态；电气场地：不会睡着
func blocks_status(status: String) -> bool:
	if terrain == "misty":
		return true
	if terrain == "electric" and status == "slp":
		return true
	return false

## 精神场地：先制招式打不出来
func blocks_priority(move_priority: int, attacker_grounded: bool) -> bool:
	return terrain == "psychic" and move_priority > 0 and attacker_grounded

## 免疫天气伤害的特性：沙隐/沙之力/拨沙/雪隐/冰冻之躯/拨雪/防尘
func _weather_immune(ability: String) -> bool:
	return ability in ["沙隐", "沙之力", "拨沙", "雪隐", "冰冻之躯", "拨雪", "防尘"]

func _grounded(mon: Dictionary) -> bool:
	var types: Array = mon.get("types", [])
	if types.has("flying"):
		return false
	if String(mon.get("ability_name", "")) == "漂浮":
		return false
	if gravity_turns > 0:
		return true
	return true
