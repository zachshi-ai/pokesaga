extends SceneTree
## Isolated scenario saves. Put the player beside a documented speaker and use the
## field's A action, actual choice buttons, item consumption, battles and disk save.
var Side: GDScript
const Save:=preload("res://core/save_game.gd")
var Party: GDScript
var Tower: GDScript
var Safari: GDScript
var g
var db
var failed:=false
var checks:=0
func _initialize():run.call_deferred()
func check(ok: bool,why: String):
	checks+=1
	if not ok:failed=true;push_error("FRLG SIDE "+why)
func dismiss():
	g._close_all_dialogs()
	for n in g.menu_layer.get_children():
		if n.is_queued_for_deletion():continue
		if n.has_meta("choice_back"):n.get_meta("choice_back").call()
	g.world.finish_walk()
func visit(key: String):
	dismiss()
	var m: Dictionary=db.load_map(key.get_slice("/",0),key.get_slice("/",1))
	g.world.load_map(m)
	g.world.arrive({"at":m.spawn})
	g.world.finish_walk()
func choose(prefix: String):
	for menu in g.menu_layer.get_children():
		if menu.is_queued_for_deletion() or not menu.visible:continue
		for b in menu.find_children("*","Button",true,false):
			if b.text.begins_with(prefix) and not b.disabled:
				b.pressed.emit()
				return true
	check(false,"missing choice "+prefix+" at "+str(g.world.map_data.id))
	return false
func at_cell(at: Array):
	var cell:=Vector2i(int(at[0]),int(at[1]))
	for d in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
		var from: Vector2i=cell-d
		if g.world.is_counter(from):from-=d
		if not g.world.can_enter(from,d) or not g.world._npc_at(from).is_empty():continue
		g.world.warp_to(from)
		g.world.finish_walk()
		g.world.facing={Vector2i.UP:"up",Vector2i.DOWN:"down",Vector2i.LEFT:"left",Vector2i.RIGHT:"right"}[d]
		g._on_action()
		return true
	check(false,"no accessible side "+str(at)+" "+g.world.map_data.id)
	return false
func stage(row: Dictionary,key: String):
	visit(key)
	return at_cell(row.at)
func get_by(kind: String,argument=null) -> Array:
	var ret: Array=[]
	for key in Side.data().actors:
		for row in Side.data().actors[key].values():
			if row.side[0]==kind and (argument==null or row.side.any(func(value):return (int(value)==argument if typeof(value) in [TYPE_FLOAT,TYPE_INT] and typeof(argument)==TYPE_INT else is_same(value,argument)))):ret.append([row,key])
	return ret
func shops():
	var coin=get_by("gift_item","代币盒")[0]
	stage(coin[0],coin[1])
	check(g._bag_count("代币盒")==1,"received coin case")
	var clerk=get_by("coins")[0]
	stage(clerk[0],clerk[1])
	if choose("500枚"):
		check(g.save_data.fr_coins==500,"coins purchase")
	var desk=get_by("prizes","mons")[0]
	stage(desk[0],desk[1])
	if choose("凯西"):
		check(g.save_data.fr_coins==320 and g.save_data.party.any(func(m):return m.get("species_id",0)==63),"exchange prize")
	var at=[]
	for key in Side.data().field:
		for xy in Side.data().field[key]:
			if Side.data().field[key][xy][0]=="vending":
				visit(key)
				at=xy.split(",")
				at_cell(at)
				break
		if not at.is_empty():break
	if choose("柠檬汁"):
		var guy=get_by("memorial_man")[0]
		visit(guy[1])
		at_cell([9,43])
		if choose("供奉"):check(g._bag_count("招式学习器 42")==1 and g._bag_count("柠檬汁")==0,"memorial offering")
func trades():
	for entry in get_by("trade"):
		var row: Dictionary=entry[0]
		var a: Array=row.side
		g.save_data.party=[Party.make(a[2],33,[33])]
		stage(row,entry[1])
		if choose("交换") and choose(db.species_of(int(a[2])).name):
			check(g.save_data.party[0].species_id==a[3] and g.save_data.party[0].level==33 and g.save_data.party[0].original_trainer==a[5] and g._flags()[row.flag],"native trade "+row.source)
