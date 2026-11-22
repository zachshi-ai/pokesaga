extends "res://tools/test_unova_side.gd"

func run() -> void:
	Save.use_test_slot()
	g=load("res://scenes/boot.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await preload("regional_start.gd").enter(g,"unova")
	g._close_all_dialogs()
	side=load("res://core/unova_side.gd")
	db=root.get_node("Data")
	party=load("res://core/party.gd")
	var pwt=load("res://core/unova_side_pwt.gd")
	var data=load("res://core/unova_side_facilities.gd").data()
	check(data.pwt_rental.sets.size()==1000 and data.pwt_modes.size()==15,"native rental, regulation and prize tables")
	var flags:={"u2_pwt":true}
	check(pwt.available(flags,{},12) and pwt.available(flags,{},14) and not pwt.available(flags,{},5),"story enrollment and champion gate")
	var completed:={"5":1,"6":1,"7":1,"8":1,"9":1}
	check(pwt.available(flags,completed,2) and not pwt.available(flags,completed,13) and not pwt.available(flags,completed,1),"advanced mode gates")
	seed(45912)
	for type in pwt.TYPES:
		var rr:={"id":2,"type":type}
		for repeat in 2:
			var slots: Array=pwt.bracket(rr)
			var opponents: Array=[slots[1]]
			var two: Array=[pwt.simulated(g,2,slots[2],slots[3]),pwt.simulated(g,2,slots[4],slots[5]),pwt.simulated(g,2,slots[6],slots[7])]
			opponents.append(two[0])
			opponents.append(pwt.simulated(g,2,two[1],two[2]))
			check(opponents.all(func(i):return i<data.pwt_masters.trainers.size() and data.pwt_rules[i][2]==type),"specialist survives each simulated round "+str(type))
			for contestant in opponents:
				var preview: Dictionary={"id":2,"type":type,"style":2,"bracket":[-1,contestant]}
				pwt.opponent(g,preview)
				check(preview.foes.size()==6 and preview.foes.all(func(m):return type in pwt.types_of(m)),"six native battle sets of type "+type)
	g.save_data.party=[party.make(445,88,[89,337,444]),party.make(9,68,[57,58,399]),party.make(6,74,[53,403,337]),party.make(130,78,[127,89,242]),party.make(131,79,[57,58,85]),party.make(149,89,[337,89,53])]
	var original: Array=g.save_data.party.duplicate(true)
	speak("b2_pwt")
	if button("租借锦标赛") and button("单打") and button("混合租借券"):
		var choice: Dictionary=g.save_data[pwt.SAVE_KEY]
		check(choice.options.size()==6 and choice.team.is_empty(),"six offered before entry and no registered party yet")
		var stored: Dictionary=Save.load_game()
		check(stored[pwt.SAVE_KEY].options[0].species_id==choice.options[0].species_id,"rental draw survives save")
		for choice_no in 3:button("",true)
		var entered: Dictionary=g.save_data[pwt.SAVE_KEY]
		check(entered.bracket.size()==8 and entered.team.size()==3 and entered.foes.size()==3,"actual entry creates an eight-person bracket and two squads")
		check(entered.team.all(func(m):return int(m.level)==50) and entered.foes.all(func(m):return not entered.team.any(func(x):return m.species_id==x.species_id)),"rental teams at level 50 with distinct owned and opposing species")
		button("开始对战")
		if is_instance_valid(g.active_battle):play_battle()
		check(original==g.save_data.party,"playing rental match leaves campaign team untouched")
		if g.save_data.has(pwt.SAVE_KEY):
			button("退出挑战")
			button("退出")
	clear()
	speak("b2_pwt")
	if button("混合锦标赛") and button("三打"):
		for choice_no in 6:button("",true)
		var run_state: Dictionary=g.save_data[pwt.SAVE_KEY]
		check(run_state.borrowed.size()==2 and run_state.borrowed[0]!=run_state.borrowed[1],"triple mix draws two distinct partner slots")
		var before: Array=run_state.team.duplicate(true)
		var foe_species: Array=run_state.foes.map(func(m):return m.species_id)
		var exchange: Array=run_state.borrowed.duplicate()
		button("开始对战")
		button("",true)
		button("",true)
		if is_instance_valid(g.active_battle):
			var ui=g.active_battle
			check(ui.positions==3 and ui.player_team.size()==6 and ui.enemy_team.size()==6,"six vs six, three active lanes")
			check(ui.player_team[exchange[0]].species_id==foe_species[0] and ui.player_team[exchange[1]].species_id==foe_species[1],"both chosen opponent monsters actually swapped into battle")
			check(ui.enemy_team[0].species_id==before[exchange[0]].species_id and ui.enemy_team[1].species_id==before[exchange[1]].species_id,"opponent received both exact selected partners")
			# Sending the close signal only for this triple-formation fixture; the single below plays all turns.
			ui.finished.emit("a")
			check(run_state.team==before and g.save_data.party==original,"next round restores original registration")
			button("退出挑战")
			button("退出")
	clear()
	g.save_data.unova_pwt_records=completed
	speak("b2_pwt")
	if button("属性专家赛") and button("单打") and button(db.type_name("water")):
		for choice_no in 3:button("",true)
		var challenge: Dictionary=g.save_data[pwt.SAVE_KEY]
		check(challenge.team.all(func(m):return "water" in pwt.types_of(m)),"water eligibility applies to the real six-mon party")
		button("退出挑战")
		button("退出")
	clear()
	# Bring unrestricted legends and play all three ordinary Driftveil matches to claim BP.
	var seed_value:=71
	for retry in 4:
		seed(seed_value+retry)
		g.rng.seed=seed_value+retry
		g.save_data.party=[party.make(493,90,[449,85,53,58]),party.make(150,90,[94,58,396,53]),party.make(644,90,[559,337,89,242])]
		speak("b2_pwt")
		if not button("帆巴锦标赛") or not button("单打"):break
		for i in 3:button("",true)
		var won:=0
		for round_no in 3:
			button("开始对战")
			if not is_instance_valid(g.active_battle):break
			if play_battle()!="a":break
			won+=1
		if won==3:break
		clear()
	check(int(g.save_data.get("unova_pwt_records",{}).get("4",0))==1 and int(g.save_data.get("unova_bp",0))>=1,"actual full three-round tournament awards BP and victory")
	print("UNOVA PWT ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures)
	Save.clear_test_slot()
	quit(0 if failures.is_empty() else 1)
