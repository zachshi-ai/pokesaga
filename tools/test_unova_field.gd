extends SceneTree
var checks:=0
var failed:=false

func expect(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failed=true
		push_error("UNOVA FIELD: "+label)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var field=load("res://core/unova_field.gd")
	var db=root.get_node("Data")
	db.load_core_tables()
	var maps: Dictionary=field.data().encounters
	expect(maps.bw.size()==112 and maps.b2.size()==135,"separate real encounter indices")
	for i in range(1,13):
		expect(field.season(i)==(i-1)%4,"four seasons repeat for each four-month block")
	var bw={"u1_started":true}
	var two={"u1_started":true,"u2_started":true}
	for f in [bw,two]:
		expect(field.moves_for(501,5,f).size()>0,"Oshawott starts with moves")
		expect(field.data().training[field.era(f)].machines.size()==101,"95 TMs and 6 HMs")
		var fish=false
		var available=false
		for key in maps[field.era(f)]:
			var habitat: Dictionary=field.habitat({"unova_encounter":key},f,"grass",2)
			if not habitat.pool.is_empty():available=true
			var water: Dictionary=field.habitat({"unova_encounter":key},f,"fishing",2)
			if not water.pool.is_empty():fish=true
		expect(available and fish,"both field and rod tables decode")
	var battle=load("res://core/battle.gd")
	var make_team:=func(ids:Array):
		var result: Array=[]
		for id in ids:result.append(battle.make_combatant(id,30,[33,57,403]))
		return result
	var bare=battle.new(911)
	var charged=battle.new(911)
	var left: Array=make_team.call([143])
	var right: Array=make_team.call([143])
	left[0].speed=1000
	right[0].max_hp=600
	right[0].hp=600
	bare.start(left.duplicate(true),right.duplicate(true))
	left[0].held="NORMAL_GEM"
	charged.start(left.duplicate(true),right.duplicate(true))
	bare.run_turn("move:0","move:0")
	charged.run_turn("move:0","move:0")
	expect(charged.cur_a().held=="" and charged.cur_a().get("spent_gem","")=="NORMAL_GEM" and charged.cur_b().hp<bare.cur_b().hp,"Gen V gem boosts a hit and is spent")
	var special=load("res://core/unova_phenomena.gd")
	var rng:=RandomNumberGenerator.new()
	rng.seed=7222
	var shards: Dictionary={}
	for ignored in 180:shards[special.prize(rng,2,"relic_passage","b2")]=true
	expect(shards.size()==4 and shards.keys().all(func(k):return k in special.SHARDS),"all four sequel shard types can be found in Relic Passage")
	var grass: Dictionary=db.load_map("unova","unova_2")
	expect("1" in "".join(grass.physics.phenomena),"Route 2 rustling grass uses native terrain")
	var bridge: Dictionary=db.load_map("unova","unova_driftveil_bridge")
	expect("3" in "".join(bridge.physics.phenomena),"drawbridge surface supports flying shadows")
	var rotation=load("res://core/rotation_battle.gd").new(413)
	rotation.start(make_team.call([25,3,9,6]),make_team.call([143,149,134,131]))
	expect(rotation.platform.a==[0,1,2],"three initial positions")
	rotation.team_a[0].stages.atk=3
	expect(rotation.rotate("a",2) and rotation.active_a==2,"turn a teammate to the front")
	expect(rotation.team_a[0].stages.atk==3 and not rotation.rotate("a",3),"rotation preserves boosts and excludes the bench")
	var pp:int=rotation.cur_a().pp[0]
	rotation.run_turn("move:0","move:0")
	expect(rotation.team_a[2].pp[0]==pp-1,"rotation and attack in one turn")
	var triple=load("res://core/double_battle.gd").new(318)
	triple.positions=3
	var enemies: Array=make_team.call([6,3,9,25])
	for mon in enemies:mon.moves=[33];mon.pp=[35]
	triple.start(make_team.call([143,149,134,131]),enemies)
	expect(triple.lanes.a==[0,1,2] and triple.lanes.b==[0,1,2],"six active combatants")
	expect(not triple.reachable("a",0,2,"move:0") and triple.reachable("a",0,2,"move:2"),"only distance-capable moves reach the opposite wing")
	triple.round_actions({0:{"move":"shift","target":0},1:{"move":"move:0","target":1},2:{"move":"move:0","target":2}})
	expect(triple.lanes.a[1]==0 and triple.team_a[2].pp[0]<35,"side-lane shift and simultaneous orders")
	var ui=load("res://scenes/double_battle_ui.gd").new()
	ui.positions=3
	root.add_child(ui)
	ui.setup(make_team.call([25,6,9]),make_team.call([3,1,4]),2,[],"三打测试")
	expect(ui.boxes.a.size()==3 and ui.target_buttons.size()==3,"three touch targets and HP boxes per side")
	ui.queue_free()
	var rot_ui=load("res://scenes/rotation_battle_ui.gd").new()
	root.add_child(rot_ui)
	rot_ui.setup(make_team.call([25,6,9]),make_team.call([3,1,4]),42,[],"查尔斯")
	rot_ui.state="menu"
	rot_ui._open_commands()
	rot_ui.rotate_buttons[1].pressed.emit()
	expect(rot_ui.battle.active_a==1 and rot_ui.rotate_buttons[1].disabled,"touch rotation updates active combatant")
	rot_ui.queue_free()
	await process_frame
	print("UNOVA FIELD ", "FAIL" if failed else "PASS"," checks=",checks)
	quit(int(failed))
