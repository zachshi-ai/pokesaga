extends "res://tools/test_emerald_frontier.gd"
var SinnohFrontier

func run() -> void:
	Save.use_test_slot()
	g=load("res://scenes/boot.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await preload("regional_start.gd").enter(g,"sinnoh")
	g._close_all_dialogs()
	g._flags().s_champion=true
	var party=load("res://core/party.gd")
	g.save_data.party=[party.make(445,70,[89,242]),party.make(9,65,[57,58]),party.make(25,65,[85,98])]
	var snapshot: Array=g.save_data.party.duplicate(true)
	SinnohFrontier=load("res://core/sinnoh_frontier.gd")
	var book: Dictionary=SinnohFrontier.data()
	check(book.sets.size()==950 and book.trainers.size()==315,"Platinum rosters")
	for kind in SinnohFrontier.LABELS:
		var mid: String="sinnoh_battle_"+kind
		var map: Dictionary=root.get_node("Data").load_map("sinnoh",mid)
		var staff: Array=map.npcs.filter(func(n):return str(n.get("source_script","")).ends_with("_SingleAttendant"))
		check(staff.size()==1,"single reception "+kind)
		for win in ([49,169] if kind=="hall" else [20,48]):
			var run_state:={"kind":kind,"win":win,"level":50}
			SinnohFrontier.opponents(g,run_state)
			check(run_state.opponent==SinnohFrontier.BRAINS[kind][1] and run_state.enemy.size()==(1 if kind=="hall" else 3),"brain team "+kind)
	var mid:="sinnoh_battle_tower"
	g._do_warp({"region":"sinnoh","map":mid,"at":[8,12]})
	var staff: Array=g.world.npcs.filter(func(n):return str(n.get("source_script","")).ends_with("_SingleAttendant"))
	check(not staff.is_empty(),"tower desk reached")
	if not staff.is_empty():
		face(staff[0])
		if button("报名挑战"):
			for i in 3:button("",true)
			check(g.save_data.s_frontier_run.team.size()==3,"three entrants")
			check(g.save_data.s_frontier_run.team[0].level==50,"entry level capped")
			button("开始下一场")
			check(is_instance_valid(g.active_battle),"tower battle opened")
			if is_instance_valid(g.active_battle):
				play_battle()
				check(g.save_data.party==snapshot,"real team stats and PP isolated")
	doubles()
	g._close_all_dialogs()
	g.save_data.battle_points=80
	var side=load("res://core/sinnoh_side.gd")
	var shop: Array=book.shops.right
	check(shop.size()==15 and book.shops.left.size()==26,"two original shop counters")
	SinnohFrontier.exchange(g,"right")
	button(side.item_name("TM26"))
	button("交换")
	check(side.has(g,side.item_name("TM26")) and g.save_data.battle_points==0,"earthquake exchanged and charged once")
	g._close_all_dialogs()
	SinnohFrontier.exchange(g,"left")
	button(side.item_name("POWER_BRACER"))
	check(not side.has(g,side.item_name("POWER_BRACER")),"cannot spend unavailable BP")
	g.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("PLATINUM FRONTIER ", "PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	quit(int(not failures.is_empty()))


func close_run() -> void:
	var run_state: Dictionary=g.save_data.get("s_frontier_run",{})
	if run_state.is_empty():
		g._close_all_dialogs()
		return
	g._close_all_dialogs()
	if run_state.get("phase","")=="swap":button("沿用现有队伍")
	button("放弃挑战")
	button("结束")
	g._close_all_dialogs()

func doubles() -> void:
	close_run()
	var party=load("res://core/party.gd")
	g.save_data.party=[party.make(445,62,[89,242]),party.make(9,62,[57,58]),
		party.make(25,66,[85,98]),party.make(398,61,[413,332]),party.make(25,38,[85,98])]
	var snapshot: Array=g.save_data.party.duplicate(true)
	for kind in ["tower","hall","factory","castle","arcade"]:
		g._do_warp({"region":"sinnoh","map":"sinnoh_battle_"+kind,"at":[8,12]})
		var clerks: Array=g.world.npcs.filter(func(n):return str(n.get("source_script","")).ends_with("_SingleAttendant"))
		check(clerks.size()==1,"single/double counter exists "+kind)
		if clerks.is_empty():continue
		face(clerks[0])
		if not button("报名双打挑战"):continue
		if kind=="factory":button("公开级")
		for i in SinnohFrontier.entrants(kind,"double"):button("",true)
		var state: Dictionary=g.save_data.get("s_frontier_run",{})
		if state.is_empty():
			check(false,"registered actual double "+kind)
			g._close_all_dialogs()
			continue
		check(state.mode=="double" and state.team.size()==SinnohFrontier.entrants(kind,"double"),"original double team count "+kind)
		if kind=="hall":check(int(state.team[0].species_id)==25 and int(state.team[1].species_id)==25 and int(state.level)==66,"Hall requires separate same-species entrants, opponent based on higher level")
		if kind=="factory":check(state.level==100 and state.team.all(func(m):return int(m.level)==100),"open factory double keeps level 100 rentals")
		g._persist()
		var persisted: Dictionary=Save.load_game()
		check(persisted.s_frontier_run.mode=="double" and persisted.s_frontier_run.team.size()==state.team.size(),"roundtrip format and selected team "+kind)
		button("开始下一场")
		if kind=="hall":button("",true)
		if kind=="arcade":
			button("按下停止")
			g._close_all_dialogs()
		var ui=g.active_battle
		check(is_instance_valid(ui) and ui.get_script().resource_path.ends_with("double_battle_ui.gd"),"entered the two-lane battle engine "+kind)
		if is_instance_valid(ui):
			check(ui.battle.lanes.a[1]>=0 and ui.battle.lanes.b[1]>=0 and ui.battle.team_b.size()==SinnohFrontier.entrants(kind,"double"),"two battlers per side and complete reserves "+kind)
			play_battle()
		check(g.save_data.party==snapshot,"facility HP, items and PP isolated "+kind)
		close_run()
	var before:=int(g.save_data.get("battle_points",0))
	var saved_singles: Dictionary=g.save_data.get("s_frontier_streak",{}).duplicate()
	var prints: Dictionary=g.save_data.get("s_frontier_prints",{}).duplicate()
	for kind in SinnohFrontier.LABELS:
		var cut:=50 if kind=="hall" else 21
		var state:={"mode":"double","kind":kind,"win":cut,"round":7,"level":50,"cp":28}
		var threshold:=10 if kind=="hall" else 7
		var expected:=int(SinnohFrontier.data().bp[kind][cut/threshold])
		check(SinnohFrontier.boss_tier({"mode":"double","kind":kind,"win":cut-1,"level":50})=="","no solo Brain at double milestone "+kind)
		SinnohFrontier.finish(g,state,true)
		g._close_all_dialogs()
		var key: String=SinnohFrontier.run_key(state)
		check(int(g.save_data.s_frontier_streak[key])==cut and int(g.save_data.get("s_frontier_streak",{}).get(kind,0))==int(saved_singles.get(kind,0)),"separate double streak at milestone "+kind)
		check(g.save_data.battle_points==before+expected and int(g.save_data.s_frontier_earned_bp[key])>=expected,"normal double BP schedule at milestone "+kind)
		before+=expected
	check(g.save_data.get("s_frontier_prints",{})==prints,"double challenge never overwrites any silver/gold print")
	check(SinnohFrontier.key_for("factory","double",100)!=SinnohFrontier.key_for("factory","double",50),"factory open and lv50 records remain independent")
