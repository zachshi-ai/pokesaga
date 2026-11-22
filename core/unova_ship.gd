extends RefCounted

const DECKS := ["unova_frigate_driftveil","unova_frigate_seaside","unova_frigate_giant","unova_frigate_p2"]

# Black 2's EVENT_WORK_PLASMA_FRIGATE_LOCATION advances at PWT, Route 22,
# the battle against Zinzolin and the ship's post-League visit to P2 Lab.
static func dock(flags: Dictionary) -> int:
	if flags.get("u2_champion",false):return 3
	if flags.get("u2_ship_ice",false):return 2
	if flags.get("u2_mchn",false):return 1
	return 0

static func gate(current: Dictionary,target: Dictionary,flags: Dictionary) -> String:
	var i:=DECKS.find(str(target.get("map","")))
	if i>=0 and i!=dock(flags) and current.get("unova_era","")=="b2":
		return "等离子驱逐舰现在没有停在这里。"
	return ""

static func active_map(map: Dictionary,flags: Dictionary) -> Dictionary:
	if not map.get("unova_dynamic_exits",false):return map
	var weekday:=int(Time.get_date_dict_from_system().weekday)
	var active:=map.duplicate()
	active.warps=[]
	for row in map.warps:
		var target: Dictionary=row.to
		var choices: Dictionary=target.get("unova_dock_returns",{})
		var choice: Dictionary=choices.get(str(dock(flags)),{})
		var fields: Array=target.get("unova_stadium_days",[])
		if fields.size()==7:choice=fields[weekday]
		active.warps.append(row if choice.is_empty() else row.merged({"to":target.merged(choice,true)},true))
	return active
