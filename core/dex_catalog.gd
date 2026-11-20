extends RefCounted
## One notebook entry may cover several battle species. Never rewrite the saved battle ID.
## Every variant has a unique key, an actual species_id, a Data form and a separate art_key.

const CATEGORIES := {"base":"基础","regional":"地区形态","mega":"超级进化","gmax":"超极巨化",
	"type":"属性","pattern":"花纹","color":"颜色","style":"造型","gender":"性别","battle":"战斗形态",
	"paradox":"悖谬种","form":"其他形态"}
const MASK_TYPES := {"hearthflame":"fire", "wellspring":"water", "cornerstone":"rock"}
const TERA := ["normal","fire","water","electric","grass","ice","fighting","poison","ground","flying","psychic","bug","rock","ghost","dragon","dark","steel","fairy","stellar"]
static var _species := {}
static var _primary := {}
static var _related := {}
static var _children := {}
static var _search := {}

static func _ensure() -> void:
	if not _species.is_empty(): return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/dex_catalog.json"))
	_species = data.species
	_related = data.related
	for key in data.paradox:
		var source := int(key)
		var parent := int(data.paradox[key])
		_primary[source] = parent
		if not _children.has(parent): _children[parent] = []
		_children[parent].append(source)

static func entry_id(species_id: int) -> int:
	_ensure()
	return int(_primary.get(species_id, species_id)) if _species.has(str(species_id)) else 0

static func entry_ids() -> Array[int]:
	_ensure()
	var result: Array[int] = []
	for key in _species:
		if not _primary.has(int(key)):
			result.append(int(key))
	result.sort()
	return result

static func aggregate(ids: Array) -> Array[int]:
	var result: Array[int] = []
	var found := {}
	for original in ids:
		var num := entry_id(int(original))
		if num > 0 and not found.has(num):
			found[num] = true
			result.append(num)
	result.sort()
	return result

static func variants(entry: int) -> Array[Dictionary]:
	var id := entry_id(entry)
	var list: Array[Dictionary] = []
	if id == 0: return list
	var group := [id]
	group.append_array(_children.get(id, []))
	group.append_array(_related.get(str(id), []))
	for num in group:
		var row: Dictionary = _species[str(int(num))]
		for v in row.variants:
			var view := (v as Dictionary).duplicate()
			if int(num) != id:
				view["kind"] = "paradox"
				view["label"] = String(row.name) if v.kind == "base" else String(row.name) + " · " + String(v.label)
			list.append(view)
	return list

static func entry_name(entry: int) -> String:
	var id := entry_id(entry)
	return String(_species[str(id)].name) if id > 0 else ""

static func record_forms(variant: Dictionary) -> Array:
	return variant.get("record_forms", [variant.get("art_key", "")])

## A search for a paradox species or a numbered entry opens that exact species.
## A form label or English slug selects the matching variant inside the notebook.
static func preferred_variant(entry: int, query: String) -> Dictionary:
	var rows := variants(entry)
	if rows.is_empty(): return {}
	var want := query.strip_edges().trim_prefix("#").to_lower().replace("_","-")
	if want.is_empty(): return rows[0]
	for v in rows:
		var sid := int(v.species_id)
		var row: Dictionary = _species[str(sid)]
		if (want.is_valid_int() and int(want) == sid) or want == String(row.name).to_lower() or want == String(row.english).to_lower() or want == String(row.slug):
			return v
		for alias in row.aliases:
			if want == String(alias).to_lower().replace("_","-"): return v
	for v in rows:
		if want == str(v.slug) or str(v.label).to_lower().contains(want): return v
	return rows[0]

static func category(variant: Dictionary) -> String:
	return String(CATEGORIES.get(variant.get("kind", "form"), "其他形态"))

static func stats(variant: Dictionary) -> Dictionary:
	_ensure()
	var sid := int(variant.get("species_id", 0))
	if not _species.has(str(sid)): return {}
	var result := Data.stats_of(sid, String(variant.get("form", ""))).duplicate()
	# Keep the actual species name. The UI displays the variant label separately.
	result["name"] = _species[str(sid)].name
	for field in ["types","abilities","base"]:
		if variant.has(field): result[field] = variant[field]
	return result

static func tera_types(variant: Dictionary) -> Array:
	var species_id := int(variant.get("species_id", 0))
	if species_id == 1024: return ["stellar"]
	if species_id == 1017:
		var key := String(variant.key)
		for mask in MASK_TYPES:
			if key.contains(mask): return [MASK_TYPES[mask]]
		return ["grass"]
	return TERA.duplicate()

static func _search_text(id: int) -> String:
	if _search.has(id): return _search[id]
	var group := [id]
	group.append_array(_children.get(id, []))
	var words: Array = []
	for source in group:
		var row: Dictionary = _species[str(int(source))]
		words.append_array([row.name,row.english,row.slug])
		words.append_array(row.aliases)
		for v in row.variants:
			words.append(v.label)
			words.append(v.slug)
	var text := " ".join(words).to_lower().replace("_","-")
	_search[id] = text + " " + text.replace("-","").replace(" ","")
	return _search[id]

static func matches(entry: int, query: String) -> bool:
	var id := entry_id(entry)
	var wanted := query.strip_edges().to_lower().trim_prefix("#").replace("_","-")
	if id == 0: return false
	if wanted.is_empty(): return true
	if wanted.is_valid_int(): return entry_id(int(wanted)) == id
	return _search_text(id).contains(wanted.replace(" ","-")) or _search_text(id).contains(wanted)
