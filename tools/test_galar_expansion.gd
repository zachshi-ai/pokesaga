extends SceneTree
var failed: Array=[]
func _initialize():call_deferred("run")
func expect(ok: bool,message: String):
	if not ok:failed.append(message)

func run():
	var db=root.get_node("Data")
	db.load_core_tables()
	var campaign=load("res://core/galar_campaign.gd")
	expect(db.move_of(campaign.RIVAL_MOVES[810][2]).key=="BRANCH_POKE","Hop's Grookey learns Branch Poke")
	var exp=load("res://core/galar_expansion.gd")
	exp.load_events()
	var count:=0
	for mid in exp.maps:
		var region: String=str(mid).get_slice("_",0)
		var m: Dictionary=db.load_map(region,mid)
		for e in exp.maps[mid]:
			count+=1
			var f: Dictionary={}
			for k in e.require:f[k]=true
			if e.has("branch"):f[e.branch[0]]=e.branch[1]
			expect(exp.available(e,f),str(e.id)+" trigger")
			f[e.id]=true
			expect(not exp.available(e,f),str(e.id)+" completion")
			if e.id=="dlc_honey_intro":
				expect(not exp.available(e,{"g_champion":true,"dlc_urshifu":true}),"Hop still investigating the brothers")
				expect(exp.available(e,{"g_hop_final":true,"dlc_urshifu":true}),"Hop travels to the dojo after the forest battle")
			var cell: Array=e.at
			expect(int(m.tiles[int(cell[1])][int(cell[0])]) not in [1,2,6,7],e.id+" visible on passable ground")
			var neighbours: int=0
			for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var p=Vector2i(int(cell[0]),int(cell[1]))+d
				if p.x>=0 and p.y>=0 and p.y<m.tiles.size() and p.x<m.tiles[p.y].size() and int(m.tiles[p.y][p.x]) not in [1,2,6,7]:neighbours+=1
			expect(neighbours>0,e.id+" interaction")
	for style in ["water","dark"]:
		for i in range(1,6):
			var m: Dictionary=db.load_map("armor","armor_"+style+"_floor_"+str(i))
			var target={"map":m.id}
			expect(exp.gate(target,{} )!="",m.id+" cannot skip selection")
			var f={"dlc_tower":style}
			if i>1:
				expect(exp.gate(target,f)!="",m.id+" cannot skip trainer")
				f["dlc_"+style+str(i-1)]=true
			expect(exp.gate(target,f)=="",m.id+" entry after trainer")
			expect(m.warps.size()==(1 if i==5 else 2),m.id+" stairs")
	var raid=load("res://core/galar_raids.gd").new(321)
	var boss: Dictionary=raid.make_combatant(890,60,[690,406,53,440],"ETERNATUS_ETERNAMAX")
	raid.prepare("eternamax",boss,[])
	raid.start([raid.make_combatant(823,70,[65,400])],[boss])
	var total: int=boss.hp
	var before: int=raid.cur_a().hp
	for i in 4:
		if raid.over:break
		raid.run_turn("move:0","move:0")
	expect(raid.allies.size()==3 and raid.allies[1].moves[0]==709 and raid.allies[2].moves[0]==710,"legendary raid helpers and signature moves")
	expect(raid.cur_b().hp<total,"raid allies and player dealt damage")
	expect(raid.allies.any(func(m):return m.hp<m.max_hp) or raid.cur_a().hp<before,"boss chooses a live target")
	var b=load("res://core/battle.gd").new(6)
	var wolf: Dictionary=b.make_combatant(889,70,[442,242])
	wolf.held="RUSTED_SHIELD"
	b.start([wolf],[b.make_combatant(831,50,[33])])
	expect(b.cur_a().moves[0]==710,"iron head transformed in battle")
	var g=load("res://scenes/boot.gd").new()
	var original=exp.mon(889,70)
	original.moves=[442,242]
	g._writeback_mon(original,b.cur_a())
	expect(original.moves[0]==442,"battle move restored with PP")
	g.free()
	var lamps=load("res://scenes/galar_ruin_lamps.gd").new()
	root.add_child(lamps)
	var found: Array=[]
	lamps.solved.connect(func(sid):found.append(sid))
	lamps.check()
	expect(found.is_empty(),"wrong lamp pattern cannot awaken giant")
	for i in lamps.ELECTRIC:lamps.lamps[i].button_pressed=true
	lamps.check()
	for i in lamps.lamps.size():lamps.lamps[i].button_pressed=(i in lamps.DRAGON)
	lamps.check()
	expect(found==[894,895],"ten-lamp puzzle selects each giant")
	lamps.queue_free()
	if failed.is_empty():print("GALAR EXPANSION PASS %d events; ten tower floors, both light patterns, raid, held items"%count)
	else:
		for message in failed:push_error(str(message))
	quit(0 if failed.is_empty() else 1)