func tutors():
	for entry in get_by("tutor"):
		var row: Dictionary=entry[0]
		var mv: int=row.side[2]
		var allowed: Array=Side.data().tutor_compatibility.get(str(mv),[])
		check(not allowed.is_empty(),"original compatibility "+str(mv))
		if allowed.is_empty():continue
		g.save_data.party=[Party.make(allowed[0],30,[33])]
		stage(row,entry[1])
		if choose(db.species_of(allowed[0]).name):check(g.save_data.party[0].moves.has(mv) and g._flags().get(row.flag,false),"learnt "+str(mv))
func static_encounters():
	g.save_data.party=[Party.make(150,90,[94])]
	for entry in get_by("wild"):
		var row: Dictionary=entry[0]
		if entry[1].ends_with("navel_rock_summit"):
			visit(entry[1]);g.world.warp_to(Vector2i(9,12));Side.arrive_step(g)
		else:stage(row,entry[1])
		if not is_instance_valid(g.active_battle):
			check(false,"wild did not start "+row.source)
			continue
		check(g.active_battle.battle.cur_b().species_id==row.side[2] and g.active_battle.battle.cur_b().level==row.side[3],"wild "+row.source)
		g.active_battle.finished.emit("fled")
		await process_frame
func progression():
	var clerk=get_by("buy_mon")[0]
	var old: int=g.save_data.money
	stage(clerk[0],clerk[1])
	if choose("确定"):check(g.save_data.money==old-500 and g._flags().has(clerk[0].flag),"Magikarp purchase")
	var egg=get_by("egg")[0]
	g.save_data.party=[Party.make(25,40,[33])]
	stage(egg[0],egg[1])
	check(not g.save_data.has("egg"),"egg gated by friendship")
	g.save_data.party[0].friendship=255
	stage(egg[0],egg[1]);check(g.save_data.get("egg",{}).get("species")==175,"Togepi egg")
	visit("sevii/seven_island_sevault_canyon_tanoby_key")
	Side.after_push(g);check(not g._flags().get("fr_tanoby",false),"sealed chamber")
	g.save_data.party[0]=Party.make(68,70,[70])
	preload("res://core/region_journey.gd").grant(g.save_data,"kanto","彩虹徽章")
	var tanoby:="rruuuuullddLruurrddddlllluUUdrruuuULrddddlluRuruuUdlddddrUluuruuUrrddLdlUldddrUruuruullUrdrddlddlddRlluuuurUdrddlUUrruululldRRRddllUdddddrUluururuulLdddddrUluuuuLrddddrUluuulLrrddRlldddldddrrrruUU"
	for command in tanoby:
		if not input_step(command):return
	check(g._flags().get("fr_tanoby",false),"seven distinct pressure pads")
	visit("sevii/seven_island_tanoby_ruins_weepth_chamber")
	for i in 30:check(Side.unown(g).trim_prefix("UNOWN_") in ["E","S","I","N"],"letter belongs here")
	var master=get_by("dojo","空手道师父")[0]
	stage(master[0],master[1])
	check(is_instance_valid(g.active_battle),"dojo master starts")
	if is_instance_valid(g.active_battle):
		check(g.active_battle.battle.team_b.size()==2,"native dojo team")
		g.active_battle.finished.emit("a")
		await process_frame
	var ball=get_by("dojo_gift",106)[0]
	stage(ball[0],ball[1])
	if choose("确定"):check(g._flags().get("fr_dojo_chosen",false),"dojo selection")
	var ball2=get_by("dojo_gift",107)[0]
	stage(ball2[0],ball2[1])
	check(not g._flags().has(ball2[0].flag),"other dojo ball stays closed")
