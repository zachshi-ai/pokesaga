extends RefCounted

const Party := preload("res://core/party.gd")

static func key(species_id: int, form := "", shiny_kind := "none", tera := "") -> String:
	return "%d|%s|%s|%s" % [species_id, form, shiny_kind, tera]

static func status(variants: Dictionary, species_id: int, form := "", shiny_kind := "none", tera := "") -> int:
	return int(variants.get(key(species_id, form, shiny_kind, tera), 0))

## Older saves use four fields. A fifth marker distinguishes ordinary Dynamax
## from a normal sighting with the same species, form and shiny pattern.
static func index_by_form(variants: Dictionary) -> Dictionary:
	var result := {}
	for identity in variants:
		var parts := str(identity).split("|", true)
		if parts.size() not in [4, 5] or not parts[0].is_valid_int(): continue
		var rank := int(variants[identity])
		if rank < 1 or parts[2] not in ["none","star","square"]: continue
		var bucket := "%d|%s" % [int(parts[0]), parts[1]]
		if not result.has(bucket): result[bucket] = []
		result[bucket].append({"shine":parts[2], "battle":"giant" if parts.size()==5 and parts[4]=="giant" else parts[3], "rank":rank})
	return result

## 只登记一次确实出现的组合。太晶属性仅在战斗中真正太晶化时入册。
static func record(save: Dictionary, mon: Dictionary, owned: bool) -> void:
	var sid := int(mon.get("species_id", 0))
	if sid <= 0:
		return
	var dex: Dictionary = save.get("dex", {})
	for column in (["seen", "caught"] if owned else ["seen"]):
		var list: Array = dex.get(column, [])
		if sid not in list:
			list.append(sid)
		dex[column] = list
	save["dex"] = dex
	var variants: Dictionary = save.get("dex_variants", {})
	var tera := str(mon.get("tera_type", "")) if mon.get("tera_active", false) else ""
	var id := key(sid, str(mon.get("form", "")), Party.shiny_kind(mon), tera)
	if mon.get("dynamax_active", false) or (mon.get("gmax_active", false) and str(mon.get("form", "")).is_empty()):
		id += "|giant"
	var previous := int(variants.get(id, 0))
	variants[id] = maxi(previous, 2 if owned else 1)
	save["dex_variants"] = variants

static func sync_owned(save: Dictionary, members: Array) -> void:
	for mon in members:
		if mon is Dictionary and int(mon.get("species_id", 0)) > 0:
			Party.set_shiny_kind(mon, Party.shiny_kind(mon))
			if not mon.has("form"):
				mon["form"] = ""
			record(save, mon, true)
			if mon.get("fused_part") is Dictionary:
				sync_owned(save, [mon.fused_part])

static func restore(save: Dictionary) -> void:
	# 旧图鉴只有物种编号，保留总记录。只为实际找到的个体补录外观。
	var records: Dictionary = save.get("dex_variants", {})
	for identity in records:
		records[identity] = int(records[identity])
	save["dex_variants"] = records
	var dex: Dictionary = save.get("dex", {})
	for column in ["caught", "seen"]:
		var list: Array = []
		for id in dex.get(column, []) + save.get("dex_" + column, []):
			if int(id) > 0 and int(id) not in list:
				list.append(int(id))
		dex[column] = list
	save["dex"] = dex
	sync_owned(save, save.get("party", []))
	for box in save.get("boxes", []):
		if box is Dictionary:
			sync_owned(save, box.get("mons", []))
	sync_owned(save, save.get("box", []))
