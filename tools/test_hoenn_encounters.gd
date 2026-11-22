extends SceneTree
## Focused fixtures for paired battles, field actors and independent league gates.
## The separate journey runner exercises the campaign from an empty save.
const Campaign := preload("res://core/hoenn_campaign.gd")
var battle_core
var failures := []

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func paired(multi: bool) -> void:
	var fight = load("res://scenes/double_battle_ui.gd").new()
	root.add_child(fight)
	var players := [battle_core.make_combatant(260,62,[57,89]),battle_core.make_combatant(254,60,[348,71])]
	if multi:
		players[0].trainer_group="first"
		players[1].trainer_group="first"
		for row in Campaign.data().steven:
			var partner: Dictionary=battle_core.make_combatant(row.species,row.level,row.moves)
			partner.trainer_group="second"
			players.append(partner)
	var event: Dictionary = Campaign.data().events.filter(func(e):return e.id==("h_space" if multi else "h_badge_7"))[0]
	var card: Dictionary = event.steps.filter(func(a):return a.has("battle"))[0].battle
	var team: Array = Campaign.team(card,{}).team
	var enemies := []
	for row in team:
		var mon: Dictionary=battle_core.make_combatant(row.species,row.level,row.get("moves",[33]))
		if row.has("trainer_group"):mon.trainer_group=row.trainer_group
		enemies.append(mon)
	fight.companion=multi
	fight.fast=true
	fight.setup(players,enemies,43,[],card.name)
	fight.set_process(false)
	var state={"outcome":"","changed":false}
	fight.finished.connect(func(result):state.outcome=result)
	check(fight.battle.lanes.a[0]!=fight.battle.lanes.a[1] and fight.battle.lanes.b[1]>=0,"two allies and opponents")
	var starting_pp: Array = players[0].pp.duplicate()
	for i in 18000:
		if state.outcome!="":break
		if fight.state=="menu":
			fight.target_buttons[1 if fight.battle.viable("b",1) else 0].pressed.emit()
			fight.menu.get_node("fight").pressed.emit()
			fight.move_menu.get_node("Move0" if int(fight.battle.cur_a().pp[0])>0 else "Move1").pressed.emit()
		fight._process(0.11)
		if i%100==0: await process_frame
	check(state.outcome=="a","paired victory")
	check(players[0].pp!=starting_pp,"player spent PP")
	if multi:check(players[2].pp[1]<10 or players[2].pp[3]<35,"Steven acted with his party")

func settle(game) -> void:
	for i in 2400:
		if not game._dialogs.is_empty():
			var dlg=game._dialogs.back()
			if dlg.is_waiting_answer(): dlg.btn_yes.pressed.emit()
			else: game._on_action()
		elif not game._escort_active: return
		await process_frame
	check(false,"scene timed out")

func stage_fixture(game,mid: String,x: int,y: int) -> void:
	game._do_warp({"region":"hoenn","map":mid,"at":[x,y],"hoenn_native":true})
	await settle(game)

func speak(game,local: int) -> void:
	var actor: Array=game.world.npcs.filter(func(n):return n.get("local_id",-1)==local)
	check(actor.size()==1,"actor is present once: %s"%local)
	if actor.is_empty():return
	var point:=Vector2i(int(actor[0].at[0]),int(actor[0].at[1]))
	for direction in [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]:
		var stand: Vector2i=point-direction
		if not game.world.can_enter(stand,Vector2i.ZERO): continue
		game.world.warp_to(stand)
		game.world.facing={Vector2i.UP:"up",Vector2i.DOWN:"down",Vector2i.LEFT:"left",Vector2i.RIGHT:"right"}[direction]
		game._on_action()
		await settle(game)
		return
	check(false,"no ordinary A-button access to actor %d"%local)

func sky_and_lake() -> void:
	var save=load("res://core/save_game.gd")
	save.use_test_slot()
	var existing: Dictionary=save.empty()
	existing.origin="hoenn"
	existing.region="hoenn"
	existing.map="em_sky_pillar_top"
	existing.pos=[14,10]
	existing.hoenn_field_revision=1
	existing.flags={"h_started":true,"h_kyogre":true,"h_duel":true,"h_origin":true,"h_wallace_origin":true,"h_pillar":true}
	existing.party=[load("res://core/party.gd").make(260,55,[57,89])]
	save.save(existing)
	var game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.title_screen.continue_button.pressed.emit()
	await settle(game)
	check(game.world.map_data.id=="em_sky_pillar_top" and game.world.player_pos==Vector2i(14,10),"tower fixture loaded")
	check(game.world.npcs.any(func(n):return n.get("local_id")==1),"sleeping Rayquaza at summit")
	game._move("up")
	game.world.tick_walk(1.0)
	await settle(game)
	check(game._flags().get("h_rayquaza",false),"approaching summit awakens Rayquaza")
	check(not game.world.npcs.any(func(n):return n.get("local_id")==1),"sleeping Rayquaza departs")
	var lake="hoenn_sootopolis"
	await stage_fixture(game,lake,31,34)
	check(game._flags().get("h_peace",false),"return to Sootopolis resolves weather showdown")
	check(not game.world.npcs.any(func(n):return int(n.get("local_id",0)) in [9,10,11]),"both legends and Rayquaza leave lake")
	print("Gym forecourt ",game.world.npcs.filter(func(n):return int(n.get("local_id",0)) in [7,16,17,18]).map(func(n):return [n.local_id,n.at]))
	check(game.world.npcs.any(func(n):return n.get("local_id")==16 and Vector2i(int(n.at[0]),int(n.at[1]))==Vector2i(33,35)),"Maxie waits outside gym")
	check(game.world.npcs.any(func(n):return n.get("local_id")==17 and Vector2i(int(n.at[0]),int(n.at[1]))==Vector2i(34,35)),"Archie waits beside Maxie")
	await speak(game,18)
	check(not game._flags().get("h_waterfall",false),"Wallace waits for the two leaders")
	await speak(game,17)
	check(game._flags().get("h_archie_peace",false) and not game._flags().get("h_teams_leave",false),"Archie alone cannot open gym")
	await speak(game,16)
	check(game._flags().get("h_teams_leave",false),"team leaders depart after both conversations")
	check(not game.world.npcs.any(func(n):return int(n.get("local_id",0)) in [16,17]),"both leaders have left")
	await speak(game,18)
	check(game._flags().get("h_item_hm_waterfall",false) and game._bag_count("秘传学习器 07")==1,"Wallace hands over HM07")
	check(Campaign.gate({"region":"hoenn","map":"em_sootopolis_city_gym_1f"},game._flags()).is_empty(),"gym opens")
	game.queue_free()
	await process_frame
	save.clear_test_slot()

func run() -> void:
	await process_frame
	root.get_node("Data").load_core_tables()
	battle_core=load("res://core/battle.gd")
	await paired(false)
	await paired(true)
	await sky_and_lake()
	var gate: Dictionary={"region":"hoenn","map":"em_ever_grande_city_champions_room"}
	check(Campaign.gate(gate,{"h_started":true,"beat_red":true,"blue_badge":true})!="","old national progress bypass")
	print("HOENN PAIRED BATTLES ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)
