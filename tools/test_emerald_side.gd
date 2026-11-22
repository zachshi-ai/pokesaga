extends "test_hoenn_items.gd"
## Isolated field fixtures for optional Emerald events. The continuous input replay lives in test_emerald_side_journey.py.
const Base := preload("res://core/hoenn_base.gd")
const Legends := preload("res://core/emerald_legends.gd")
const Hill := preload("res://core/hoenn_hill.gd")
const Side := preload("res://core/hoenn_side.gd")

func interact(o: Dictionary) -> void:
	var target:=Vector2i(o.at[0],o.at[1])
	for pair in [[Vector2i.DOWN,"up"],[Vector2i.LEFT,"right"],[Vector2i.RIGHT,"left"],[Vector2i.UP,"down"]]:
		var p: Vector2i=target+pair[0]
		if game.world.blocked_by_terrain(p):continue
		game.world.warp_to(p)
		game.world.finish_walk()
		game.world.facing=pair[1]
		game._on_action()
		return
	check(false,"field fixture has an adjacent square at "+str(target))

func obj(script: String) -> Dictionary:
	for o in game.world.map_data.objects:
		if o.get("source_script","")==script:return o
	return {}

func base_and_decor() -> void:
	visit("hoenn_111")
	var spots: Array=game.world.map_data.objects.filter(func(o):return o.has("secret_site"))
	var spot: Dictionary=spots[0]
	var flags: Dictionary=game._flags()
	game.save_data.party=[game.PartyScript.make(260,55,[57])]
	interact(spot)
	check(not flags.has("h_base_site"),"Secret Power required")
	dismiss()
	game.save_data.party[0].moves=[290]
	interact(spot)
	choose("使用秘密之力")
	check(game.world.map_data.id==spot.room and flags.get("h_base_site","")==spot.secret_site,"creates native base and stores its actual entrance")
	var m: Dictionary=game.world.map_data
	if not m.get("mechanisms",{}).has("base"):return
	var b: Dictionary=m.mechanisms.base
	check(b.furniture.size()==120,"120 original decoration definitions")
	var sprite_count:=0
	for id in b.furniture:
		var d: Dictionary=b.furniture[id]
		check(not Base.title(id).is_empty() and (d.has("gfx") or d.tiles.size()==d.size[0]*d.size[1]),"valid decoration "+id)
		if d.has("gfx"):
			var s:=Sprite2D.new()
			preload("res://core/hoenn_field.gd").draw(s,{"source_gfx":d.gfx},"down")
			if s.texture!=null:sprite_count+=1
			s.free()
	check(sprite_count==45,"all 45 original doll and cushion sprites load")
	check(Base.add_decoration(game,"DECOR_HEAVY_DESK") and Base.add_decoration(game,"PIKACHU_DOLL") and Base.add_decoration(game,"DECOR_GLASS_ORNAMENT"),"furniture reward interface")
	check(not Base.add_decoration(game,"FAKE"),"unknown decoration rejected")
	# Find a normal floor position with a walkable lower neighbour.
	var marker: Array=[]
	for y in range(2,int(m.size[1])-1):
		for x in range(1,int(m.size[0])-3):
			var ok:=true
			for iy in range(y-1,y+2):
				for ix in range(x-1,x+3):
					if m.physics.behavior[iy][ix]!=0 or m.physics.collision[iy][ix] or [ix,iy] in [b.pc_at,b.exit,[b.exit[0],b.exit[1]-1]]:ok=false
			if ok and marker.is_empty():marker=[x,y]
	check(not marker.is_empty(),"usable floor in selected base")
	if marker.is_empty():return
	dismiss()
	interact(obj("EmeraldBasePC"));choose("摆放家具");choose("厚重桌子");dismiss()
	face(marker);game._on_action()
	check(flags.get("h_base_furniture",[]).size()==1,"touch PC placement writes a visible desk")
	dismiss();interact(obj("EmeraldBasePC"));choose("摆放家具");choose("皮卡丘玩偶");dismiss()
	game.world.warp_to(Vector2i(marker[0]-1,marker[1]-1));game.world.finish_walk();game.world.facing="right";game._on_action()
	check(flags.get("h_base_furniture",[]).size()==2,"doll can sit on the desk")
	dismiss();var exit: Array=b.exit
	game.world.warp_to(Vector2i(exit[0],exit[1]-1));game.world.finish_walk();game.world.facing="down";game._on_action()
	check(game.world.map_data.id=="hoenn_111","base returns to the originating route")

