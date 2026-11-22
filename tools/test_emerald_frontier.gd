extends SceneTree
const Rules := preload("res://core/frontier_rules.gd")
const Facility := preload("res://core/frontier_challenge.gd")
const Maze := preload("res://core/frontier_maze.gd")
const Save := preload("res://core/save_game.gd")
var g
var checks := 0
var failures := []

func _initialize() -> void:run.call_deferred()

func check(ok: bool, explanation: String) -> void:
	checks+=1
	if not ok:
		failures.append(explanation)
		push_error(explanation)

func button(prefix: String,first:=false) -> bool:
	for layer in g.menu_layer.get_children():
		if not layer.visible or layer.is_queued_for_deletion():continue
		for b in layer.find_children("*","Button",true,false):
			if b.is_visible_in_tree() and (first or b.text.begins_with(prefix)):
				b.pressed.emit()
				return true
	check(false,"Missing button "+prefix)
	return false

func face(n: Dictionary) -> void:
	var pos:=Vector2i(n.at[0],n.at[1])+Vector2i.DOWN
	if g.world.is_desk(pos):pos+=Vector2i.DOWN
	g.world.warp_to(pos)
	g.world.finish_walk()
	g.world.facing="up"
	g._on_action()

func play_battle() -> String:
	var ui=g.active_battle
	ui.fast=true
	var turns:=0
	for tick in 3500:
		if g.active_battle!=ui:break
		if ui.state=="menu":
			turns+=1
			var command:=Rules.choose(ui.battle,"a",false)
			ui._on_move(int(command.get_slice(":",1)))
		else:ui._process(2.0)
	check(g.active_battle!=ui and turns>0,"played match through battle commands")
	return ui.battle.winner

