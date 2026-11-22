extends RefCounted

static func completed_field() -> Dictionary:
	var flags: Dictionary={"s_started":true,"s_national_dex":true,"s_suite_returned":true}
	for event in preload("res://core/sinnoh_campaign.gd").data().events:flags[event.id]=true
	for leader in ["aaron","bertha","flint","lucian"]:flags["s_again_"+leader]=true
	for n in range(1,9): flags["s_hm_%d"%n]=true
	return flags

static func walk(w,seeds: Dictionary) -> Dictionary:
	if not w.map_data.has("platinum_cycling"):return walk_floor(w,seeds)
	var reachable:={}
	for mode in ["ground","deck"]:
		w.emerald_collision=w.map_data.platinum_cycling[mode]
		w.taken.platinum_cycling_deck=mode=="deck"
		w.refresh_story_actors(w.taken)
		var landings:={}
		for cell in seeds:
			if not w.blocked_by_terrain(cell):landings[cell]=true
		reachable.merge(walk_floor(w,landings))
	return reachable

static func walk_floor(w,seeds: Dictionary) -> Dictionary:
	var seen:=seeds.duplicate()
	var queue:=seen.keys()
	var cursor:=0
	var surfing:bool=w.surfing
	while cursor<queue.size():
		var p:Vector2i=queue[cursor]
		cursor+=1
		for d:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var t:=p+d
			w.surfing=w.is_water(p) or w.is_water(t)
			if w.is_climb(t): t=w.platinum_climb_landing(p,d)
			elif d==Vector2i.UP and w.is_waterfall(t) and w.is_water(p):t=w.waterfall_landing(p)
			elif w._ledge_allows(t,d) and w.can_enter(t+d,d):t+=d
			elif not w.can_enter(t,d):continue
			if not seen.has(t):
				seen[t]=true
				queue.append(t)
	w.surfing=surfing
	return seen