func safari():
	visit("kanto/safarizone_entrance")
	var money: int=g.save_data.money
	g._do_warp({"region":"kanto","map":"safarizone_center","at":[26,30]})
	if g._dialogs.is_empty():check(false,"entry ticket prompt");return
	g._dialogs[-1].btn_yes.pressed.emit()
	check(g.save_data.money==money-500 and g.save_data.get("fr_safari",{}).get("balls",0)==30,"ticket, fee and supply")
	for i in 599:
		if Safari.step(g):check(false,"early timeout");break
	check(g.save_data.get("fr_safari",{}).get("steps")==1,"599 counted steps")
	Safari.step(g)
	check(g.world.map_data.id==Safari.GATE and not g.save_data.has("fr_safari"),"600th returns to gate")
	dismiss()
	g._do_warp({"region":"kanto","map":"safarizone_center","at":[26,30]})
	g._dialogs[-1].btn_yes.pressed.emit()
	var captured:=false
	for i in 30:
		if not g.save_data.has("fr_safari"):break
		if not g.menu_layer.has_node("SafariEncounter"):g._start_wild_battle(129,7)
		var ui=g.menu_layer.get_node("SafariEncounter")
		if g.save_data.fr_safari.balls==30:check(ui.moves.size()==4 and not is_instance_valid(g.active_battle),"Safari four choices")
		var old: int=g.save_data.fr_safari.balls
		ui.moves.ball.pressed.emit()
		await process_frame
		if g.save_data.party.any(func(mon):return mon.get("species_id",0)==129 and mon.level==7):captured=true
		if g.save_data.has("fr_safari"):check(g.save_data.fr_safari.balls==old-1,"one ball per throw")
	check(captured and g.world.map_data.id==Safari.GATE and not g.save_data.has("fr_safari"),"captured and exhausted Safari supplies")
func tower():
	for mode in Tower.MODES:
		check(Side.data().tower[mode].size()==8,"eight floors "+mode)
		for floor_data in Side.data().tower[mode]:check(not floor_data.fights.is_empty(),"opponents "+mode)
	var desk=get_by("tower_desk")[0]
	stage(desk[0],desk[1])
	choose("单打")
	check(Tower.course(g).get("floor",0)==1,"registered time challenge")
	visit("sevii/trainer_tower_1f")
	if at_cell([15,13]) and is_instance_valid(g.active_battle):
		check(g.active_battle.battle.team_b.size()==2,"single course has two native opponents")
		g.active_battle.finished.emit("a")
		await process_frame
		check(Tower.course(g).get("floor",0)==2,"next floor after victory")
	check(not Tower.gate(g,{"map":"trainer_tower_8f"}).is_empty(),"cannot skip floors")
const DIRS := {"u":"up","d":"down","l":"left","r":"right"}
const VECTORS := {"u":Vector2i.UP,"d":Vector2i.DOWN,"l":Vector2i.LEFT,"r":Vector2i.RIGHT}
func input_step(command: String) -> bool:
	var key:=command.to_lower()
	var before: Vector2i=g.world.player_pos
	g.world.finish_walk()
	if key!=command:
		g.world.facing=DIRS[key]
		g._on_action()
		g._close_all_dialogs()
	g._move(DIRS[key])
	g.world.finish_walk()
	if g.world.player_pos!=before+VECTORS[key]:
		check(false,"field step %s at %s on %s"%[command,before,g.world.map_data.id])
		return false
	return true

func deoxys():
	visit("sevii/birth_island_exterior")
	g.save_data.party=[Party.make(150,85,[94])]
	var route=[["uuuuuuuuuuu","u"],["llll","d"],["rrrruuuu","u"],["rrrrdddd","d"],["lllllluu","l"],["rrrr","r"],["lldd","d"],["llld","l"],["rrrrrr","r"],["lll","d"],["uuu","u"]]
	for i in route.size():
		for step in route[i][0]:
			if not input_step(step):return
		g.world.facing=DIRS[route[i][1]]
		g._on_action()
		if i<10:check(g._flags().get("fr_triangle_stage",0)==i+1,"triangle landing "+str(i+1))
	check(is_instance_valid(g.active_battle) and g.active_battle.battle.cur_b().get("form","")=="DEOXYS_ATTACK","earned Deoxys on foot")
	if is_instance_valid(g.active_battle):
		g.active_battle.finished.emit("caught")
		await process_frame
		check(g._flags().get("fr_deoxys_done",false),"caught Deoxys once")
