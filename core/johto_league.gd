extends RefCounted
## 通行和对战共用同一份挑战顺序，旧存档在后面的房间仍可向南返回。

var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/johto/league.json"))

func stage(room: String) -> int:
	var rounds: Array = rules.rounds
	if room == String(rules.hall):
		return rounds.size()
	for i in rounds.size():
		if rounds[i].room == room:
			return i
	return -1

func gate_message(room: String, save: Dictionary) -> String:
	var index := stage(room)
	if index < 0:
		return ""
	var missing: Array = []
	for badge in rules.badges:
		if not (save.get("badges", []) as Array).has(badge):
			missing.append(badge)
	if not missing.is_empty():
		return "联盟要求八枚城都徽章。你还缺少%s。" % "、".join(missing)
	for i in index:
		var opponent: Dictionary = rules.rounds[i]
		if not bool((save.get("flags", {}) as Dictionary).get(opponent.flag, false)):
			return "请先战胜%s。" % String(opponent.name)
	return ""

func register_team(save: Dictionary, region := "johto") -> void:
	var hall: Dictionary = save.get("hall_of_fame", {})
	if hall.has(region):
		return
	var team: Array = []
	for mon in save.get("party", []):
		if mon is Dictionary and int(mon.get("species_id", 0)) > 0:
			team.append({"species_id": int(mon.species_id), "name": String(mon.name),
				"level": int(mon.level), "form": String(mon.get("form", "")),
				"shiny": bool(mon.get("shiny", false)),
				"shiny_kind": String(mon.get("shiny_kind", "star" if mon.get("shiny", false) else "none"))})
	if not team.is_empty():
		hall[region] = team
		save["hall_of_fame"] = hall
		save["flags"][region+"_champion"] = true

func record_lines(save: Dictionary, region := "johto") -> Array:
	var team: Array = (save.get("hall_of_fame", {}) as Dictionary).get(region, [])
	if team.is_empty():
		return ["这里记录着战胜四天王和冠军的队伍。"]
	var lines := [("关都" if region=="kanto" else "城都")+"联盟 · 首次冠军队伍"]
	for mon in team:
		lines.append("%s　Lv.%d" % [String(mon.name), int(mon.level)])
	return lines
