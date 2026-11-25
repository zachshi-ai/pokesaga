extends SceneTree
## Connected controller routes over the six Safari sections and all four Abyssal floors.
## Godot --headless --path . -s tools/test_ds_repaired_routes.gd

class Walker extends "res://core/world.gd":
	func _ready() -> void: pass
	func _rebuild(_flags: Variant=null) -> void: pass

const DIRS := [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
var db
var world
var result := {}
var steps := 0
var legs := 0
var label := ""

func _initialize():run.call_deferred()

func pt(a):return Vector2i(int(a[0]),int(a[1]))

func leg(mid):
	var targets := {}
	for w in world.map_data.warps:
		if w.to.map==mid:targets[pt(w.at)]=w
	var start: Vector2i=world.player_pos
	var queue := [start]
	var prev := {start:null}
	var index := 0
	var finish = null
	while index<queue.size() and finish==null:
		var cell: Vector2i=queue[index]
		index+=1
		for d in DIRS:
			world.player_pos=cell
			var w: Dictionary=world._warp_from(cell,d)
			if not w.is_empty():
				if w.to.map==mid:finish=[cell,d];break
				continue
			if not world.can_step(d):continue
			var next: Vector2i=world.jump_landing(d) if world.hop_wanted(d) else cell+d
			var threshold: Dictionary=world.warp_at(next)
			if threshold.get("trigger","")=="step":
				if threshold.to.map==mid:finish=[cell,d];break
				continue
			if not prev.has(next):
				prev[next]=[cell,d];queue.append(next)
	world.player_pos=start
	if finish==null:
		push_error("%s no path from %s %s to %s (visited %d)"%[label,world.map_data.id,start,mid,prev.size()])
		return false
	var moves: Array=[finish[1]]
	var current: Vector2i=finish[0]
	while current!=start:
		moves.push_front(prev[current][1]);current=prev[current][0]
	result={}
	for d in moves:
		if not world.step(d):return false
		world.tick_walk(1.0)
		steps+=1
	if result.get("map","")!=mid:return false
	world.load_map(db.load_map(result.region,mid))
	world.arrive(result)
	world.finish_walk()
	legs+=1
	return true

func start(region,mid):
	world.surfing=false
	world.load_map(db.load_map(region,mid))
	world.finish_walk()

func run():
	db=root.get_node("Data");world=Walker.new();root.add_child(world)
	world.warp_ready.connect(func(to):result=to)
	label="HGSS"
	start("johto","hgss_safari_zone_entrance_interior")
	for area in ["entrance_exterior","04","08","01","06","04","07","02","08","04","entrance_exterior","entrance_interior"]:
		if not leg("hgss_safari_zone_"+area):quit(1);return
	print(label," default six connected ",legs," transitions, ",steps," actual steps")
	# The owner's console may replace all slots. Traversal must use the saved
	# neighbors, even when the new center-south field differs from the old Peak.
	world.taken.j_safari_layout=[3,5,9,10,11,12]
	steps=0;legs=0
	start("johto","hgss_safari_zone_entrance_interior")
	for swapped in ["entrance_exterior","11","05","03","10","11","12","09","05","11","entrance_exterior","entrance_interior"]:
		if not leg("hgss_safari_zone_"+swapped):quit(1);return
	print(label," alternate six connected ",legs," transitions, ",steps," actual steps")
	for era in ["bw","b2"]:
		label=era;db.set_unova_era(era);legs=0;steps=0
		var prefix: String="unova_"+str(era)+"_zone_"
		start("unova",prefix+"245")
		# Two steps at a shaft exercise the actual swimming arrival and its return
		# without resetting position between the four corners of the sunken floor.
		for zone in [241,245,242,245,243,245,244,245,246,247,248,247,246,245]:
			if not leg(prefix+str(zone)):quit(1);return
		print(label," connected ",legs," transitions, ",steps," actual steps")
	quit()