func tide() -> void:
	var read: Dictionary=root.get_node("Data").load_region("hoenn")
	var cells:=0
	for id in read.map_ids:
		if not str(id).contains("shoal"):continue
		visit(id)
		for o in game.world.map_data.objects:
			var sc:=str(o.get("source_script",""))
			if not sc.contains("_ShoalSalt") and not sc.contains("_ShoalShell"):continue
			var name: String="浅滩海盐" if sc.contains("ShoalSalt") else "浅滩贝壳"
			var before: int=game._bag_count(name)
			interact(o);dismiss()
			if (name=="浅滩海盐")==str(id).contains("high_tide"):
				check(game._bag_count(name)==before,"inactive tide gives nothing")
				continue
			if game._bag_count(name)==before+1:cells+=1
			interact(o);dismiss()
			check(game._bag_count(name)==before+1,"daily pickup cannot repeat "+sc)
	check(cells==8,"four unique salts and four unique shells")
	visit("em_shoal_cave_low_tide_entrance_room")
	talk("ShoalCave_LowTideEntranceRoom_EventScript_ShellBellExpert");choose("制作")
	check(game._bag_count("贝壳之铃")==1 and game._bag_count("浅滩海盐")==0 and game._bag_count("浅滩贝壳")==0,"Shell Bell costs exactly 4+4")
	dismiss()

func battle_end(result: String) -> void:
	if is_instance_valid(game.active_battle):
		game.active_battle.finished.emit(result)
	dismiss()

func legends() -> void:
	var f:Dictionary=game._flags()
	visit("em_lilycove_city_harbor")
	talk("LilycoveCity_Harbor_EventScript_Sailor");dismiss()
	check(not f.has("h_distribution"),"distribution closed before League")
	f.h_champion=true
	talk("LilycoveCity_Harbor_EventScript_Sailor");choose("领取");dismiss()
	for island in Legends.ISLANDS:check(game._bag_count(Legends.ISLANDS[island][0])==1,"issued reusable ticket "+island)
	visit("littleroot_west_home_1f")
	interact(obj("EmeraldRoamingTV"));choose("红色");dismiss()
	check(f.get("h_roaming_species",0)==380,"red TV releases Latias")
	visit("em_southern_island_interior")
	interact(obj("SouthernIsland_Interior_EventScript_TryLatiEncounter"))
	check(is_instance_valid(game.active_battle) and int(game.active_battle.battle.cur_b().species_id)==381,"other Eon twin on Southern Island")
	battle_end("caught")
	check(f.get("h_legend_381",false) and game._bag_count("心之水滴")==1,"island capture awards Soul Dew once")
	visit("em_birth_island_exterior")
	var rock: Dictionary={}
	for n in game.world.npcs:
		if n.get("source_local","")=="LOCALID_BIRTH_ISLAND_EXTERIOR_ROCK":rock=n
	check(not rock.is_empty(),"Birth island triangle appears")
	if not rock.is_empty():
		for stage in 10:
			for n in game.world.npcs:
				if n.get("source_local","")=="LOCALID_BIRTH_ISLAND_EXTERIOR_ROCK":rock=n
			interact(rock);dismiss()
			check(f.get("h_deoxys_rock",0)==stage+1,"triangle moves "+str(stage+1))
		for n in game.world.npcs:
			if n.get("source_local","")=="LOCALID_BIRTH_ISLAND_EXTERIOR_ROCK":interact(n);break
		check(is_instance_valid(game.active_battle),"solved triangle starts Deoxys")
		battle_end("a")
	visit("em_sealed_chamber_inner_room")
	var wall:=obj("SealedChamber_InnerRoom_EventScript_BrailleBackWall")
	game.save_data.party=[game.PartyScript.make(369,55,[57]),game.PartyScript.make(321,55,[57])]
	interact(wall);dismiss()
	check(not f.get("h_regi_doors",false),"reversed party does not open Regi doors")
	game.save_data.party.reverse()
	interact(wall);dismiss()
	check(f.get("h_regi_doors",false),"Wailord first and Relicanth last opens all three")
	visit("em_terra_cave_end")
	var trigger: Dictionary=game.world.map_data.coord_events[0]
	game.world.warp_to(Vector2i(trigger.x,trigger.y));game.world.finish_walk()
	Legends.step(game)
	check(is_instance_valid(game.active_battle) and int(game.active_battle.battle.cur_b().species_id)==383,"native Groudon step trigger")
	battle_end("a")
	check(f.get("h_legend_383",false),"defeated static encounter persists")

