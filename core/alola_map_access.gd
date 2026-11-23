extends RefCounted

static var limits: Dictionary

static func gate(mid: String, version: String, flags: Dictionary, from_map: String = "") -> String:
	if limits.is_empty():
		limits=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_map_access.json"))
	var rule: Dictionary=limits.get(mid,{})
	if rule.has("versions") and version not in rule.versions:
		return "这条道路通向另一个版本的阿罗拉。"
	if rule.has("closes") and flags.get(rule.closes,false):
		if not (from_map.begins_with("alola_rr_") and mid=="alola_rr_mansion"):
			return "彩虹火箭队已经撤退，露莎米奈的宅邸恢复了原貌。"
	if rule.has("require") and not flags.get(rule.require,false):
		return rule.message
	return ""


static func break_reef(g, obj: Dictionary) -> void:
	if not g.world.surfing or not g._flags().get("a_ride_sharpedo",false):
		g._dialog(["这些礁石挡住了水道。骑上巨牙鲨后可以撞碎它们。"])
		return
	g.world.mark_taken(obj)
	g._persist()
	g.snd.play_sfx("hit")
	g._show_toast("巨牙鲨撞开了礁石！")
