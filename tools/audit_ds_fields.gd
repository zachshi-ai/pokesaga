extends SceneTree
## Exercise the shipped field controller once per DS map and per active passage.
## godot --headless --path . -s tools/audit_ds_fields.gd -- bw /tmp/walk.jsonl

class Walker extends "res://core/world.gd":
	func _ready() -> void: pass
	func _rebuild(_flags: Variant=null) -> void: pass

const DIRS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const SETS := {
	"hgss":["johto","hgss/maps"], "platinum":["sinnoh","platinum_native/maps"],
	"flower":["sinnoh","platinum_native/flower"], "bw":["unova","unova_native/bw"],
	"b2":["unova","unova_native/b2"],"crystal":["johto","regions/johto/maps"],
	"sinnoh_transit":["sinnoh","regions/sinnoh/maps"],"unova_transit":["unova","regions/unova/maps"]}
var db
var world
var arrival := {}

func _initialize():
	run.call_deferred()

func point(a):
	return Vector2i(int(a[0]),int(a[1]))

func move(d):
	arrival={}
	var moved: bool=world.step(d)
	world.tick_walk(1.0)
	return moved

func land(p):
	return Rect2i(Vector2i.ZERO,world.tile_size).has_point(p) and not world.is_blocked(p) and not world.is_water(p)

func place(p):
	world.warp_to(p)
	world.finish_walk()

func traverse():
	var start: Vector2i=world.player_pos
	var visits: Dictionary={start:1}
	var cells := 0
	var count := 0
	# Follow the least-visited accessible branch, backtracking only on real steps.
	# Maps with a forced exit or an isolated spawn can legitimately have no land steps.
	for i in 96:
		var best = null
		var score := 10000000
		var spot: Vector2i=world.player_pos
		for di in range(4):
			var d: Vector2i=DIRS[(di+cells)%4]
			if not world._warp_from(spot,d).is_empty() or not world.warp_at(spot+d).is_empty():continue
			if not world.can_step(d):continue
			var dest: Vector2i=world.jump_landing(d) if world.hop_wanted(d) else spot+d
			if dest==spot or not world.warp_at(dest).is_empty():continue
			var candidate: int=visits.get(dest,0)
			if candidate<score:
				score=candidate
				best=d
		if best==null or not move(best) or not arrival.is_empty():break
		count+=1
		if not visits.has(world.player_pos):cells+=1
		visits[world.player_pos]=int(visits.get(world.player_pos,0))+1
		if visits.size()<5 and count>=16:break
	return [count,visits.size()]

func gate(w):
	var at: Vector2i=point(w.at)
	var dirs: Array=DIRS
	var direction: Vector2i=world.WARP_DIR.get(w.get("trigger","step"),Vector2i.ZERO)
	if direction!=Vector2i.ZERO:dirs=[direction]
	elif w.get("trigger","step")=="door":dirs=[Vector2i.UP]
	var blocked_npc := false
	var saw_approach := false
	var observed := ""
	for d in dirs:
		var from: Vector2i=at if direction!=Vector2i.ZERO else at-d
		var water: bool=world.is_water(from)
		if not land(from) and not water:
			if not world._npc_at(from).is_empty():blocked_npc=true
			continue
		saw_approach=true
		place(from)
		world.surfing=water
		if w.get("trigger","step")=="panel":
			world.facing={Vector2i.UP:"up",Vector2i.DOWN:"down",Vector2i.LEFT:"left",Vector2i.RIGHT:"right"}[d]
			world.step_interact()
			arrival=world.pending_warp
			world.finish_walk()
		elif not move(d):continue
		var local_move: bool=w.get("mechanism","") in ["distortion_jump","floating_jump","floating_ride"] or str(w.get("source_warp","")).begins_with("ledge_")
		if local_move and world.player_pos==point(w.to.at):return "local"
		if arrival.get("map","")==w.to.map and arrival.get("region","")==w.to.region:
			if point(arrival.at)==point(w.to.at):return "pass"
			observed="arrival_adjusted"
		elif not arrival.is_empty():
			observed="dynamic" if w.get("turnback_maze",false) or world.map_data.has("platinum_gym") else "redirect"
	return observed if observed!="" else ("npc_at_threshold" if blocked_npc else ("no_signal" if saw_approach else "no_approach"))

func run():
	var args=OS.get_cmdline_user_args()
	if args.size()!=2 or not SETS.has(args[0]):quit(1);return
	var era: String=args[0]
	var region: String=SETS[era][0]
	var folder: String="res://content/"+str(SETS[era][1])
	db=root.get_node("Data")
	if region=="unova":db.set_unova_era("bw" if era=="bw" else "b2")
	world=Walker.new()
	root.add_child(world)
	world.warp_ready.connect(func(to):arrival=to)
	var out:=FileAccess.open(args[1],FileAccess.WRITE)
	for file in DirAccess.get_files_at(folder):
		if file.get_extension()!="json":continue
		var mid:=file.get_basename()
		if era in ["crystal","sinnoh_transit","unova_transit"]:
			if not mid in db.load_region(region).map_ids:continue
			if era=="crystal" and FileAccess.file_exists("res://content/hgss/maps/"+file):continue
			if era=="sinnoh_transit" and FileAccess.file_exists("res://content/platinum_native/maps/"+file):continue
			if era=="unova_transit" and not mid.begins_with("unova_pass_"):continue
		world.taken={"s_flower_path":era=="flower"}
		if era=="hgss" and preload("res://core/johto_safari.gd").area(mid) in [3,5,9,10,11,12]:
			world.taken.j_safari_layout=[3,5,9,10,11,12]
		var data: Dictionary=db.load_map(region,mid)
		world.load_map(data)
		world.finish_walk()
		if data.is_empty() or world.map_data.id!=mid:
			out.store_line(JSON.stringify({"era":era,"region":region,"map_id":mid,"error":"load"}));continue
		world.surfing=world.is_water(world.player_pos)
		var route=traverse()
		var original_steps: int=route[0]
		# A few scripted platforms start between two transitions. Exercise an
		# actual floor in these instances while preserving the default-spawn result.
		var exercise_at: Vector2i=world.player_pos
		if original_steps==0:
			var found:=false
			for y in world.tile_size.y:
				for x in world.tile_size.x:
					var candidate:=Vector2i(x,y)
					if not land(candidate) or not world.warp_at(candidate).is_empty():continue
					place(candidate)
					route=traverse()
					if route[0]>0:
						found=true;exercise_at=candidate;break
				if found:break
		var results: Dictionary={}
		var issues: Array=[]
		for w in preload("res://core/world_passages.gd").active(world.map_data):
			var status: String=gate(w)
			if status=="no_approach" and world.map_data.has("platinum_cycling"):
				world.taken.platinum_cycling_deck=true
				world.load_map(data)
				var on_deck: String=gate(w)
				if on_deck=="pass":status="cycling_deck"
				world.taken.platinum_cycling_deck=false
				world.load_map(data)
			results[status]=int(results.get(status,0))+1
			if status not in ["pass","local","cycling_deck"]:
				issues.append([w.at,w.get("trigger","step"),w.get("source_warp",""),w.to.map,w.to.at,status])
		out.store_line(JSON.stringify({"era":era,"region":region,"map_id":mid,"spawn_steps":original_steps,"exercise_at":[exercise_at.x,exercise_at.y],"walk_steps":route[0],"unique_cells":route[1],"gates":results,"issues":issues}))
		out.flush()
	quit()
