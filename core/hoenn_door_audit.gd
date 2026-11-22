extends RefCounted
## Map topology QA. Keep original dummy warps and unsupported side activities
## separate from reachable entrances, and fail any unclassified obstruction.
const Items := preload("res://core/hoenn_items.gd")
const Campaign := preload("res://core/hoenn_campaign.gd")
const DIRS := [Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT]

static func completed_field() -> Dictionary:
	var flags := {"h_started":true,"h_rusturf_open":true,"h_regi_doors":true,"h_regi_dig":true,"h_regirock_open":true,"h_registeel_open":true,"h_regice_open":true}
	for event in Campaign.data().events:
		if event.repeat: continue
		flags[event.id]=true
		for action in event.steps:
			if action.has("hoenn_item"): flags[Items.flag_for(action.hoenn_item)]=true
	return flags

static func walk(w, seeds: Dictionary) -> Dictionary:
	# A bridge can be entered both on the bridge and beneath it. Carry the
	# previous elevation through each bridge tile, as World.step does.
	var seen := {}
	var states := {}
	var queue := []
	var previous_surf: bool=w.surfing
	var previous_height: int=w.last_elevation
	var surf: bool=Items.permission(w.taken,"SURF").is_empty()
	var waterfall: bool=Items.permission(w.taken,"WATERFALL").is_empty()
	for pos: Vector2i in seeds:
		var height: int=w.elevation_at(pos)
		var state:=Vector3i(pos.x,pos.y,0 if height==15 else height)
		states[state]=true
		queue.append(state)
	var cursor:=0
	while cursor<queue.size():
		var here: Vector3i=queue[cursor]
		cursor+=1
		var p:=Vector2i(here.x,here.y)
		seen[p]=true
		w.last_elevation=here.z
		var wet: bool=w.is_water(p)
		var current: Vector2i=w._push_dir_of(w.emerald_current,p)
		w.surfing=wet
		if current!=Vector2i.ZERO and not w.can_enter(p+current,current): current=Vector2i.ZERO
		for d: Vector2i in DIRS:
			if current!=Vector2i.ZERO and d!=current:continue
			var t:=p+d
			w.surfing=wet or (surf and w.is_water(t))
			if d==Vector2i.UP and w.is_waterfall(t) and waterfall and wet:
				t=w.waterfall_landing(p)
			elif d!=Vector2i.DOWN and (w.is_waterfall(t) or w.is_waterfall(p)):
				continue
			elif w._ledge_allows(t,d) and w.can_enter(t+d,d):t+=d
			elif not w.can_enter(t,d):continue
			var height: int=w.elevation_at(t)
			var state:=Vector3i(t.x,t.y,here.z if height==15 else height)
			if not states.has(state):
				states[state]=true
				queue.append(state)
	w.surfing=previous_surf
	w.last_elevation=previous_height
	return seen

static func trigger_reached(w,warp: Dictionary,seen: Dictionary) -> bool:
	var at:=Vector2i(warp.at[0],warp.at[1])
	if warp.get("trigger","")=="door" or w._warp_from(at+Vector2i.DOWN,Vector2i.UP)==warp:
		return seen.has(at+Vector2i.DOWN) and w._warp_from(at+Vector2i.DOWN,Vector2i.UP)==warp
	if w.WARP_DIR.has(warp.get("trigger","")):
		return seen.has(at) and w._warp_from(at,w.WARP_DIR[warp.trigger])==warp
	if warp.get("trigger","")=="panel":
		return DIRS.any(func(d):return seen.has(at+d))
	return seen.has(at)

static func scripted_exit(w,warp: Dictionary,seen: Dictionary) -> bool:
	# Some doors are taken from a conversation, including Wallace's Hall of Fame
	# escort and the Safari attendant's exit prompt. Check the actual event data.
	for event in Campaign.data().events:
		if event.map_id!=w.map_data.id or event.trigger.kind!="talk" or not Campaign.eligible(event.require,w.taken):continue
		var exits:=false
		for act in event.steps:
			if act.get("warp",{}).get("map","")==warp.to.map or act.get("hoenn_transport",[]).any(func(o):return o.target.map==warp.to.map):
				exits=true
		if not exits:continue
		for actor in w.npcs:
			if int(actor.get("local_id",0))==int(event.trigger.actor):
				var at:=Vector2i(actor.at[0],actor.at[1])
				if DIRS.any(func(d):return seen.has(at+d)):return true
	return false

static func unavailable(w,warp: Dictionary,seen: Dictionary) -> String:
	var site: String=w.map_data.emerald_original
	var at:=Vector2i(warp.at[0],warp.at[1])
	var source: int=warp.get("source_warp",-1)
	var occupancy: Dictionary=w._npc_at(at)
	# The route driver walks both legs after manipulating the specific room mechanism.
	if site in ["Route110_TrickHousePuzzle2","Route110_TrickHousePuzzle3","Route110_TrickHousePuzzle4","Route110_TrickHousePuzzle6"] and at==Vector2i(13,1) and warp.to.map=="em_route110_trick_house_end":
		return "机关屋动态机关 · 由 test_emerald_side_journey 实走验证"
	if site.begins_with("LavaridgeTown_Gym_"):
		if not occupancy.is_empty() and str(occupancy.get("source_script","")).begins_with(site+"_EventScript_") and DIRS.any(func(d):return seen.has(at+d)):
			return "原版保留 · 釜炎道馆训练家占据的沙坑"
		if site=="LavaridgeTown_Gym_1F" and source==21 and at==Vector2i(4,16) and w.blocked_by_terrain(at):
			return "原版保留 · 釜炎道馆墙内的对层坐标"
	if site=="MossdeepCity_GameCorner_1F" and source==2 and at==Vector2i(2,0) and w.blocked_by_terrain(at):
		return "原版保留 · 已停用的混合记录之家地下入口"
	match site:
		"BattleFrontier_BattlePalaceBattleRoom":
			if source==1 and occupancy.get("source_local","")=="LOCALID_PALACE_BATTLE_PLAYER": return "原版脚本退场 · 对战结束送回报名柜台"
		"BattleFrontier_OutsideEast":
			if warp.to.map=="em_battle_frontier_lounge9" and at==Vector2i(21,45):return "支线待核 · 对战开拓区第九休息室的墙内坐标"
	return ""
