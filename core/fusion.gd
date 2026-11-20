extends RefCounted

const PartyScript := preload("res://core/party.gd")
## 融合系统：宝可梦中心里的合体 / 分离 / 洛托姆家电切换，纯逻辑。
## 合体在原版是一次性的、不可逆；这里做成可逆——分离后另一只原样回来，方便试。

## 合体配方：base 留场，part 被吸进去
const RECIPES := [
	{"base": 646, "part": 643, "form": "KYUREM_WHITE", "label": "焰白酋雷姆"},
	{"base": 646, "part": 644, "form": "KYUREM_BLACK", "label": "暗黑酋雷姆"},
	{"base": 800, "part": 791, "form": "NECROZMA_DUSK_MANE", "label": "奈克洛兹玛（黄昏之鬃）"},
	{"base": 800, "part": 792, "form": "NECROZMA_DAWN_WINGS", "label": "奈克洛兹玛（拂晓之翼）"},
]

## 洛托姆的家电：宝可梦中心免费换，不占携带道具
const ROTOM := 479
const ROTOM_FORMS := [
	{"key": "", "label": "普通形态"},
	{"key": "ROTOM_HEAT", "label": "加热（电/火）"},
	{"key": "ROTOM_WASH", "label": "清洗（电/水）"},
	{"key": "ROTOM_FROST", "label": "结冰（电/冰）"},
	{"key": "ROTOM_FAN", "label": "旋转（电/飞行）"},
	{"key": "ROTOM_MOW", "label": "切割（电/草）"},
]

## 能合的成本：队伍里 base 与 part 都在，且 base 还没合过
static func options(party: Array) -> Array:
	var out: Array = []
	for i in party.size():
		var m: Variant = party[i]
		if not (m is Dictionary) or (m as Dictionary).is_empty():
			continue
		var mon: Dictionary = m
		var sid := int(mon.get("species_id", 0))
		if mon.get("fused_part", null) != null:
			continue
		for r in RECIPES:
			if int(r["base"]) != sid:
				continue
			var j := _index_of(party, int(r["part"]))
			if j < 0:
				continue
			out.append({
				"base": i, "part": j, "form": String(r["form"]), "label": String(r["label"]),
				"text": "%s + %s → %s" % [_nm(sid), _nm(int(r["part"])), String(r["label"])],
			})
	return out

## 已经合过的：可以拆开
static func unfusable(party: Array) -> Array:
	var out: Array = []
	for i in party.size():
		var m: Variant = party[i]
		if not (m is Dictionary) or (m as Dictionary).is_empty():
			continue
		var mon: Dictionary = m
		if mon.get("fused_part", null) == null:
			continue
		var part: Dictionary = mon["fused_part"]
		out.append({
			"base": i, "text": "%s ⇠ %s" % [String(mon.get("name", "?")), String(part.get("name", "?"))],
		})
	return out

## 合体：base 变形态，part 收进 base 里并从队伍移除
static func fuse(party: Array, base_idx: int, part_idx: int, form: String) -> String:
	if base_idx < 0 or base_idx >= party.size() or part_idx < 0 or part_idx >= party.size():
		return ""
	if base_idx == part_idx:
		return ""
	var base: Dictionary = party[base_idx]
	var part: Dictionary = party[part_idx]
	var f: Dictionary = Data.form_of(int(base.get("species_id", 0)), form)
	if f.is_empty():
		return ""
	var keep_hp := float(int(base.get("hp", 0))) / float(maxi(1, int(base.get("max_hp", 1))))
	base["form"] = form
	base["fused_part"] = (part as Dictionary).duplicate(true)
	base["name"] = "%s（%s）" % [String(Data.species_of(int(base.get("species_id", 0))).get("name", "?")),
		String(f.get("label", ""))]
	PartyScript.recalc(base, false)
	base["hp"] = clampi(int(round(keep_hp * float(int(base["max_hp"])))), 1, int(base["max_hp"]))
	base["hp_text"] = "%d/%d" % [int(base["hp"]), int(base["max_hp"])]
	party[base_idx] = base
	party.remove_at(part_idx)
	return String(base["name"])