func roamers():
	var roaming=load("res://core/frlg_roamer.gd")
	visit("kanto/kanto_main")
	g.world.warp_to(Vector2i(73,225))
	roaming.observe(g)
	check(not g.save_data.has("fr_roamer"),"no beast before the network is repaired")
	g._flags().sevii_network_online=true
	roaming.observe(g)
	g.save_data.party=[Party.make(150,100,[33,86])]
	var roam: Dictionary=g.save_data.fr_roamer
	check(roam.mon.species_id==243,"Raikou for Pikachu starter")
	roam.route=1
	for i in 100:
		if roaming.roll(g):break
	check(is_instance_valid(g.active_battle),"encountered roamer on occupied route")
	if not is_instance_valid(g.active_battle):return
	var b=g.active_battle.battle
	var foe=b.cur_b()
	var remaining:int=foe.hp-21
	foe.hp=remaining
	foe.status="par"
	foe.pp[0]=1
	b.run_turn("none","0")
	check(b.over and b.winner=="fled","beast flees on its action")
	g.active_battle.finished.emit(b.winner)
	await process_frame
	check(roam.mon.hp==remaining and roam.mon.pp[0]==1 and roam.mon.status=="par" and int(roam.route)!=1,"HP status PP remain after escape and route changes")
	roam.route=1
	for i in 100:
		if roaming.roll(g):break
	check(is_instance_valid(g.active_battle) and g.active_battle.battle.cur_b().hp==remaining,"next battle restores previous HP")
	if not is_instance_valid(g.active_battle):return
	g.active_battle.finished.emit("caught")
	await process_frame
	check(not g.save_data.has("fr_roamer") and g._flags().fr_roamer_finished and g.save_data.party.back().species_id==243,"caught roamer stored once")
	g._start_wild_battle(19,5)
	check(not g.active_battle.battle.cur_b().has("fr_roaming"),"ordinary battle isolated")
	g.active_battle.finished.emit("fled")
	await process_frame
	roaming.observe(g)
	check(not g.save_data.has("fr_roamer"),"completed roamer never respawns")

func island_games():
	var clerk=get_by("joyful")[0]
	g.save_data.party=[Party.make(25,40,[33]),Party.make(85,30,[33])]
	stage(clerk[0],clerk[1])
	check(not g._dialogs.is_empty(),"game corner shut before meteorite")
	g._flags().sevii_delivered_meteorite=true
	for kind in ["jump","dodrio"]:
		stage(clerk[0],clerk[1])
		if not choose("宝可梦跳绳" if kind=="jump" else "嘟嘟利摘树果"):continue
		if not choose("皮卡丘" if kind=="jump" else "嘟嘟利"):continue
		var room=g.menu_layer.get_node("JoyfulGame")
		choose("与工作人员练习")
		var ui=room.arena
		ui.buttons.get_child(0).pressed.emit()
		if kind=="jump":
			ui._process(ui.cycle*0.85-ui.air_time()*0.5)
			ui.buttons.get_child(0).pressed.emit()
			ui._process(ui.air_time()*0.51)
			check(ui.score==60 and ui.streak==1,"jump timer and paired NPC bonus")
			ui._process(ui.cycle)
		else:
			ui._process(ui.cycle*0.74)
			ui.buttons.get_child(ui.lane).pressed.emit()
			check(ui.score==10 and ui.streak==1,"touch the ripe berry's lane")
		ui.buttons.get_child(-1).pressed.emit()
		choose("登记成绩")
		check(int(g._flags()["fr_"+kind+"_record"].points)>0,"two island game record "+kind)
		await process_frame

