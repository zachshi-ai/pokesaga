extends "res://tools/test_region_journey.gd"

const Field = preload("res://core/alola_field.gd")
const Start = preload("regional_start.gd")

func arrival(old:Dictionary,version:String,mode:String) -> void:
	expect(Save.save(old.duplicate(true)), "legacy slot written")
	await title()
	expect(await Start.enter(game,"alola",mode,version),"choose "+version+"/"+mode)
	var slot:=Save.existing()
	expect(slot.flags.a_version==version and slot.chapters.alola==mode,"store version and transfer choice")
	expect(slot.map=="alola_home" and Vector2i(int(slot.pos[0]),int(slot.pos[1]))==Vector2i(8,7),"wake up at home on Melemele")
	expect(slot.money==old.money and slot.dex==old.dex and slot.hall_of_fame==old.hall_of_fame,"preserve other chapters")
	if mode=="boxed":expect(slot.party.is_empty() and slot.boxes[0].mons.slice(1)==old.party,"deposit all twelve individuals intact")
	else:expect(slot.party==old.party and slot.boxes==old.boxes,"carry all twelve intact")
	game._close_all_dialogs()
	for mid in ["alola_cavern_den","alola_aether_mansion","alola_megalo_tower","alola_champion_room"]:
		game._do_warp({"map":mid,"region":"alola","at":[3,3]})
		expect(game.world.map_data.id=="alola_home","early access refused "+mid)
		game._close_all_dialogs()
	expect(not game._party_can_move("SURF") and not game._party_can_move("FLY"),"foreign moves do not replace local Ride registrations")
	game._do_warp(root.get_node("Data").travel_regions().ultra.hub)
	expect(game.world.map_data.region=="ultra","leave safely")
	expect(Start.open_trip(game,"alola"),"return using travel device")
	await process_frame
	expect(game.world.map_data.id=="alola_home" and not game._flags().get("a_starter",0),"return to unfinished prologue")
	game._persist()
	await title()
	game.title_screen.continue_button.pressed.emit()
	await process_frame
	expect(game._flags().a_version==version and not game._offer_chapter("alola"),"cold resume retains choice")

func combat() -> void:
	var battle=load("res://core/battle.gd").new(27)
	var mon:Dictionary=battle.make_combatant(25,40,[85,98])
	var ally:Dictionary=battle.make_combatant(26,40,[85])
	var foe:Dictionary=battle.make_combatant(143,90,[33])
	mon.held="ELECTRIUM_Z"
	ally.held="ELECTRIUM_Z"
	battle.alola_rules=true
	battle.start([mon,ally],[foe])
	expect(not battle.use_z("a",0).ok,"foreign crystal without local Z ring")
	battle.alola_ring=true
	expect(not battle.use_z("a",1).ok and battle.use_z("a",0).ok,"only electric move can use this crystal")
	var hp:=int(foe.hp)
	var pp:=int(mon.pp[0])
	battle.run_turn("z:0","move:0")
	expect(foe.hp<hp and int(mon.pp[0])==pp-1 and battle.alola_z_used.a,"Z attack hits and consumes one PP")
	battle.active_a=1
	expect(not battle.use_z("a",0).ok,"one Z attack for the entire team")
	expect(not battle.can_use_tera("a"),"no Terastallization in Alola")
	expect(battle.catch_bonus("究极球",1,battle.make_combatant(793,40,[33]))==5.0 and battle.catch_bonus("究极球",1,ally)<1.0,"Beast Ball targets Ultra Beasts")
	var double=load("res://core/double_battle.gd").new(28)
	double.alola_totem={"stat":"def","stages":1}
	double.alola_rules=true
	double.start([double.make_combatant(25,9,[33]),double.make_combatant(19,8,[33])],[double.make_combatant(735,40,[39]),double.make_combatant(734,10,[33])])
	expect(double.lanes.a==[0,-1] and double.lanes.b==[0,-1] and double.cur_b().stages.def==1,"Totem aura, player fights alone")
	double.round_actions({0:{"move":"move:0","target":0}})
	expect(double.lanes.b==[0,1] and double.lanes.a==[0,-1],"SOS ally joins after opening round")

func run() -> void:
	Save.use_test_slot()
	await title()
	var old:=fixture()
	Chapters.migrate(old)
	old.party[0].moves=[57,19]
	old.party[0].pp=[10,10]
	old=JSON.parse_string(JSON.stringify(old))
	for i in Field.VERSIONS.size():await arrival(old,Field.VERSIONS[i],"boxed" if i%2==1 else "carried")
	expect((Field.hour({"a_version":"moon"})-Field.hour({"a_version":"sun"})+24)%24==12,"opposite local clocks")
	expect(Field.hour({"a_version":"moon","a_reverse_world":true})==Field.hour({"a_version":"sun"}),"reverse-world clock")
	var growth=load("res://core/growth.gd")
	expect(growth.evolution_for_item({"species_id":25},"THUNDER_STONE","alola").form=="RAICHU_ALOLA","stone evolves Pikachu into Alolan Raichu")
	combat()
	game.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("ALOLA SHARED SAVE AND BATTLE ", "FAIL" if failed else "PASS"," checks=",checks)
	quit(1 if failed else 0)
