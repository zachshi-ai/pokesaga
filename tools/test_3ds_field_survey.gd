extends SceneTree
## Walk every registered map and every active threshold, including the reverse
## trip from the real landing when the receiving field has a reciprocal gate.
## godot --headless --path . --script tools/test_3ds_field_survey.gd -- /tmp/fields.tsv [region ...]

class Walker extends "res://core/world.gd":
	func _ready() -> void: pass
	func _rebuild(_flags: Variant = null) -> void: pass
	func _sync_player() -> void: pass

const DIRS = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]
const REGIONS = ["kalos","alola","aether","ultra"]
const Passages = preload("res://core/world_passages.gd")
var world := Walker.new()
var db
var received := {}
var faults := 0
var total_steps := 0
var service_interactions := 0

func _initialize() -> void: call_deferred("run")

func pos(a: Array) -> Vector2i: return Vector2i(int(a[0]),int(a[1]))

func put_at(target: Dictionary) -> void:
	world.load_map(db.load_map(target.region,target.map))
	world.arrive(target)
	world.finish_walk()

func motion(dir: Vector2i) -> bool:
	if not world.step(dir):return false
	world.tick_walk(1.0)
	total_steps+=1
	return true

func blocked(dir: Vector2i) -> bool:
	var here: Vector2i=world.player_pos
	if not world._warp_from(here,dir).is_empty():return true
	if not world.can_step(dir) or world.hop_wanted(dir):return true
	var front: Dictionary=world.warp_at(here+dir)
	return not front.is_empty() and front.get("trigger","") not in world.WARP_DIR

func approach(w: Dictionary, p: Vector2i) -> Array:
	var gate:=pos(w.at)
	var trigger: String=w.get("trigger","")
	if trigger in world.WARP_DIR:
		if p==gate:return [world.WARP_DIR[trigger]]
	elif trigger=="door":
		if p==gate+Vector2i.DOWN:return [Vector2i.UP]
	elif gate-p in DIRS:return [gate-p]
	return []

func seek(w: Dictionary, limit: int) -> Array:
	var start:=world.player_pos
	var queue: Array[Vector2i]=[start]
	var parent: Dictionary={start:Vector2i.ZERO}
	var tail: Array=[]
	var cur:=start
	var index:=0
	while index<queue.size() and index<limit:
		cur=queue[index]
		index+=1
		tail=approach(w,cur)
		if not tail.is_empty():break
		# Prefer the destination, but always use game movement rules to expand.
		world.player_pos=cur
		for d: Vector2i in DIRS:
			if parent.has(cur+d) or blocked(d):continue
			parent[cur+d]=d
			queue.append(cur+d)
	world.player_pos=start
	if tail.is_empty():return []
	while cur!=start:
		var mov: Vector2i=parent[cur]
		tail.push_front(mov)
		cur-=mov
	return tail

func cross(w: Dictionary, limit: int) -> bool:
	received={}
	var moves:=seek(w,limit)
	if moves.is_empty():return false
	for d in moves:
		if not motion(d):return false
	return received.get("map","")==w.to.map and received.get("region","")==w.to.region and received.get("at",[])==w.to.at

func on_warp(target: Dictionary) -> void:
	received=target

func near_gate(w: Dictionary) -> bool:
	var gate:=pos(w.at)
	for d: Vector2i in DIRS:
		var p:=gate+d
		if w.get("trigger","") in world.WARP_DIR:p=gate
		if approach(w,p).is_empty():continue
		# Some original beach/den endpoints are occupied by a mounted surfer.
		world.surfing=world.is_water(p)
		if not world.can_enter(p,Vector2i.ZERO):continue
		world.warp_to(p)
		if cross(w,8):return true
	return false

func walk_floor() -> int:
	# Traverse to the most distant tile of the connected floor. Parent links
	# are computed with the same collision, NPC, water and passage rules as input.
	var start:=world.player_pos
	var size:=pos(world.map_data.size)
	var queue: Array[Vector2i]=[start]
	var parent: Dictionary={start:Vector2i.ZERO}
	var index:=0
	while index<queue.size():
		var here:=queue[index]
		index+=1
		world.player_pos=here
		for d: Vector2i in DIRS:
			var n:=here+d
			if parent.has(n) or n.x<0 or n.y<0 or n.x>=size.x or n.y>=size.y or blocked(d):continue
			parent[n]=d
			queue.append(n)
	var cur: Vector2i=queue.back()
	var moves: Array[Vector2i]=[]
	while cur!=start:
		var d: Vector2i=parent[cur]
		moves.push_front(d)
		cur-=d
	world.warp_to(start)
	for d in moves:
		if not motion(d):return -1
	return moves.size()