func fame():
	var fame_data=load("res://core/frlg_fame.gd")
	var sites:={}
	for rows in Side.data().fame.values():
		for row in rows.values():
			for id in row.clues:sites[id]=true
	sites.BILL0=true
	for who in fame_data.NAMES:
		for i in 6:check(sites.has(who+str(i)),"source for "+who+str(i))
	g._flags().erase("fr_fame_clues")
	g._flags().rival_bridge=true
	g._give_item("名人传言器",1,"key")
	visit("kanto/kanto_main")
	var rows: Dictionary=Side.data().fame["kanto/kanto_main"]
	for coords in rows:
		var row: Dictionary=rows[coords]
		if row.clues.has("BROCK0"):
			var xy=coords.split(",")
			at_cell([int(xy[0]),int(xy[1])])
			break
	var entries=fame_data.known(g)
	check(entries.has("BROCK0") and entries.has("BILL0") and not entries.has("BROCK5"),"plaque records only the visited fact")
	dismiss()
	g._use_bag_item("名人传言器")
	check(choose("小刚"),"open a discovered person")
	var late={"flag":"FLAG_HIDE_POSTGAME_GOSSIPERS","clues":["LANCE5"]}
	check(fame_data.learn(g,late).is_empty(),"postgame gossip gated")
	g._flags().kanto_champion=true
	check(fame_data.learn(g,late).size()==1 and fame_data.learn(g,late).is_empty(),"postgame gossip persists once")
func collections():
	var corner="kanto/celadon_city_game_corner"
	visit(corner)
	var stations: Dictionary=Side.data().field[corner]
	for xy in stations:
		if stations[xy][0]!="slots":continue
		var pos=xy.split(",")
		at_cell([int(pos[0]),int(pos[1])])
		break
	var machine=g.menu_layer.get_node_or_null("Reels")
	check(is_instance_valid(machine),"original Celadon reel station")
	if is_instance_valid(machine):
		var coins:int=g.save_data.fr_coins
		for i in 3:machine.wager.pressed.emit()
		check(machine.bet==3 and g.save_data.fr_coins==coins-3,"three credits pay for five lines")
		machine.stop.pressed.emit()
		for i in 3:
			machine._process(0.1)
			machine.stop.pressed.emit()
		check(not machine.running and machine.stop_count==3,"three player reel stops")
		machine.handle_back()
		await process_frame
	g._give_item("教学电视",1,"key")
	g._use_bag_item("教学电视")
	if choose("登记常用道具") and choose("名人传言器"):
		check(g._flags().fr_registered_item=="名人传言器","registered key item")
	var stickers=get_by("stickers")[0]
	g._flags().fr_link_wins=1
	stage(stickers[0],stickers[1])
	if choose("通信对战胜利"):check(g._flags().get("sticker_fr_link_wins",0)==1,"won a communication sticker")
	var doll=get_by("doll",52)[0]
	g._flags().fr_hof_count=24
	visit(doll[1])
	var p: Array=doll[0].at
	check(not g.world._npc_at(Vector2i(int(p[0]),int(p[1]))).has("side"),"Meowth doll before 25 championships")
	g._flags().fr_hof_count=25
	g.world.refresh_story_actors(g._flags())
	check(g.world._npc_at(Vector2i(int(p[0]),int(p[1]))).get("side",[]).has("doll"),"25th championship displays original doll")
	var rules: Array=preload("res://core/kanto_campaign.gd").field_rules("three_island_dunsparce_tunnel")
	var closed: Array=rules[0].base
	var opened: Array=rules[0].variants[0].cells
	check(closed.size()==152 and opened.size()==152 and opened!=closed,"national dex opens original tunnel layout")

func walk_tower(goal: Vector2i) -> bool:
	var world=g.world
	var start: Vector2i=world.player_pos
	var reached:={start:""}
	var queue: Array=[start]
	for cell in queue:
		if cell==goal:break
		for k in VECTORS:
			var dir: Vector2i=VECTORS[k]
			var next: Vector2i=cell+dir
			if reached.has(next) or not world._warp_from(cell,dir).is_empty():continue
			if not world.can_enter(next,dir) or not world._npc_at(next).is_empty():continue
			reached[next]=reached[cell]+k
			queue.append(next)
	if not reached.has(goal):
		check(false,"no walking route in %s from %s to %s"%[world.map_data.id,start,goal])
		return false
	for k in reached[goal]:
		world.tick_walk(1.0)
		g._move(DIRS[k])
		world.tick_walk(1.0)
		if is_instance_valid(g.active_battle):break
	check(world.player_pos==goal,"walking %s from %s to %s ended at %s"%[world.map_data.id,start,goal,world.player_pos])
	return world.player_pos==goal

