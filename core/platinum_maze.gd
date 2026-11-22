extends RefCounted
## Turnback Cave assigns all exits except the one the player entered through to the
## same room on arrival, with a 25% pillar chance and a limit of thirty rooms.
static func arrive(w, target: Dictionary) -> void:
	if not str(w.map_data.id).begins_with("sinnoh_turnback_cave_"):return
	var room:=str(w.map_data.id)
	var state: Dictionary=w.taken.get_or_add("pl_turnback",{})
	if room=="sinnoh_turnback_cave_entrance" or state.is_empty():state.merge({"rooms":0,"pillars":0},true)
	if room=="sinnoh_turnback_cave_pillar_room":state.pillars=mini(3,int(state.pillars)+1)
	state.rooms=int(state.rooms)+1
	state.entry=target.at
	if int(state.pillars)>=3:state.next="sinnoh_turnback_cave_giratina_room"
	elif int(state.rooms)>=30:state.next="sinnoh_turnback_cave_entrance"
	elif randi()%100<25:state.next="sinnoh_turnback_cave_pillar_room"
	else:state.next="sinnoh_turnback_cave_pillar_%d_room_%d"%[int(state.pillars)+1,randi_range(1,6)]

static func destination(w, row:Dictionary) -> Dictionary:
	var state:Dictionary=w.taken.get("pl_turnback",{})
	if state.is_empty() or row.at==state.get("entry",[]) or str(w.map_data.id)=="sinnoh_turnback_cave_giratina_room":return row.to
	return row.to.merged({"map":state.next},true)