## 分离：形态还原，被吸进去的那只回到队伍末尾
static func unfuse(party: Array, idx: int) -> String:
	if idx < 0 or idx >= party.size():
		return ""
	var mon: Dictionary = party[idx]
	if mon.get("fused_part", null) == null:
		return ""
	var filled := 0
	for m in party:
		if m is Dictionary and not (m as Dictionary).is_empty():
			filled += 1
	if filled >= PartyScript.MAX_SIZE:
		return "队伍满了，先腾一个位置。"
	var part: Dictionary = mon["fused_part"]
	mon.erase("fused_part")
	mon["form"] = ""
	var sp: Dictionary = Data.species_of(int(mon.get("species_id", 0)))
	mon["name"] = String(sp.get("name", mon.get("name", "?")))
	PartyScript.recalc(mon, false)
	party[idx] = mon
	party.append(part)
	return "%s 分离出了 %s" % [String(mon["name"]), String(part.get("name", "?"))]

## 靠携带道具定形态的清单：宝可梦中心的道具台按这个发
## rows: [道具 key, 适用图鉴号]
const ITEM_FORMS := [
	["ROTOM_HEAT", 479], ["ROTOM_WASH", 479], ["ROTOM_FROST", 479], ["ROTOM_FAN", 479], ["ROTOM_MOW", 479],
	["FLAME_PLATE", 493], ["SPLASH_PLATE", 493], ["ZAP_PLATE", 493], ["MEADOW_PLATE", 493],
	["ICICLE_PLATE", 493], ["FIST_PLATE", 493], ["TOXIC_PLATE", 493], ["EARTH_PLATE", 493],
	["SKY_PLATE", 493], ["MIND_PLATE", 493], ["INSECT_PLATE", 493], ["STONE_PLATE", 493],
	["SPOOKY_PLATE", 493], ["DRACO_PLATE", 493], ["DREAD_PLATE", 493], ["IRON_PLATE", 493],
	["PIXIE_PLATE", 493],
	["DOUSE_DRIVE", 649], ["SHOCK_DRIVE", 649], ["BURN_DRIVE", 649], ["CHILL_DRIVE", 649],
	["GRACIDEA", 492], ["RUSTED_SWORD", 888], ["RUSTED_SHIELD", 889],
	["GRISEOUS_ORB", 487], ["PRISON_BOTTLE", 720], ["REVEAL_GLASS", 641],
	["REVEAL_GLASS", 642], ["REVEAL_GLASS", 645],
]

## 道具对应的形态 key（空串表示回到普通形态）
static func form_for_item(sid: int, held: String) -> String:
	var plate := {"FLAME_PLATE": "FIRE", "SPLASH_PLATE": "WATER", "ZAP_PLATE": "ELECTRIC",
		"MEADOW_PLATE": "GRASS", "ICICLE_PLATE": "ICE", "FIST_PLATE": "FIGHTING",
		"TOXIC_PLATE": "POISON", "EARTH_PLATE": "GROUND", "SKY_PLATE": "FLYING",
		"MIND_PLATE": "PSYCHIC", "INSECT_PLATE": "BUG", "STONE_PLATE": "ROCK",
		"SPOOKY_PLATE": "GHOST", "DRACO_PLATE": "DRAGON", "DREAD_PLATE": "DARK",
		"IRON_PLATE": "STEEL", "PIXIE_PLATE": "FAIRY"}
	var drive := {"DOUSE_DRIVE": "DOUSE", "SHOCK_DRIVE": "SHOCK", "BURN_DRIVE": "BURN", "CHILL_DRIVE": "CHILL"}
	match sid:
		479:
			return held if held.begins_with("ROTOM_") else ""
		493:
			return "ARCEUS_" + String(plate[held]) if plate.has(held) else ""
		649:
			return "GENESECT_" + String(drive[held]) if drive.has(held) else ""
		492:
			return "SHAYMIN_SKY" if held == "GRACIDEA" else ""
		888:
			return "ZACIAN_CROWNED" if held == "RUSTED_SWORD" else ""
		889:
			return "ZAMAZENTA_CROWNED" if held == "RUSTED_SHIELD" else ""
		487:
			return "GIRATINA_ORIGIN" if held == "GRISEOUS_ORB" else ""
		720:
			return "HOOPA_UNBOUND" if held == "PRISON_BOTTLE" else ""
		641:
			return "TORNADUS_THERIAN" if held == "REVEAL_GLASS" else ""
		642:
			return "THUNDURUS_THERIAN" if held == "REVEAL_GLASS" else ""
		645:
			return "LANDORUS_THERIAN" if held == "REVEAL_GLASS" else ""
	return ""

