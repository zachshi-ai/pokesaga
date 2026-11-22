extends RefCounted
## Platinum's gym overlays alter the walkable map in place. Keep state in the same save.
static func state(w) -> Dictionary:
	return w.taken.get_or_add("pl_gym_"+str(w.map_data.id),{})

static func point(row: Array) -> Vector2i:
	return Vector2i(int(row[0]),int(row[1]))

static func cell(x:int,y:int,tile:int,solid:bool) -> Array:
	return [x,y,tile,0,int(solid)]

static func overrides(w) -> Array:
	var m: Dictionary=w.map_data.platinum_gym
	var s:=state(w)
	var a:Dictionary=m.tiles
	var out: Array=[]
	match str(m.kind):
		"water":
			var level:=int(s.get("level",1))
			for t in m.classes:
				var open:=int(t[2])==level
				out.append(cell(t[0],t[1],a.plank if open else a.water,not open))
			for b in m.buttons: out.append(cell(b[0],b[1],a[["yellow","green","blue"][int(b[2])]],false))
		"gear":
			var blocked:Array=m.states[int(s.get("rotation",0))]
			for i in m.regions.size():
				var r:Array=m.regions[i]
				for y in range(int(r[1]),int(r[1])+int(r[3])):
					for x in range(int(r[0]),int(r[0])+int(r[2])):
						out.append(cell(x,y,a.closed if i in blocked else a.plank,i in blocked))
			for b in m.buttons: out.append(cell(b[0],b[1],a.blue if int(b[2])==1 else a.green if int(b[2])<0 else a.yellow,false))
		"lift":
			var floor_index:=int(s.get("floor",0))
			var grid:Array=m.states[floor_index]
			for i in grid.size():
				var solid:=int(grid[i])!=0
				out.append(cell(i%32,floori(i/32.0),a.closed if solid else a.open,solid))
			for i in m.platforms.size():
				var p:Array=m.platforms[i]
				var off:=3*int(s.get(str(i),p[6]))
				if int(p[off+2])==floor_index:out.append(cell(p[off],p[off+1],a.lift,false))
			w.npcs=preload("res://core/frlg_actors.gd").roster(w.map_data,w.taken).filter(func(n):return int(n.get("elevation",0))==floor_index*10)
		"clock":
			var step:=0
			for stage in ["s_lass_caroline","s_aroma_lady_jenna","s_aroma_lady_angela"]:
				if not w.taken.get(stage,false):break
				step+=1
			if w.taken.get("s_badge_2",false):step=4
			for j in 169:
				var block:=int(m.states[step][j])!=0
				out.append(cell(5+j%13,7+floori(j/13.0),a.closed if block else a.plank,block))
			for x in 21:
				if int(m.fountain[step][x]):out.append(cell(x+1,19,a.water,true))
		"bags":
			var bags:Array=s.get_or_add("bags",m.bags.duplicate(true))
			var tires:Array=s.get_or_add("tires",m.tires.duplicate(true))
			for v in tires:out.append(cell(v[0],v[1],a.tires,true))
			for v in bags:out.append(cell(v[0],v[1],a.bag,true))
		"symbols":
			var choice:=int(s.get_or_add("choice",randi()%m.doors.size()))
			var clue:Array=s.get_or_add("clue",m.clues.pick_random())
			out.append(cell(clue[0],clue[1],a[m.doors[choice][2]],false))
			for v in m.doors:out.append(cell(v[0],v[1],a[v[2]],false))
		"snow":
			var broken:Array=s.get("broken",[])
			w.npcs=w.npcs.filter(func(n):return not (n.get("local_id","") in broken))
	return out

static func landed(w) -> void:
	var m:Dictionary=w.map_data.platinum_gym
	var s:=state(w)
	if m.kind in ["water","gear"]:
		for b in m.buttons:
			if point(b)!=w.player_pos:continue
			if m.kind=="water":s.level=int(b[2])
			else:s.rotation=posmod(int(s.get("rotation",0))+int(b[2]),4)
			w._rebuild()
			return
	elif m.kind=="lift":
		for i in m.platforms.size():
			var p:Array=m.platforms[i]
			var side:=int(s.get(str(i),p[6]))
			var off:=3*side
			if Vector2i(int(p[off]),int(p[off+1]))!=w.player_pos or int(p[off+2])!=int(s.get("floor",0)):continue
			s[str(i)]=1-side
			off=3*(1-side)
			s.floor=int(p[off+2])
			w.warp_to(Vector2i(int(p[off]),int(p[off+1])))
			w._rebuild()
			return

static func interact(w) -> bool:
	var m:Dictionary=w.map_data.platinum_gym
	if m.kind!="bags": return false
	var dir:Vector2i=w._dir_vec()
	var p:Vector2i=w.player_pos+dir
	var s:=state(w)
	var b:Array=s.bags
	var i:=b.find([p.x,p.y])
	if i<0:return false
	var dest:=p
	while true:
		var next:=dest+dir
		if next.x<0 or next.y<0 or next.x>=32 or next.y>=32:break
		var v:=int(m.rails[dest.y*32+dest.x])
		if (v==2 and dir.y!=0) or (v==3 and dir.x!=0) or (v==5 and dir.x<0):break
		if int(m.rails[next.y*32+next.x])==1 or b.has([next.x,next.y]):break
		if s.tires.has([next.x,next.y]):
			s.tires.erase([next.x,next.y])
			break
		dest=next
		if int(m.rails[dest.y*32+dest.x])==4:break
	b[i]=[dest.x,dest.y]
	w._rebuild()
	return true

static func break_snow(w,dir:Vector2i) -> void:
	if w.map_data.platinum_gym.kind!="snow" or not w.is_ice(w.player_pos) or w.last_dir!=dir:return
	var p:Vector2i=w.player_pos+dir
	for n in w.npcs:
		if point(n.at)==p and n.get("platinum_gfx","")=="OBJ_EVENT_GFX_SNOWBALL":
			state(w).get_or_add("broken",[]).append(n.local_id)
			w.npcs.erase(n)
			w._rebuild()
			return

static func destination(w,row:Dictionary) -> Dictionary:
	var m:Dictionary=w.map_data.platinum_gym
	if m.kind=="symbols":
		for i in m.doors.size():
			if point(m.doors[i])==point(row.at) and i!=int(state(w).get("choice",0)):
				return {"region":"sinnoh","map":"sinnoh_hearthome_city_gym_entrance_room","at":[4,7],"platinum_native":true}
	return row.to
