extends RefCounted
## 野外遇敌：纯逻辑，不碰渲染。
## 每次踩进高草摇一次骰子，命中就从地区的遭遇表里按权重抽一只。
## 地区差异全部来自 region.json 的 encounters，内核不认识任何具体物种。

const DEFAULT_RATE := 0.12

## 这一步要不要遇敌。streak 是连续在高草里走的步数，走得越久越容易碰上。
static func should_encounter(rng: RandomNumberGenerator, rate: float, streak: int = 0) -> bool:
	var r := rate if rate > 0.0 else DEFAULT_RATE
	# 连续走再给一点点加成，避免「走了三十步什么都没有」
	r = minf(0.55, r * (1.0 + 0.03 * maxi(0, streak - 1)))
	return rng.randf() < r

## 从遭遇表里按权重抽一只；表为空返回 {} 表示这次不遇敌
static func roll(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for row in pool:
		if row is Dictionary:
			total += maxf(0.0, float(row.get("weight", 1)))
	if total <= 0.0:
		return {}
	var pick := rng.randf() * total
	var acc := 0.0
	for row in pool:
		if not (row is Dictionary):
			continue
		acc += maxf(0.0, float(row.get("weight", 1)))
		if pick <= acc:
			var sid := int(row.get("species", 0))
			if sid <= 0 or Data.species_of(sid).is_empty():
				continue
			var lo := int(row.get("min", 2))
			var hi := int(row.get("max", lo))
			var lv := rng.randi_range(mini(lo, hi), maxi(lo, hi))
			return {"species": sid, "level": clampi(lv, 1, 100)}
	return {}

## 给一只配招：按等级从种族学习表里挑，取到这一级为止学会的最后四招。
## 以前是固定写死的两招，全图鉴的宝可梦打起来手感都一样。
static func moves_for(species_id: int, level: int = 5, learnset: Array = []) -> Array:
	var sp: Dictionary = Data.species_of(species_id)
	var out: Array = []
	var learn = sp.get("learnset", []) if learnset.is_empty() else learnset
	if learn is Array:
		for row in learn:
			if not (row is Array) or (row as Array).size() < 2:
				continue
			if int(row[0]) > level:
				continue
			var mid := int(row[1])
			if Data.moves.has(mid) and not out.has(mid):
				out.append(mid)
	if out.is_empty():
		for mid2 in sp.get("moves", []):
			if Data.moves.has(int(mid2)):
				out.append(int(mid2))
	if out.is_empty() and Data.moves.has(33):
		out.append(33)
	# 最多四招，取最后学会的四个（越靠后越强）
	if out.size() > 4:
		out = out.slice(out.size() - 4)
	return out
