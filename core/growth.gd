extends RefCounted
## 成长：等级经验曲线 + 升级 + 进化判定。
## 纯计算，不碰界面；曲线按 species.growth 字段选，缺省 medium_fast。

const MAX_LEVEL := 100

## 到达某等级需要的累计经验
static func exp_for_level(level: int, growth: String = "medium_fast") -> int:
	var lv := clampi(level, 1, MAX_LEVEL)
	if lv <= 1:
		return 0
	var n := float(lv)
	match growth:
		"slow":
			return int(5.0 * pow(n, 3) / 4.0)
		"medium_slow":
			return int(maxf(0.0, 1.2 * pow(n, 3) - 15.0 * n * n + 100.0 * n - 140.0))
		"fast":
			return int(4.0 * pow(n, 3) / 5.0)
		"slow_then_fast":
			return int(5.0 * pow(n, 3) / 4.0)
		_:
			return int(pow(n, 3))

## 这一级占多少经验（用来算进度条）
static func level_span(level: int, growth: String = "medium_fast") -> int:
	var lo := exp_for_level(level, growth)
	var hi := exp_for_level(level + 1, growth)
	return maxi(1, hi - lo)

static func progress(exp: int, level: int, growth: String = "medium_fast") -> float:
	var lo := exp_for_level(level, growth)
	var span := level_span(level, growth)
	return clampf(float(exp - lo) / float(span), 0.0, 1.0)

## 打赢一只给多少经验：等级差越大给得越少，但不至于为零
static func gain(defeated_level: int, base_exp: int = 60, my_level: int = 5) -> int:
	var lv := maxi(1, defeated_level)
	var raw := int(base_exp * lv / 7.0 + 6.0)
	var diff := lv - maxi(1, my_level)
	var mult := clampf(1.0 + 0.15 * diff, 0.35, 1.8)
	return maxi(1, int(raw * mult))

## 加经验，返回升了几级
static func add_exp(mon: Dictionary, amount: int) -> int:
	if mon.is_empty() or amount <= 0:
		return 0
	var sp: Dictionary = Data.species_of(int(mon.get("species_id", 1)))
	var growth := String(sp.get("growth", "medium_fast"))
	var lv := int(mon.get("level", 1))
	var exp := int(mon.get("exp", exp_for_level(lv, growth))) + amount
	var gained := 0
	while lv < MAX_LEVEL and exp >= exp_for_level(lv + 1, growth):
		lv += 1
		gained += 1
	mon["exp"] = exp
	if gained > 0:
		mon["level"] = lv
		for i in gained:
			level_friendship(mon)
	return gained

static func level_friendship(mon: Dictionary) -> void:
	var value := int(mon.get("friendship", 200))
	var bonus := 5 if value < 100 else (3 if value < 200 else 2)
	if str(mon.get("held", "")) == "SOOTHE_BELL":
		bonus = bonus * 3 / 2
	mon["friendship"] = mini(255, value + bonus)

static func award_effort(mon: Dictionary, defeated_species: int) -> void:
	var gains: Dictionary = Data.training_values.get(str(defeated_species), {}).get("effort", {})
	var effort: Dictionary = mon.get("effort", {})
	var room := 510
	for n in effort.values(): room -= int(n)
	for stat in gains:
		var earned := int(gains[stat]) * (2 if str(mon.get("held", "")) == "MACHO_BRACE" else 1)
		var old := int(effort.get(stat, 0))
		var add := maxi(0, mini(earned, mini(room, 252 - old)))
		effort[stat] = old + add
		room -= add
	mon["effort"] = effort

## 升级时新学会的招式：从 from_lv+1 到 to_lv 这一段的升级招式表
static func moves_learned(mon: Dictionary, from_lv: int, to_lv: int) -> Array:
	var out: Array = []
	if mon.is_empty():
		return out
	var sp: Dictionary = Data.species_of(int(mon.get("species_id", 0)))
	var learn = sp.get("learnset", [])
	if not (learn is Array):
		return out
	for row in learn:
		if not (row is Array) or (row as Array).size() < 2:
			continue
		var lv := int(row[0])
		if lv > from_lv and lv <= to_lv:
			var mid := int(row[1])
			if Data.moves.has(mid) and not out.has(mid):
				out.append(mid)
	return out