func take_stair(cell: Vector2i,dir: String,dest: String) -> bool:
	if not walk_tower(cell):return false
	g.world.tick_walk(1.0)
	g._move(dir)
	g.world.tick_walk(1.0)
	g.world.tick_walk(1.0)
	check(g.world.map_data.id==dest,"stair to %s, arrived at %s"%[dest,g.world.map_data.id])
	return g.world.map_data.id==dest

func full_tower():
	var desk=get_by("tower_desk")[0]
	var owner=get_by("tower_owner")[0]
	var fights:=0
	for n in Tower.MODES.size():
		var mode: String=Tower.MODES[n]
		g.save_data.party=[]
		for i in 12:
			var sid:int=[150,384,382,383,149,376][i%6]
			g.save_data.party.append(Party.make(sid,75,[94,58,85,247] if sid in [150,382] else [337,89,442,399]))
		if n==0:visit(desk[1])
		if not walk_tower(Vector2i(9,7)):return
		g.world.facing="right"
		g._on_action()
		if not choose(Tower.NAMES[n]):return
		dismiss()
		if not take_stair(Vector2i(9,2),"right","trainer_tower_1f"):return
		for floor_no in range(1,9):
			var site:="trainer_tower_%df"%floor_no
			var kind: String=Side.data().tower[mode][floor_no-1].kind
			var trigger:=Vector2i(9,12) if kind=="double" else Vector2i(10,13)
			if not walk_tower(trigger):return
			while int(Tower.course(g).get("floor",0))==floor_no:
				dismiss()
				if not is_instance_valid(g.active_battle):
					check(false,"tower opponent at "+site)
					return
				var ui=g.active_battle
				for frame in 5000:
					if g.active_battle!=ui:break
					if ui.state=="menu":
						if ui.get_script().resource_path.ends_with("double_battle_ui.gd"):
							var lane:int=ui.battle.choose_lane("b",0)
							if lane>=0:ui.target_buttons[lane].pressed.emit()
						var mon: Dictionary=ui.battle.cur_a()
						var best:=-1
						var damage:=-1.0
						for j in mon.moves.size():
							if int(mon.pp[j])<=0:continue
							var mv: Dictionary=db.move_of(int(mon.moves[j]))
							var weight: float=float(mv.get("power",0))*ui.battle.effectiveness_on(str(mv.type),ui.battle.cur_b())
							if mv.type in mon.types:weight*=1.5
							if weight>damage:best=j;damage=weight
						ui.menu.get_node("fight").pressed.emit()
						var button: Button=ui.move_menu.get_node("Move%d"%best if best>=0 else "MoveStruggle")
						button.pressed.emit()
					ui._process(5.0)
				check(g.active_battle!=ui and not Tower.course(g).is_empty(),mode+" actual fight "+str(floor_no))
				if g.active_battle==ui or Tower.course(g).is_empty():return
				fights+=1
				await process_frame
			dismiss()
			if floor_no==1:
				if not take_stair(Vector2i(4,6),"left","trainer_tower_lobby"):return
				if not take_stair(Vector2i(9,2),"right",site):return
				check(g.world._npc_at(Vector2i(10,12) if kind=="double" else (Vector2i(15,13) if kind=="single" else Vector2i(14,13))).get("side",[]).has("tower_done"),"cleared roster retained on reentry")
			if not take_stair(Vector2i(15,6),"left","trainer_tower_roof" if floor_no==8 else "trainer_tower_%df"%(floor_no+1)):return
		if not walk_tower(Vector2i(int(owner[0].at[0]),int(owner[0].at[1])+1)):return
		g.world.facing="up"
		g._on_action()
		check(g._flags().get("fr_tower_prize_"+mode,false) and Tower.course(g).is_empty(),"roof item "+mode)
		dismiss()
		if not take_stair(Vector2i(13,6),"up","trainer_tower_elevator"):return
		if not walk_tower(Vector2i(0,3)):return
		g.world.facing="up"
		g._on_action()
		g.world.tick_walk(1.0)
		check(g.world.map_data.id=="trainer_tower_lobby","roof elevator returns to lobby")
	print("TOWER ACTUAL FIGHTS ",fights)

