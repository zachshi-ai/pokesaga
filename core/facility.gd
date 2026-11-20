extends RefCounted
## 对战塔：连续挑战的规则都在这里，纯逻辑。
## 进塔一律 Lv50 平级对战（不消耗队伍真实血量），连胜越高对手越硬。

const LEVEL := 50
const POOL := [149, 143, 130, 6, 9, 3, 92, 95, 67, 75, 64, 134, 148]

## 对手：连胜越高，越容易抽到高种族值的，且配四招
static func make_opponent(streak: int, rng: RandomNumberGenerator) -> Dictionary:
	var tier := clampi(streak / 3, 0, 2)
	var pick: int = int(POOL[rng.randi_range(0, POOL.size() - 1)])
	if tier >= 1:
		# 高分池：快龙 / 卡比兽 / 暴鲤龙 / 三只御三家
		var elite := [149, 143, 130, 6, 9, 3]
		pick = int(elite[rng.randi_range(0, elite.size() - 1)])
	if tier >= 2:
		var top := [149, 143, 130]
		pick = int(top[rng.randi_range(0, top.size() - 1)])
	var moves: Array = []
	var sp: Dictionary = Data.species_of(pick)
	for mid in sp.get("moves", [33]):
		moves.append(int(mid))
	if moves.is_empty():
		moves = [33]
	# 等级随连胜小幅上浮，封顶 60，避免纯靠等级碾压
	var lv := LEVEL + mini(10, streak)
	return _combatant(pick, lv, moves)

static func _combatant(species_id: int, level: int, moves: Array) -> Dictionary:
	var sp: Dictionary = Data.species_of(species_id)
	var base: Dictionary = sp.get("base", {})
	var mx := int((2 * int(base.get("hp", 1)) + 31) * level / 100.0) + level + 10
	var stats := {}
	for k in ["atk", "def", "spa", "spd", "spe"]:
		stats[k] = int((2 * int(base.get(k, 1)) + 31) * level / 100.0) + 5
	var pp: Array = []
	for mid in moves:
		pp.append(int((Data.move_of(int(mid)) as Dictionary).get("pp", 10)))
	return {
		"species_id": species_id,
		"name": String(sp.get("name", "?")),
		"types": sp.get("types", []),
		"level": level,
		"max_hp": mx,
		"hp": mx,
		"stats": stats,
		"moves": moves,
		"pp": pp,
		"stages": {"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0},
		"fainted": false,
	}

## 玩家的塔内队伍：复制存档队伍并统一到 Lv50，不改存档
static func tower_team(party: Array) -> Array:
	var out: Array = []
	for m in party:
		if not (m is Dictionary) or (m as Dictionary).is_empty():
			continue
		var mon: Dictionary = (m as Dictionary).duplicate(true)
		var sid := int(mon.get("species_id", 0))
		if Data.species_of(sid).is_empty():
			continue
		var moves: Array = []
		for mid in mon.get("moves", []):
			if int(mid) > 0:
				moves.append(int(mid))
		if moves.is_empty():
			moves = [33]
		out.append(_combatant(sid, LEVEL, moves))
		if out.size() >= 6:
			break
	if out.is_empty():
		out.append(_combatant(25, LEVEL, [84, 33]))
	return out

## 连胜奖金：第 n 场给 200 + n*120
static func prize(streak: int) -> int:
	return 200 + maxi(0, streak) * 120