func hill() -> void:
	var f: Dictionary=game._flags()
	f.h_champion=true
	for mode in Hill.MODES:
		visit(Hill.ENTRY)
		talk("TrainerHill_Entrance_EventScript_Attendant")
		choose(Hill.NAMES[Hill.MODES.find(mode)]);dismiss()
		for floor in range(1,5):
			visit("em_trainer_hill_%df"%floor)
			var course:=Hill.course(game.world)
			check(course.tiles.size()==256 and course.actors.size()==2,"native map and pair "+mode+str(floor))
			for n in course.actors:check(n.team.size()==3 and n.team[0].moves.size()>0,"original hill party "+n.name)
		var trainer: Dictionary=Hill.course(game.world).actors[0]
		interact(trainer)
		check(is_instance_valid(game.active_battle),"native trainer battle starts "+mode)
		battle_end("a")
		check(f.h_hill.won.has(trainer.hill_id),"trainer victory persists "+mode)
		visit(Hill.ROOF)
		talk("TrainerHill_Roof_EventScript_Owner");dismiss()
		check(not f.has("h_hill") and f.h_hill_times.has(mode),"roof finishes and records "+mode)
	check(Hill.reward("Normal",719)[0]=="招式学习器 11" and Hill.reward("Normal",720)!=Hill.reward("Normal",719),"12 minute reward cutoff")

func town_rewards() -> void:
	var f: Dictionary=game._flags()
	visit("em_route109_seashore_house")
	var owner:="Route109_SeashoreHouse_EventScript_Owner"
	talk(owner)
	check(game._bag_count("劲爽汽水")==0,"three beach trainers required")
	dismiss()
	for t in ["DWAYNE","SIMON","JOHANNA"]:f["h_trainer_TRAINER_"+t]=true
	talk(owner)
	check(game._bag_count("劲爽汽水")==6,"six sodas for a full house")
	dismiss()
	var before:=int(game.save_data.money)
	talk(owner)
	choose("购买")
	check(game._bag_count("劲爽汽水")==7 and game.save_data.money==before-300,"revisiting buys one soda")
	dismiss()
	var mon: Dictionary=game.PartyScript.make(260,60,[57])
	game.save_data.party=[mon]
	mon.hp=1
	game._apply_heal("劲爽汽水",0,{"hp":60})
	check(mon.hp==61,"soda restores sixty HP")
	visit("hoenn_slateport")
	talk("SlateportCity_EventScript_EffortRibbonWoman")
	check(not mon.get("effort_ribbon",false),"effort ribbon requires completed training")
	dismiss()
	mon.effort={"atk":252,"spe":252,"hp":6}
	talk("SlateportCity_EventScript_EffortRibbonWoman")
	check(mon.get("effort_ribbon",false),"effort ribbon stored on this partner")
	visit("em_pacifidlog_town_house2")
	var brother:="PacifidlogTown_House2_EventScript_FanClubYoungerBrother"
	var normal:=int(game._bag_count("招式学习器 27"))
	var unhappy:=int(game._bag_count("招式学习器 21"))
	mon.friendship=80
	talk(brother)
	check(not f.has("h_fan_tm_day"),"middle friendship keeps weekly gift available")
	dismiss()
	mon.friendship=40
	talk(brother)
	check(game._bag_count("招式学习器 21")==unhappy+1,"low friendship teaches Frustration")
	dismiss()
	mon.friendship=245
	talk(brother)
	check(game._bag_count("招式学习器 27")==normal,"weekly cooldown spans both gifts")
	dismiss()
	f.h_fan_tm_day-=7
	talk(brother)
	check(game._bag_count("招式学习器 27")==normal+1,"high friendship teaches Return after a week")