func reward_edges():
	for entry in get_by("free_coins"):
		var clerk: Dictionary=entry[0]
		var amount: int=clerk.side[2]
		g.save_data.fr_coins=10000-amount
		stage(clerk,entry[1])
		check(not g._flags().get(clerk.flag,false) and g.save_data.fr_coins==10000-amount,"room required for all gift coins")
		g.save_data.fr_coins=9999-amount
		stage(clerk,entry[1])
		check(g._flags().get(clerk.flag,false) and g.save_data.fr_coins==9999,"full gift still available")
	g.save_data.party=[Party.make(3,100,[33,15,73,75]),Party.make(3,100,[33])]
	g.save_data.party[1].friendship=255
	var tutor=get_by("starter_tutor")[0]
	stage(tutor[0],tutor[1])
	check(not g._dialogs.is_empty() and not g.save_data.party[1].moves.has(338),"only max friendship lead qualifies")
	g.save_data.party[0].friendship=255
	stage(tutor[0],tutor[1])
	choose("传授")
	dismiss()
	check(g.save_data.party[0].moves==[33,15,73,75] and not g._flags().get("fr_cape_move_338",false),"cancel replacement preserves tutor use")
	for pair in [[3,338],[6,307],[9,308]]:
		g.save_data.party[0]=Party.make(pair[0],100,[33])
		g.save_data.party[0].friendship=255
		stage(tutor[0],tutor[1])
		if choose("传授"):
			check(g.save_data.party[0].moves.has(pair[1]) and not g.save_data.party[1].moves.has(pair[1]),"taught correct lead once "+str(pair))
		var old_moves: Array=g.save_data.party[0].moves.duplicate()
		g.save_data.party[0].moves=[33]
		stage(tutor[0],tutor[1])
		check(not g._dialogs.is_empty() and g.save_data.party[0].moves==[33],"same move cannot be taught twice")
		g.save_data.party[0].moves=old_moves
	g._flags()[tutor[0].flag]=true
	g._flags().erase("fr_cape_move_308")
	stage(tutor[0],tutor[1])
	check(g._flags().get("fr_cape_move_308",false) and not g._flags().get(tutor[0].flag,false),"old shared flag recovers known move")
	for pair in [["美味之水",50],["劲爽汽水",60],["柠檬汁",80]]:
		dismiss()
		var drink: String=pair[0]
		var mon: Dictionary=g.save_data.party[0]
		mon.hp=1
		g._give_item(drink,1,"heal")
		var before: int=g._bag_count(drink)
		g._use_bag_item(drink)
		dismiss()
		check(mon.hp==1 and g._bag_count(drink)==before,"cancel drink "+drink)
		g._use_bag_item(drink)
		if choose(mon.name):check(mon.hp==1+int(pair[1]) and g._bag_count(drink)==before-1,"drink HP and consumption "+drink)