func run() -> void:
	Save.use_test_slot()
	g=load("res://scenes/boot.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await preload("regional_start.gd").enter(g,"hoenn")
	await process_frame
	g._close_all_dialogs()
	var party=load("res://core/party.gd")
	var battle=load("res://core/battle.gd")
	g.save_data.party=[party.make(6,48,[53,163]),party.make(9,48,[57,33]),party.make(3,48,[75,33])]
	g._flags().h_champion=true
	var tables:=Rules.data()
	check(tables.main.sets.size()==882 and tables.main.trainers.size()==300,"original rentals and trainers")
	check(tables.nature.size()==25 and tables.bp.size()==30 and tables.move_groups.size()>=354,"nature and BP schedules")
	for k in Rules.NAMES:
		for tier in 2:
			var f: Dictionary={"kind":k,"pack":"main","mode":"单打","wins":Rules.BOSS_AT[k][tier]-1,"level":50}
			var boss:=Rules.opponent(f)
			check(Rules.symbol_at(f)==tier+1 and boss.name==Rules.BRAINS[k] and boss.team.size()==3,"leader "+k)
			if k!="factory":
				for i in 3:check(int(boss.team[i].species_id)==int(tables.brains[k][tier][i].species),"boss team "+k)
	for k in Facility.TENTS:
		var sample:=Rules.draw({"kind":Facility.TENTS[k],"pack":k,"wins":0,"level":30},6)
		check(sample.team.size()==6 and sample.team[0].level==30,"tent group "+k)
	var draw: Dictionary={"kind":"dome","mode":"单打","wins":16,"pack":"main","level":50,"team":g.save_data.party}
	for round_no in 4:
		var foe: Dictionary=preload("res://core/frontier_dome.gd").opponent(draw)
		check(draw.bracket.size()==16>>round_no and foe.team.size()==3,"sixteen-player bracket round "+str(round_no))
		if round_no==3:check(foe.name==Rules.BRAINS.dome,"Brain advances on opposite half")
		preload("res://core/frontier_dome.gd").advance(draw)
		draw.wins+=1
	for scenario in ["hit", "status", "substitute"]:
		var focus = battle.new(42)
		focus.start([battle.make_combatant(307,50,[264])],[battle.make_combatant(143,35,[33,150])])
		var opponent_hp: int = focus.cur_b().hp
		var pp: int = focus.cur_a().pp[0]
		if scenario == "substitute":
			focus.cur_a().sub_hp = 100
		focus.run_turn("move:0","move:1" if scenario == "status" else "move:0")
		check((focus.cur_b().hp == opponent_hp) == (scenario == "hit"),"Focus Punch damage after "+scenario)
		check(focus.cur_a().pp[0] == pp-1,"Focus Punch uses PP after "+scenario)
		if scenario == "hit":
			focus.run_turn("move:0","move:1")
			check(focus.cur_b().hp < opponent_hp,"Focus Punch recovers next turn")
	var match_engine=battle.new(42)
	match_engine.start([battle.make_combatant(129,10,[150])],[battle.make_combatant(129,10,[150])])
	var court:=Rules.new()
	court.kind="arena"
	for i in 3:court.turn(match_engine,"move:0")
	check(match_engine.over and match_engine.log.any(func(line):return "三回合裁定" in line),"Arena three-turn judgment")
	var db=root.get_node("Data")
	var base: Dictionary=db.load_map("hoenn",Maze.FLOOR)
	for s in 12:
		var setup: Dictionary={"kind":"pyramid","floor_seed":s,"wins":s,"cleared":[]}
		var floor_data:=Maze.apply(base,setup)
		check(floor_data.spawn!=floor_data.pyramid_exit and floor_data.physics.collision.size()==32 and not floor_data.npcs.is_empty(),"connected seeded floor %d"%s)
		check(floor_data.hoenn_art.t==Maze.apply(base,setup).hoenn_art.t,"reload same floor %d"%s)
	var lobby:="em_battle_frontier_battle_tower_lobby"
	g._do_warp({"region":"hoenn","map":lobby,"at":[8,8],"hoenn_native":true})
	var attendant: Array=g.world.npcs.filter(func(n):return str(n.get("source_script","")).ends_with("SinglesAttendant"))
	check(not attendant.is_empty(),"tower reception")
	if not attendant.is_empty():
		face(attendant[0])
		button("等级 50")
		for i in 3:button("",true)
		check(is_instance_valid(g.active_battle) and g.world.map_data.id.ends_with("tower_battle_room"),"walk up to actual counter and enter original battle room")
		var f: Dictionary=g._flags().get(Facility.RUN,{})
		if not f.is_empty() and is_instance_valid(g.active_battle):
			check(int(f.team[0].species_id)==6 and int(f.level)==50 and f.opponent.team.size()==3,"registered selected team")
			var old_save:=Save.load_game()
			check(old_save.map==g.world.map_data.id and old_save.flags[Facility.RUN].stage=="battle","saved in challenge room")
			g.active_battle.finished.emit("b")
			check(not g._flags().has(Facility.RUN) and g.world.map_data.id==lobby,"loss returns to the same desk")
			g._close_all_dialogs()
			Save.save(old_save)
			g._restore_from_save()
			await process_frame
			button("继续挑战")
			check(is_instance_valid(g.active_battle) and g.active_battle.battle.team_b[0].species_id==f.opponent.team[0].species_id,"load and resume same opponent")
			if is_instance_valid(g.active_battle):g.active_battle.finished.emit("b")
			g._close_all_dialogs()
	var tent:="em_fallarbor_town_battle_tent_lobby"
	g._do_warp({"region":"hoenn","map":tent,"at":[4,6],"hoenn_native":true})
	var clerk: Array=g.world.npcs.filter(func(n):return str(n.get("source_script","")).ends_with("Attendant"))
	check(not clerk.is_empty(),"registered at Fallarbor tent")
	if not clerk.is_empty():
		var won_set:=false
		var matches:=0
		for attempt in 12:
			if won_set:break
			face(clerk[0])
			button("参加挑战")
			for i in 3:button("",true)
			for bout in 3:
				if not is_instance_valid(g.active_battle):break
				matches+=1
				var won:=play_battle()=="a"
				if not won:break
				if bout!=2:button("继续挑战")
				else:won_set=true
			g._close_all_dialogs()
		check(won_set and g._bag_count("厉害伤药")>=1,"three real arena wins grant the tent prize")
		print("Fallarbor Tent matches actually played: ",matches)

	var calls=load("res://core/hoenn_match_call.gd")
	check(calls.contacts().size()==73,"original Match Call trainers and eight leaders")
	for id in calls.contacts():
		var chain: Array=calls.contacts()[id].teams
		check(chain.size()==4 and not preload("res://core/hoenn_campaign.gd").data().teams[chain.back()].is_empty(),"rematch teams "+id)
	g._flags().h_badge_1=true
	g._flags().h_badge_5=true
	g._flags().h_generator_reward=true
	for n in 1000:
		calls.after_battle(g,false)
		if g._flags().get("h_rematches_ready",{}).has("TRAINER_ROXANNE_1"):break
	check(g._flags().get("h_rematches_ready",{}).get("TRAINER_ROXANNE_1",false),"trainer battles unlock real leader invitations")
	g._do_warp({"region":"hoenn","map":"em_rustboro_city_gym","at":[5,3],"hoenn_native":true})
	var leader: Array=g.world.npcs.filter(func(n):return n.get("rematch_trainer",n.get("source_trainer",""))=="TRAINER_ROXANNE_1")
	if not leader.is_empty():
		face(leader[0])
		button("接受再战")
		check(is_instance_valid(g.active_battle) and g.active_battle.battle.team_b.size()==4 and g.active_battle.battle.has_method("round_actions"),"Roxanne accepts native double battle with second party")
	else:check(false,"original gym leader is present for rematch")

	Save.clear_test_slot()
	print("EMERALD FRONTIER %s · %d checks" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