## 该不该进化：返回 {to, form}，没得进化返回空字典。
## 形态要跟着走：阿罗拉小拉达进化成阿罗拉拉达，不是普通拉达。
static func evolution_of(mon: Dictionary) -> Dictionary:
	if mon.is_empty():
		return {}
	var sid := int(mon.get("species_id", 0))
	var form_key := String(mon.get("form", ""))
	var lv := int(mon.get("level", 1))

	# 先看形态自己的进化链
	if form_key != "":
		var f: Dictionary = Data.form_of(sid, form_key)
		var fe = f.get("evolves", [])
		if fe is Array:
			for e in fe:
				var r := _match_evo(e, lv)
				if not r.is_empty():
					return r
		# 形态没有自己的进化链，说明这只不进化（比如各种帽子皮卡丘）
		return {}

	var sp: Dictionary = Data.species_of(sid)
	var list = sp.get("evolves", [])
	if list is Array and not (list as Array).is_empty():
		for e in list:
			var r2 := _match_evo(e, lv)
			if not r2.is_empty():
				return r2
		return {}

	# 老字段兜底
	var to := int(sp.get("evolves_to", 0))
	var at := int(sp.get("evolves_at", 0))
	if to > 0 and at > 0 and lv >= at and not Data.species_of(to).is_empty():
		return {"to": to, "form": ""}
	return {}

## 单条进化条件是否满足：现在只做等级进化，道具进化留给后面的道具系统
static func _match_evo(e: Variant, lv: int) -> Dictionary:
	if not (e is Dictionary):
		return {}
	var row: Dictionary = e
	if String(row.get("how", "")) != "level":
		return {}
	var at := int(row.get("at", 0))
	if at <= 0 or lv < at:
		return {}
	var to := int(row.get("to", 0))
	if to <= 0 or Data.species_of(to).is_empty():
		return {}
	var form := String(row.get("form", ""))
	if form != "" and Data.form_of(to, form).is_empty():
		return {}
	return {"to": to, "form": form}

## Dawn Stone evolutions depend on the individual's sex. Earlier saves did not store it.
static func evolution_sex(mon: Dictionary) -> String:
	var sid := int(mon.get("species_id", 0))
	if sid not in [280, 281, 282, 475, 361, 362, 478]:
		return ""
	if sid == 475:
		mon["sex"] = "male"
	elif sid == 478:
		mon["sex"] = "female"
	elif str(mon.get("sex", "")) not in ["male", "female"]:
		var legacy_identity := "%s|%s|%s|%s" % [sid, mon.get("level", 1), mon.get("moves", []), mon.get("nature", "")]
		mon["sex"] = "female" if legacy_identity.hash() % 2 == 0 else "male"
	return str(mon["sex"])

## 这只靠道具能进化成什么：返回 [{item, to, form}]，界面拿去提示「需要火之石」
static func item_evolutions(mon: Dictionary) -> Array:
	var out: Array = []
	if mon.is_empty():
		return out
	var sid := int(mon.get("species_id", 0))
	var form_key := String(mon.get("form", ""))
	var list: Array = []
	if form_key != "":
		var f: Dictionary = Data.form_of(sid, form_key)
		var fe = f.get("evolves", [])
		if fe is Array:
			list = fe
	else:
		var sp: Dictionary = Data.species_of(sid)
		var se = sp.get("evolves", [])
		if se is Array:
			list = se
	for e in list:
		if not (e is Dictionary):
			continue
		var row: Dictionary = e
		if String(row.get("how", "")) != "item":
			continue
		if row.has("sex") and str(row.sex) != evolution_sex(mon):
			continue
		var to := int(row.get("to", 0))
		if to <= 0 or Data.species_of(to).is_empty():
			continue
		var form := String(row.get("form", ""))
		if form != "" and Data.form_of(to, form).is_empty():
			continue
		out.append({"item": String(row.get("item", "")), "to": to, "form": form})
	return out

static func evolution_for_item(mon: Dictionary, item_key: String) -> Dictionary:
	for rule in item_evolutions(mon):
		if str(rule.item) == item_key:
			return rule
	return {}

## 兼容老调用：只关心进化成哪个图鉴号
static func evolution_target(mon: Dictionary) -> int:
	return int(evolution_of(mon).get("to", 0))