func version_and_tv():
	dismiss()
	var programmer=get_by("comparison")[0]
	stage(programmer[0],programmer[1])
	if not choose("叶绿"):return
	for entry in get_by("trade"):
		var row: Dictionary=entry[0]
		if row.side.size()<8:continue
		g._flags().erase(row.flag)
		var alt: Array=row.side[7]
		g.save_data.party=[Party.make(int(alt[0]),32,[33])]
		stage(row,entry[1])
		if choose("交换") and choose(g.save_data.party[0].name):
			check(g.save_data.party[0].species_id==int(alt[1]) and g.save_data.party[0].nickname==alt[2],"LeafGreen trade "+str(alt))
	var desk=get_by("prizes","mons")[0]
	g.save_data.fr_coins=2500
	stage(desk[0],desk[1])
	if choose("凯罗斯"):check(g.save_data.fr_coins==0 and g.save_data.party.any(func(m):return m.species_id==127 and m.level==18),"LeafGreen Pinsir prize")
	var designer=get_by("diploma")[0]
	var restored_dex: Dictionary=g.save_data.dex.duplicate(true)
	g.save_data.dex.caught=range(1,150)
	stage(designer[0],designer[1]);check(not g.menu_layer.has_node("PokedexDiploma"),"149 species not enough")
	g.save_data.dex.caught=range(1,151)
	stage(designer[0],designer[1])
	check(g._flags().get("fr_diploma_kanto",false),"150 species diploma")
	dismiss()
	await process_frame
	g.save_data.dex.caught=range(1,385).filter(func(sid):return sid not in [151,249,250,251])
	stage(designer[0],designer[1]);check(g._flags().get("fr_diploma_national",false),"380 species national diploma")
	dismiss()
	await process_frame
	g.save_data.dex=restored_dex
	visit("sevii/birth_island_exterior")
	g._flags().erase("fr_deoxys_done")
	g._flags().fr_deoxys_awake=true
	g._flags().fr_triangle_stage=10
	g.world.refresh_story_actors(g._flags())
	at_cell(Side.TRI[10])
	check(is_instance_valid(g.active_battle) and g.active_battle.battle.cur_b().get("form","")=="DEOXYS_DEFENSE","LeafGreen Deoxys")
	if is_instance_valid(g.active_battle):
		g.active_battle.finished.emit("caught")
		await process_frame
	var party: Array=g.save_data.party.duplicate(true)
	var bag: Array=g.bag_items.duplicate(true)
	var dex: Dictionary=g.save_data.dex.duplicate(true)
	var titles:=["战斗入门","异常状态","属性相性","捕捉宝可梦"]
	for i in 4:
		dismiss()
		g._use_bag_item("教学电视")
		if not choose(titles[i]):return
		var demo=g.menu_layer.get_node("TeachyDemo")
		var poisoned:=false
		var slept:=false
		for frame in 300:
			if demo.state=="finished":break
			if demo.state=="menu":demo.proceed.pressed.emit()
			demo._process(1.0)
			if demo.battle.cur_a().status=="psn":poisoned=true
			if demo.battle.cur_b().status=="slp":slept=true
		print("TV DEMO ",i," ",demo.battle.winner," turns ",demo.completed_turns," poison ",poisoned," asleep ",slept)
		check(demo.state=="finished" and demo.battle.winner==("caught" if i==3 else "a"),"TV ending "+titles[i])
		if i==1:check(poisoned and demo.battle.cur_a().status=="","TV poison and antidote")
		if i==2:check(demo.battle.cur_a().species_id==12,"TV changed to Butterfree")
		if i==3:check(slept and demo.battle.caught_species==39,"TV sleep and catch")
		await process_frame
	check(g.save_data.party==party and g.bag_items==bag and g.save_data.dex==dex,"TV leaves bag, team and dex intact")

func run():
	Side=load("res://core/frlg_sidequests.gd")
	Party=load("res://core/party.gd")
	Tower=load("res://core/frlg_tower.gd")
	Safari=load("res://core/frlg_safari.gd")
	Save.use_test_slot()
	g=load("res://scenes/boot.tscn").instantiate()
	root.add_child(g)
	await process_frame
	g.title_screen.new_button.pressed.emit()
	await process_frame
	dismiss()
	db=root.get_node("Data")
	g.save_data.money=50000
	g.save_data.party=[Party.make(25,40,[33])]
	g._flags().got_dex=true
	g._flags().national_dex=true
	g.save_data.chapters.sevii="carried"
	g.rng.seed=913
	if "tower" in OS.get_cmdline_user_args():
		await full_tower()
		print("TOWER COURSES ", "FAIL" if failed else "PASS"," checks=",checks)
		Save.clear_test_slot()
		quit(int(failed))
		return
	shops()
	trades()
	tutors()
	await static_encounters()
	await progression()
	await deoxys()
	await safari()
	await roamers()
	await island_games()
	fame()
	await collections()
	await version_and_tv()
	reward_edges()
	await tower()
	dismiss()
	g._persist()
	var restored=Save.existing()
	check(restored.flags.get("fr_dojo_chosen",false) and restored.flags.get("fr_memorial",false) and restored.flags.get("fr_tower",{}).get("floor",0)==2,"save consistency")
	g.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("FRLG SIDE ", "FAIL" if failed else "PASS", " checks=",checks)
	quit(int(failed))