## 队伍里带上道具就地变形态；返回提示文案，没变化返回空
static func apply_held_form(mon: Dictionary) -> String:
	var sid := int(mon.get("species_id", 0))
	var want := form_for_item(sid, String(mon.get("held", "")))
	if want == "" or want == String(mon.get("form", "")):
		return ""
	var f: Dictionary = Data.form_of(sid, want)
	if f.is_empty():
		return ""
	var ratio := float(int(mon.get("hp", 0))) / float(maxi(1, int(mon.get("max_hp", 1))))
	mon["form"] = want
	mon["types"] = f.get("types", mon.get("types", []))
	mon["name"] = "%s（%s）" % [String(Data.species_of(sid).get("name", "?")), String(f.get("label", ""))]
	PartyScript.recalc(mon, false)
	mon["hp"] = clampi(int(round(ratio * float(int(mon["max_hp"])))), 1, int(mon["max_hp"]))
	mon["hp_text"] = "%d/%d" % [int(mon["hp"]), int(mon["max_hp"])]
	return "%s 变成了%s形态！" % [String(Data.species_of(sid).get("name", "?")), String(f.get("label", ""))]

## 洛托姆换家电：只对判定为洛托姆的那只生效，体力按比例保留
static func rotom_slots(party: Array) -> Array:
	var out: Array = []
	for i in party.size():
		var m: Variant = party[i]
		if not (m is Dictionary) or (m as Dictionary).is_empty():
			continue
		if int((m as Dictionary).get("species_id", 0)) != ROTOM:
			continue
		out.append({"slot": i, "text": "%s 目前：%s" % [String((m as Dictionary).get("name", "?")), _rotom_label(String((m as Dictionary).get("form", "")))]})
	return out

static func set_rotom(party: Array, slot: int, form_key: String) -> String:
	if slot < 0 or slot >= party.size():
		return ""
	var mon: Dictionary = party[slot]
	if int(mon.get("species_id", 0)) != ROTOM:
		return ""
	if String(mon.get("form", "")) == form_key:
		return ""
	var ratio := float(int(mon.get("hp", 0))) / float(maxi(1, int(mon.get("max_hp", 1))))
	mon["form"] = form_key
	var f: Dictionary = Data.form_of(ROTOM, form_key)
	var sp: Dictionary = Data.species_of(ROTOM)
	mon["types"] = f.get("types", sp.get("types", mon.get("types", [])))
	mon["name"] = String(sp.get("name", "洛托姆")) if f.is_empty() \
		else "%s（%s）" % [String(sp.get("name", "洛托姆")), String(f.get("label", ""))]
	PartyScript.recalc(mon, false)
	mon["hp"] = clampi(int(round(ratio * float(int(mon["max_hp"])))), 1, int(mon["max_hp"]))
	mon["hp_text"] = "%d/%d" % [int(mon["hp"]), int(mon["max_hp"])]
	party[slot] = mon
	return String(mon["name"])

static func _rotom_label(form_key: String) -> String:
	for f in ROTOM_FORMS:
		if String(f["key"]) == form_key:
			return String(f["label"])
	return "普通形态"

static func _index_of(party: Array, sid: int) -> int:
	for i in party.size():
		var m: Variant = party[i]
		if m is Dictionary and not (m as Dictionary).is_empty() \
				and int((m as Dictionary).get("species_id", 0)) == sid \
				and (m as Dictionary).get("fused_part", null) == null:
			return i
	return -1

static func _nm(sid: int) -> String:
	return String(Data.species_of(sid).get("name", str(sid)))