func verify_counter(m: Dictionary, key: String, feature: String) -> bool:
	var anchors: Dictionary=m.get("kalos_anchors",m.get("alola_anchors",{}))
	var clerk:=pos(anchors[key])
	var counter:=clerk+Vector2i.DOWN
	var lane:=counter+Vector2i.DOWN
	world.warp_to(lane)
	world.facing="up"
	if world.can_step(Vector2i.UP) or not world.is_counter(counter):return false
	world.last_npc={}
	world.step_interact()
	return world.last_npc.get(feature,false)

func edition_rules() -> bool:
	var rules: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_map_access.json"))
	var conditions:=0
	for mid: String in rules:
		var rule: Dictionary=rules[mid]
		for version: String in ["sun","moon","ultra_sun","ultra_moon"]:
			for state in [[false,false],[true,false],[true,true]]:
				var flags: Dictionary={}
				if rule.has("require"): flags[rule.require]=state[0]
				if rule.has("closes"): flags[rule.closes]=state[1]
				var allowed: bool=(not rule.has("versions") or version in rule.versions) and (not rule.has("require") or state[0]) and (not rule.has("closes") or not state[1])
				if preload("res://core/alola_map_access.gd").gate(mid,version,flags).is_empty()!=allowed:return false
				conditions+=1
	print("ALOLA edition and story map access ",conditions)
	return true

func stone_town_phases() -> bool:
	var m: Dictionary=db.load_map("kalos","kalos_geosenge")
	for flags: Dictionary in [{},{"k_two_buttons":true},{"k_weapon":true}]:
		world.load_map(m)
		var art: Dictionary=preload("res://core/kalos_geometry.gd").town(world,m.hoenn_art,flags)
		if not ResourceLoader.exists(art.scene[0]) or walk_floor()<1:return false
		for gate in Passages.active(m):
			if not near_gate(gate):return false
		print("GEOSENGE ",world.terrain_phase," landed ",Passages.active(m).size()," entrances")
	return true

func check(mid: String, rid: String, output: FileAccess) -> void:
	var m: Dictionary=db.load_map(rid,mid)
	world.load_map(m)
	var steps:=walk_floor()
	var problems: Array[String]=[]
	if steps<=0:problems.append("floor")
	if m.get(rid+"_center",false):
		for service in [["nurse","heal"],["mart","shop"]]:
			if verify_counter(m,service[0],service[1]):service_interactions+=1
			else:problems.append("counter "+service[0])
	var doors:=Passages.active(m)
	var crossed:=0
	var returned:=0
	var oneway:=0
	for w in doors:
		world.load_map(m)
		if not near_gate(w):
			problems.append("out %s %s"%[w.at,w.to.map])
			continue
		crossed+=1
		var destination:=received.duplicate()
		put_at(destination)
		var back: Array=Passages.active(world.map_data).filter(func(b):return b.to.region==rid and b.to.map==mid)
		if back.is_empty():
			oneway+=1
			continue
		var landing:=world.player_pos
		back.sort_custom(func(a,b):return pos(a.at).distance_squared_to(landing)<pos(b.at).distance_squared_to(landing))
		var success:=false
		for candidate in back:
			world.warp_to(landing)
			if cross(candidate,30000):
				put_at(received)
				if world.map_data.id==mid:success=true
				break
		if success:returned+=1
		else:problems.append("back %s %s from %s"%[w.at,destination.map,landing])
	faults+=problems.size()
	output.store_line("%s\t%s\t%d\t%d\t%d\t%d\t%d\t%s"%[rid,mid,steps,doors.size(),crossed,returned,oneway," | ".join(problems)])
	output.flush()
	if not problems.is_empty(): print("FIELD ",rid,"/",mid," ",problems)

func run() -> void:
	db=root.get_node("Data")
	root.add_child(world)
	world.warp_ready.connect(on_warp)
	var args:=OS.get_cmdline_user_args()
	var output:=FileAccess.open(args[0],FileAccess.WRITE)
	output.store_line("region\tmap_id\tlongest_floor_walk\tactive_exits\tcrossed\twalked_back\tno_direct_return\tfailures")
	var regions: Array=Array(args.slice(1)) if args.size()>1 else REGIONS
	for rid: String in regions:
		var places: Array=db.load_region(rid).map_ids.duplicate()
		places.sort()
		for mid: String in places:check(mid,rid,output)
		print("SURVEY ",rid," steps=",total_steps," faults=",faults)
	if "kalos" in regions and not stone_town_phases():faults+=1
	if "alola" in regions and not edition_rules():faults+=1
	print("FIELD SERVICE ",service_interactions," verified across a marked solid counter")
	output.close()
	quit(int(faults>0))
