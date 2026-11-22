extends "test_hoenn_items.gd"
const Cycling:=preload("res://core/emerald_cycling.gd")
const DIRS:={Vector2i.UP:"up",Vector2i.DOWN:"down",Vector2i.LEFT:"left",Vector2i.RIGHT:"right"}
var pedalled:=0
var realtime: bool="realtime" in OS.get_cmdline_user_args()

func press(dir: Vector2i) -> void:
	game.world.tick_walk(1.0)
	game._move(DIRS[dir])
	if realtime and game.has_meta(Cycling.TIMER):
		while game.world.walking:await process_frame
	game.world.tick_walk(1.0)
	game.world.tick_walk(1.0)

func ride_to(goal: Vector2i) -> bool:
	var w=game.world
	var home:=Vector3i(w.player_pos.x,w.player_pos.y,w.last_elevation)
	var queue: Array=[home]
	var parent:={home:home}
	var found:=false
	var finish:=home
	for state in queue:
		var pos:=Vector2i(state.x,state.y)
		if pos==goal:
			finish=state
			found=true
			break
		w.last_elevation=state.z
		for dir: Vector2i in DIRS:
			var next:=pos+dir
			if not w._warp_from(pos,dir).is_empty() or not w.can_enter(next,dir):continue
			var height: int=w.elevation_at(pos)
			var dest:=Vector3i(next.x,next.y,state.z if height==15 else height)
			if parent.has(dest):continue
			parent[dest]=state
			queue.append(dest)
	w.last_elevation=home.z
	check(found,"walkable bike route from %s to %s on %s"%[home,goal,w.map_data.id])
	if not found:return false
	var path: Array=[]
	while finish!=home:
		var before: Vector3i=parent[finish]
		path.push_front(Vector2i(finish.x-before.x,finish.y-before.y))
		finish=before
	for dir: Vector2i in path:
		var before: Vector2i=w.player_pos
		await press(dir)
		if w.player_pos!=before+dir:
			check(false,"real step at %s to %s, got %s"%[before,dir,w.player_pos])
			return false
		pedalled+=1
	return true

func enter_north(bike: String) -> void:
	visit(Cycling.NORTH)
	game.world.warp_to(Vector2i(6,4));game.world.finish_walk()
	game.world.bike=not bike.is_empty()
	game._flags().h_bike=bike
	await press(Vector2i.RIGHT)

func ride(retain: bool=false) -> bool:
	if not await ride_to(Vector2i(12,5)):return false
	await press(Vector2i.DOWN)
	check(game.world.map_data.id==Cycling.ROAD and game.has_meta(Cycling.TIMER),"north bridge exit starts timing")
	if not game.has_meta(Cycling.TIMER):return false
	var started: Dictionary=game.get_meta(Cycling.TIMER)
	if retain:started.started-=61000000
	game._last_bump=-1000
	await press(Vector2i.LEFT)
	check(started.hits==1 and game.world.player_pos==Vector2i(18,17),"physical wall counts once")
	if not await ride_to(Vector2i(28,92)):return false
	check(not game.has_meta(Cycling.TIMER) and not game._dialogs.is_empty(),"original finish line signals result")
	return true

func run() -> void:
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await preload("regional_start.gd").enter(game,"hoenn")
	dismiss()
	game._flags().h_started=false
	# Route trainers have been beaten in this fixture to isolate movement and timing.
	var road: Dictionary=root.get_node("Data").load_map("hoenn",Cycling.ROAD)
	for n in road.npcs:
		if n.has("source_trainer"):game._flags()["h_trainer_"+n.source_trainer]=true
	game.world.taken=game._flags()
	await enter_north("")
	check(game.world.player_pos==Vector2i(6,4) and not game._dialogs.is_empty(),"no bike gate")
	dismiss()
	await enter_north("ITEM_ACRO_BIKE")
	check(game.world.player_pos==Vector2i(7,4),"Acro Bike admitted")
	if await ride_to(Vector2i(12,5)):await press(Vector2i.DOWN)
	check(not game.has_meta(Cycling.TIMER),"Acro Bike no timing")
	await enter_north(Cycling.MACH)
	game._toggle_bike()
	check(game.world.bike,"cannot dismount on track")
	if await ride():
		var best: Dictionary=game._flags().get(Cycling.RECORD,{}).duplicate()
		print("FIRST RIDE ",best)
		if realtime:check(int(best.get("frames",0))>450,"timed full ride at native animation speed")
		check(best.get("hits",-1)==1 and int(best.get("frames",0))>0,"fastest record includes real collision")
		dismiss()
		if await ride_to(Vector2i(31,93)):
			game.world.facing="right";game._on_action()
			check(not game._dialogs.is_empty() and str(game._dialogs.back().lines).contains("最快纪录"),"actual record sign")
		dismiss()
		await enter_north(Cycling.MACH)
		if await ride(true):
			check(game._flags().get(Cycling.RECORD,{})==best,"slower finish retains faster result")
		dismiss()
		var saved: Dictionary=Save.existing().flags.get(Cycling.RECORD,{})
		check(int(saved.get("frames",-1))==int(best.frames) and int(saved.get("hits",-1))==int(best.hits),"record survives disk reload")
	await enter_north(Cycling.MACH)
	if await ride_to(Vector2i(12,5)):await press(Vector2i.DOWN)
	game._do_warp({"region":"hoenn","map":"hoenn_mauville","at":[18,18]})
	check(not game.has_meta(Cycling.TIMER) and not game._flags().get(Cycling.TRACK,false),"leaving road cancels timer")
	check(Cycling.score(659,0)==10 and Cycling.score(660,3)==8 and Cycling.score(3600,100)==0,"native frame and collision thresholds")
	check(Cycling.summary(75,1).contains("1.25") and Cycling.summary(3600,100).contains("99 次以上"),"original result precision and limits")
	print("CYCLING ROAD ", "FAIL" if failed else "PASS"," physical_steps=",pedalled)
	Save.clear_test_slot()
	quit(int(failed))
