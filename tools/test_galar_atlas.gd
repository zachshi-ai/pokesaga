extends "res://tools/test_world_walks.gd"
## Test every registered Galar, Armor and Crown scene using actual movement,
## including each alternate gym floor. Pass -- /absolute/file.tsv [capture_dir].

class GymVisit extends Node:
	var world
	var run_held := false
	var held_dir := ""
	var panel_open := 0
	func _flags() -> Dictionary:return world.taken
	func _persist() -> void:pass
	func _show_toast(_s: String) -> void:pass

var gym:=GymVisit.new()
var visited := ""
var misses := 0
var emitted := {}

func cross(target: Dictionary) -> void:
	target=load("res://core/galar_tower.gd").switch_map(world.map_data.id,target,world.taken)
	emitted=target
	visited=str(target.region)+"/"+str(target.map)
	var dest: Dictionary=db.load_map(target.region,target.map)
	world.load_map(dest)
	world.arrive(target)
	world.finish_walk()

func enter_map(map: Dictionary, edition: String) -> void:
	world.taken.g_version=edition
	world.taken.g_champion=(edition=="champion")
	world.taken.g_water_bike=true
	world.bike=(map.id=="galar_circhester_bay" or map.get("galar_water_approach",false))
	world.load_map(map)
	world.warp_to(vec(map.spawn))
	world.finish_walk()
	current=str(map.region)+"/"+str(map.id)
	visited=current
	emitted={}
	failed=false

func ride_cups(map: Dictionary) -> bool:
	world.taken.erase("g_gym_4_field")
	for i in map.galar_facility.cups.size():
		var seat:Dictionary=map.galar_facility.cups[i]
		var at:=vec(seat.at)
		if not walk(at+Vector2i.LEFT):return false
		for j in int(seat.goal):
			preload("res://core/galar_league_gyms.gd").cup(gym,map.galar_facility,i)
		if not walk(at+Vector2i.DOWN):return false
		preload("res://core/galar_league_gyms.gd").cup(gym,map.galar_facility,i)
		while gym.panel_open:await process_frame
		if world.player_pos!=vec(seat.landing):return false
	return true

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var out: FileAccess
	if not args.is_empty():out=FileAccess.open(args[0],FileAccess.WRITE)
	var capture := str(args[1]) if args.size()>1 else ""
	if capture != "":DirAccess.make_dir_recursive_absolute(capture)
	var header="region\tmap\tedition\tspawn\tsize\tsteps\tcrossed\texits\tfailures"
	if out:out.store_line(header)
	db=root.get_node("Data")
	world=Walker.new() if capture.is_empty() else load("res://core/world.gd").new()
	root.add_child(world)
	root.add_child(gym)
	gym.world=world
	await process_frame
	world.warp_ready.connect(cross)
	var scenes:=0
	var crossed:=0
	for region in ["galar","armor","crown"]:
		for id in db.load_region(region).map_ids:
			var map: Dictionary=db.load_map(region,id)
			for version in (["sword","shield"] if int(map.get("galar_facility",{}).get("number",0)) in [4,6] else ["story","champion"] if id=="galar_wyndon" else ["shared"]):
				var errors:=PackedStringArray()
				var num:=0
				var start:=steps
				enter_map(map,version)
				if "_center_" in str(id):
					for entry in [[Vector2i(7,4),"heal"],[Vector2i(2,6),"shop"]]:
						if not walk(entry[0]):
							errors.append(str(entry[1])+" approach");continue
						world.facing="up"
						world.step_interact()
						if not world.last_npc.get(entry[1],false):errors.append(str(entry[1])+" counter")
				if capture!="":
					var frame_at:=Vector2i(-1,-1)
					if str(id).begins_with("crown_adventure_"):frame_at=Vector2i(12,7) if "fork" in str(id) else Vector2i(13,9)
					elif id=="galar_battle_tower":frame_at=Vector2i(12,7)
					elif id=="galar_battle_tower_field":frame_at=Vector2i(12,10)
					elif str(id).ends_with("_cafe_room"):frame_at=Vector2i(8,5)
					elif str(id).ends_with("_salon_room") or str(id).ends_with("_boutique_room"):frame_at=Vector2i(10,6)
					elif str(id).begins_with("galar_ionia_") and not "guest" in str(id):frame_at=Vector2i(12,5)
					if frame_at.x>=0 and not walk(frame_at):errors.append("capture approach")
					world._sync_player()
					await process_frame
					await RenderingServer.frame_post_draw
					var err:=root.get_texture().get_image().save_png(capture.path_join("%s-%s.png"%[id,version]))
					if err!=OK:errors.append("capture")
					if args.size()>2 and args[2]=="pictures":
						scenes+=1
						misses+=errors.size()
						continue
				for door in map.warps:
					enter_map(map,version)
					var dest:Dictionary=load("res://core/galar_tower.gd").switch_map(id,door.to,world.taken)
					var expected:=str(dest.region)+"/"+str(dest.map)
					var target:=vec(door.at)
					var expected_pos:=vec(dest.at)
					if id=="galar_gym_4_mission" and dest.map=="galar_gym_4_pitch":
						if not await ride_cups(map):
							errors.append("cup "+str(target));continue
					var reached:=false
					if door.get("trigger","")=="door":
						reached=walk(target+Vector2i.DOWN) and world.step(Vector2i.UP)
						world.tick_walk(1.0)
						steps+=1
					else:reached=walk(target)
					if not reached or visited!=expected or emitted.get("at",[])!=dest.at:
						errors.append("%s>%s:%s"%[door.at,dest.map,world.player_pos])
						continue
					if world.map_data.has("kalos_native") and not dest.get("kalos_native",false):expected_pos=vec(world.map_data.spawn)
					if world.player_pos!=expected_pos or world.is_blocked(world.player_pos) or world.is_water(world.player_pos):
						errors.append("arrival %s>%s:%s"%[door.at,dest.map,world.player_pos])
						continue
					num+=1
				var line="%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%s"%[region,id,version,map.spawn,map.size,steps-start,num,map.warps.size(),"; ".join(errors)]
				if out:out.store_line(line);out.flush()
				if not errors.is_empty():print("ATLAS ISSUE ",line)
				misses+=errors.size()
				scenes+=1
				crossed+=num
	print("GALAR ATLAS ",scenes," variants, ",crossed," exits, ",steps," steps, ",misses," issues")
	quit(0 if misses==0 else 1)