func extra_routes() -> void:
	var f: Dictionary=game._flags()
	visit("em_route114_fossil_maniacs_house")
	talk("Route114_FossilManiacsHouse_EventScript_FossilManiacsBrother");dismiss()
	check(game._bag_count("招式学习器 28")==1 and game._tm_move_of("招式学习器 28")==91,"Fossil Maniac's brother gives usable Dig")
	talk("Route114_FossilManiacsHouse_EventScript_FossilManiacsBrother");dismiss()
	check(game._bag_count("招式学习器 28")==1,"TM28 cannot duplicate")
	visit("em_route121_safari_zone_entrance")
	var actor: Dictionary=game.world.npcs.filter(func(n):return str(n.get("source_script","")).ends_with("_WelcomeAttendant"))[0]
	interact(actor);dismiss()
	check(not f.has("h_safari"),"Safari excludes visitor without Pokeblock Case")
	Items.grant(game,"ITEM_POKEBLOCK_CASE")
	game.save_data.money=700
	interact(actor);choose("入园");dismiss()
	check(f.get("h_safari",{}).get("balls",0)==30 and game.save_data.money==200 and game.world.map_data.id=="em_safari_zone_south","Safari admission costs 500 and supplies 30 balls")
	f.h_champion=false
	check(preload("res://core/hoenn_safari.gd").passage(game,{"map":"em_safari_zone_southeast"})!="","Safari expansion locked before champion")
	f.h_champion=true
	check(preload("res://core/hoenn_safari.gd").passage(game,{"map":"em_safari_zone_southeast"})=="","Safari expansion opens")
	var safari=preload("res://core/hoenn_safari.gd")
	safari.encounter(game,25,25,"")
	var screen=game.menu_layer.get_node_or_null("HoennSafariEncounter")
	check(screen!=null and screen.moves.has("near") and screen.moves.has("block"),"Safari touch encounter exposes Emerald commands")
	if screen!=null:screen.moves.run.pressed.emit()
	f.h_safari.steps=1
	safari.step(game);dismiss()
	check(game.world.map_data.id==safari.GATE and not f.has("h_safari"),"Safari returns after final step")
	visit("hoenn_130")
	var v: Dictionary=game.world.map_data.mechanisms.mirage
	check(v.tiles.size()>20 and not v.ground.is_empty(),"Mirage Island native alternate layout")
	f.h_mirage_day=Time.get_date_string_from_system()
	f.h_mirage_value=0x1234
	game.save_data.party=[game.PartyScript.make(260,50,[57]),game.PartyScript.make(150,50,[94])]
	for mon in game.save_data.party:mon.h_mirage_pid=0xabcd
	check(not Legends.mirage(game),"unmatched daily Mirage Island value keeps ocean")
	game.save_data.party[1].h_mirage_pid=0x1234
	check(Legends.mirage(game) and game.world.objects.any(func(o):return o.kind=="berry_tree"),"party match reveals island and Liechi tree")
	game.save_data.party[1].h_mirage_pid=1
	check(not Legends.mirage(game) and not game.world.objects.any(func(o):return o.kind=="berry_tree"),"island disappears when matching member leaves")
	visit("littleroot_birch_lab")
	f.h_national_dex=true
	game.save_data.dex.caught=Base.data().regional.duplicate()
	var sc:="LittlerootTown_ProfessorBirchsLab_EventScript_"
	Legends.talk(game,{"source_script":sc+"Birch"});dismiss()
	check(f.get("h_johto_starter_offer",false),"Birch offers Johto starter for 200 regional entries")
	var balls: Array=game.world.npcs.filter(func(n):return n.get("source_script","").get_slice("_EventScript_",1) in ["Chikorita","Totodile","Cyndaquil"])
	check(balls.size()==3 and balls.any(func(n):return n.at==[10,4]),"all three native starter balls staged separately")
	if not balls.is_empty():
		interact(balls[0]);choose("选择");dismiss()
		check(f.get("h_johto_starter_gift",false),"one extra starter received")
	var reporter=load("res://core/hoenn_reporters.gd")
	for wins in range(9):
		f.h_reporter_wins=wins
		for route in ["111","118","120"]:
			visit("hoenn_"+route)
			var journalists: Array=game.world.npcs.filter(func(n):return n.get("source_script","").begins_with("GabbyAndTy"))
			check(journalists.size()==(2 if route==reporter.ROUTES[wins%3] else 0),"both reporters rotate together "+str(wins)+"/"+route)
	f.h_reporter_wins=0
	visit("hoenn_111")
	var lead: Dictionary=game.world.npcs.filter(func(n):return n.get("source_script","").begins_with("GabbyAndTy"))[0]
	reporter.talk(game,lead);choose("对战")
	check(is_instance_valid(game.active_battle) and game.active_battle.battle!=null,"reporters start double battle")
	if is_instance_valid(game.active_battle):
		game.active_battle.finished.emit("a")
		choose("努力");dismiss()
		check(f.h_reporter_wins==1 and f.get("h_reporter_quote","")=="努力","interview recorded with team relocation")

func run() -> void:
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await preload("regional_start.gd").enter(game,"hoenn")
	dismiss()
	game._flags().h_started=false
	game.world.taken=game._flags()
	base_and_decor()
	tide()
	legends()
	hill()
	extra_routes()
	town_rewards()
	Save.clear_test_slot()
	print("EMERALD SIDE ", "FAIL" if failed else "PASS"," (",checks," checks)")
	quit(1 if failed else 0)
