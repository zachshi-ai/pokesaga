extends "res://tools/test_region_journey.gd"
const UHOME := "unova_bw_home_2f"
const TITLE_DEST := {"region":"unova","map":"unova_champion_room","at":[4,6],"unova_native":true}

func first_visit(old: Dictionary, mode: String) -> void:
	expect(Save.save(old.duplicate(true)),"save the previous journey")
	await title()
	expect(await preload("regional_start.gd").enter(game,"unova",mode),"use the regional transfer and choose "+mode)
	expect(game.world.map_data.id==UHOME and game.world.player_pos==Vector2i(5,6),"start in the Nuvema bedroom")
	var slot: Dictionary=Save.existing()
	expect(slot.chapters.unova==mode and slot.flags.u1_started and not slot.flags.get("u2_started",false),"record only the first era")
	expect(slot.dex==old.dex and slot.badges==old.badges and slot.money==old.money and slot.hall_of_fame==old.hall_of_fame,"preserve earlier regions")
	if mode=="carried":
		expect(slot.party==old.party and slot.boxes==old.boxes,"keep the twelve exact Pokémon")
	else:
		expect(slot.party.is_empty() and slot.boxes[0].mons.slice(1)==old.party,"store all twelve with their individual condition")
	expect(not game._party_can_move("SURF") and not game._party_can_move("FLY"),"imported moves and badges cannot open field gates")
	expect(Chapters.begin_unova_sequel(slot,"carried").is_empty(),"cannot advance two years before Ghetsis")
	game._close_all_dialogs()
	game._do_warp(TITLE_DEST)
	expect(game.world.map_data.id==UHOME,"early League warp stopped")
	game._close_all_dialogs()
	game._persist()
	await title()
	game.title_screen.continue_button.pressed.emit()
	await process_frame
	expect(game.world.map_data.id==UHOME and not game._offer_chapter("unova"),"continue without repeating the deposit")

func verify_counter_and_feather() -> void:
	var side=load("res://core/unova_side.gd")
	var stores=load("res://core/unova_trainers.gd")
	var clerk={"name":"店员","shop":true,"unova_shop":255}
	game._talk_to_npc(clerk)
	var ui=game.menu_layer.get_child(-1)
	expect(ui.goods.size()==2 and ui.goods[0].name=="精灵球","first chapter starts with the local two-item shelf")
	var cash:=int(game.save_data.money)
	var count:=int(game._bag_count("精灵球"))
	ui._buy(0)
	expect(game._bag_count("精灵球")==count+1 and game.save_data.money==cash-200,"buy a ball at the original price")
	ui.closed.emit()
	ui.queue_free()
	game._flags().u1_badge_1=true
	expect(stores.goods(game,255).size()==11,"first local badge expands the primary counter")
	expect(stores.goods(game,0)[0].name=="初次邮件","first era secondary clerk has separate stock")
	game._flags().erase("u1_badge_1")
	side.give(game,"HEALTH_WING")
	var lead: Dictionary=game.save_data.party[0]
	var old:=int(lead.get("effort",{}).get("hp",0))
	game._use_bag_item("体力之羽")
	expect(press(game.menu_layer.get_child(-1),lead.name),"give the wing to an eligible party member")
	expect(int(lead.effort.hp)==old+1 and game._bag_count("体力之羽")==0,"wing increases actual effort and is consumed")
	game._close_all_dialogs()

func run() -> void:
	Save.use_test_slot()
	await title()
	var field=load("res://core/unova_field.gd")
	var old:=fixture()
	Chapters.migrate(old)
	old.regional_badges.erase("unova")
	old.party[0].moves=[57,19]
	old.party[0].pp=[10,10]
	old=JSON.parse_string(JSON.stringify(old))
	await first_visit(old,"carried")
	verify_counter_and_feather()
	await first_visit(old,"boxed")
	var one:=Chapters.begin(old,"unova","carried")
	one.flags.u1_ghetsis=true
	one.flags.u1_hm_3=true
	one.centers={"unova":{"region":"unova","map":"unova_bw_center","at":[4,8]}}
	Chapters.grant(one,"unova","基础徽章")
	var before:=JSON.stringify(one)
	for mode in ["carried","boxed"]:
		var two:=Chapters.begin_unova_sequel(one,mode)
		expect(JSON.stringify(one)==before and two.map==Chapters.SEQUEL_HOME.map,"two years later is an atomic transition")
		expect(two.flags.u1_ghetsis and two.flags.u2_started and not two.flags.get("u2_hm_3",false) and not two.centers.has("unova"),"keep first plot and reset local permits and recovery location")
		expect(two.regional_badges.unova==["基础徽章"] and Chapters.badges(two,"unova").is_empty(),"independent badges")
		expect(two.dex==one.dex and two.money==one.money and two.hall_of_fame==one.hall_of_fame,"shared records through the sequel")
		expect(two.party==one.party if mode=="carried" else two.boxes[0].mons.slice(1)==one.party,"retain attributes through sequel choice")
		expect(Chapters.begin_unova_sequel(two,"carried").is_empty(),"cannot repeat the arrival")
		expect(Chapters.switch_unova_memory(two).is_empty(),"memory stays locked until champion")
		two.flags.u2_champion=true
		Chapters.grant(two,"unova","基础徽章")
		two.centers.unova={"region":"unova","map":"unova_b2_center","at":[3,4]}
		var back:=Chapters.switch_unova_memory(two)
		expect(field.era(back.flags)=="bw" and back.centers.unova==one.centers.unova and back.map==UHOME,"return to completed first era")
		var present:=Chapters.switch_unova_memory(back)
		expect(field.era(present.flags)=="b2" and present.centers==two.centers and present.party==two.party and present.boxes==two.boxes,"return to Iris era with intact party, PC and Center")
	var box: Array=[]
	for i in 30:box.append({"species_id":25})
	one.boxes=[]
	for i in 200:one.boxes.append({"mons":box.duplicate(true)})
	before=JSON.stringify(one)
	expect(Chapters.begin_unova_sequel(one,"boxed").is_empty() and JSON.stringify(one)==before,"full boxes abort without losing anyone")
	game.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("UNOVA SHARED SAVE ", "FAIL" if failed else "PASS"," checks=",checks)
	quit(int(failed))
