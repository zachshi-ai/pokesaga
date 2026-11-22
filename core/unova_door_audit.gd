extends RefCounted
## Validate both temporal editions, including same-named towns with different terrain.
const Passages:=preload("res://core/world_passages.gd")
const DIR:={"up":Vector2i.UP,"down":Vector2i.DOWN,"left":Vector2i.LEFT,"right":Vector2i.RIGHT}

static func rooms(db,era: String) -> Array:
	var result:=[]
	for file in DirAccess.get_files_at("res://content/unova_native/"+era):
		if file.ends_with(".json"):
			var id: String=file.get_basename()
			result.append({"mid":id,"m":db.load_unova_map(id,era),"rid":"unova"})
	return result

static func point(at: Array) -> Vector2i:
	return Vector2i(int(at[0]),int(at[1]))

static func land(m: Dictionary,p: Vector2i) -> bool:
	return p.x>=0 and p.y>=0 and p.x<int(m.size[0]) and p.y<int(m.size[1]) and int(m.physics.collision[p.y][p.x])==0

static func graph(db,era: String) -> bool:
	var maps:={}
	for room in rooms(db,era):maps[room.mid]=room.m
	var ok:=true
	var count:=0
	for id in maps:
		var m: Dictionary=maps[id]
		if m.is_empty() or not m.has("physics") or not land(m,point(m.spawn)):
			print("unova graph: invalid spawn ",era,"/",id)
			ok=false
			continue
		for w in Passages.active(m):
			var destinations: Array=[w.to]
			for port in w.to.get("unova_dock_returns",{}).values():destinations.append(w.to.merged(port,true))
			for dest in destinations:
				if dest.region!="unova" or str(dest.map).begins_with("unova_pass_"):continue
				var target: Dictionary=maps.get(dest.map,{})
				if target.is_empty() or not land(target,point(dest.at)):
					print("unova graph: invalid arrival ",era,"/",id," ",w.at," -> ",dest)
					ok=false
					continue
				for npc in target.get("npcs",[]):
					if point(npc.at)==point(dest.at):
						print("unova graph: NPC on arrival ",era,"/",dest.map," ",dest.at)
						ok=false
				count+=1
	print("unova graph: ",era," maps=",maps.size()," arrivals=",count)
	return ok

static func reach(db,era: String) -> bool:
	var all:=rooms(db,era)
	var arrivals:={}
	for room in all:
		for w in Passages.active(room.m):
			var targets: Array=[w.to]
			for dock in w.to.get("unova_dock_returns",{}).values():targets.append(w.to.merged(dock,true))
			for t in targets:
				if t.region=="unova" and t.map!=room.mid:
					arrivals.get_or_add(t.map,{})[point(t.at)]=true
	var ok:=true
	var doors:=0
	var technical:=0
	var separate_lips:={}
	for room in all:
		var m: Dictionary=room.m
		var seen: Dictionary=arrivals.get(room.mid,{}).duplicate()
		# Standalone activities, script-only stages and the region's initial home use their spawn.
		if seen.is_empty():seen[point(m.spawn)]=true
		var exits:=Passages.active(m)
		var links:={}
		for w in exits:
			if w.to.region=="unova" and w.to.map==room.mid:
				links.get_or_add(point(w.at),[]).append(point(w.to.at))
		var queue:=seen.keys()
		var cursor:=0
		while cursor<queue.size():
			var p: Vector2i=queue[cursor]
			cursor+=1
			var neighbors: Array=links.get(p,[]).duplicate()
			for d: Vector2i in DIR.values():
				var adj:=p+d
				if land(m,adj):neighbors.append(adj)
			for dst in neighbors:
				if not seen.has(dst) and land(m,dst):
					seen[dst]=true
					queue.append(dst)
		for w in exits:
			var from:=point(w.at)
			# Ledge records are directional terrain rather than room entrances. Every one is
			# physically jumped (with its actual landing and animation) in ledges().
			if str(w.get("source_warp","")).begins_with("ledge_"):
				if not seen.has(from):separate_lips[room.mid]=int(separate_lips.get(room.mid,0))+1
				continue
			if not seen.has(from):
				print("unova reach: ",era,"/",room.mid," ",w.at," ",w.source_warp if w.has("source_warp") else "", " -> ",w.to.map)
				ok=false
			doors+=1
		if m.get("unova_technical",false):technical+=1
	print("unova reach: ",era," rooms=",all.size()," activity/script rooms=",technical," checked exits=",doors)
	if not separate_lips.is_empty():print("unova terrain: disconnected takeoffs from original room arrivals ",era," ",separate_lips)
	return ok

static func ledges(db,w,era: String) -> bool:
	var ok:=true
	var tested:=0
	for room in rooms(db,era):
		var loaded:=false
		for warp in Passages.active(room.m):
			if not str(warp.get("source_warp","")).begins_with("ledge_"):continue
			if not loaded:
				w.load_map(room.m)
				loaded=true
			var start:=point(warp.at)
			var target:=point(warp.to.at)
			var direction: Vector2i=DIR[warp.trigger]
			w.warp_to(start)
			w.surfing=w.is_water(start) or w.is_water(target)
			if not w.step(direction) or w.player_pos!=target or not w.jumping:
				print("unova ledge: ",era,"/",room.mid," ",start," -> ",target)
				ok=false
			w.finish_walk()
			tested+=1
	print("unova ledges: ",era," actual jumps=",tested)
	return ok
