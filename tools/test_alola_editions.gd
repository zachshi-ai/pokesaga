extends "res://tools/test_region_journey.gd"
const Timeline=preload("res://core/alola_editions.gd")
const Start=preload("regional_start.gd")

func switch(version:String,started:bool,mode:String="carried") -> void:
	game._close_all_dialogs()
	game._toggle_start_menu()
	press(game.start_menu,"工具")
	press(game.start_menu,"阿罗拉版本")
	await process_frame
	var names=preload("res://core/alola_field.gd")
	press(game.menu_layer.get_child(-1),names.TITLES[names.VERSIONS.find(version)]+("　继续巡礼" if started else "　开始巡礼"))
	if not started:
		await process_frame
		press(game.menu_layer.get_child(-1),"寄存队伍，重新组队" if mode=="boxed" else "带现有队伍出发")
	await process_frame

func run() -> void:
	Save.use_test_slot()
	await title()
	var legacy:=fixture()
	expect(Save.save(legacy),"old shared party")
	await title()
	expect(await Start.enter(game,"alola","carried","sun"),"start Sun with old party")
	var original:Dictionary=game.save_data
	var partner=load("res://core/party.gd").make(725,5,[10])
	partner.alola_partner=true
	game.save_data.boxes[0].mons.append(partner)
	game._flags().a_starter=725
	game._flags().a_z_ring=true
	game._flags().as_ub_complete=true
	game._flags().a_champion=true
	game._flags()["alola_1:5,4"]=true
	game.save_data.regional_badges.alola=["美乐美乐岛大考验"]
	game.save_data.get_or_add("hall_of_fame",{}).alola=[{"name":"首冠伙伴","level":60}]
	game._give_item("Ｚ手环",1,"key")
	game._persist()
	var purse:=int(game.save_data.money)
	await switch("ultra_moon",false,"boxed")
	expect(game._flags().a_version=="ultra_moon" and not game._flags().get("a_champion",false) and not game._flags().has("alola_1:5,4"),"new route and pickups have separate flags")
	expect(game.save_data.chapters.alola=="boxed" and game.save_data.party.is_empty() and game.save_data.boxes[0].mons.size()==14,"all twelve carried individuals deposited once")
	expect(not game._flags().get("a_z_ring",false) and game._bag_count("Ｚ手环")==0 and game.save_data.regional_badges.alola.is_empty(),"old ring, seal and beast case do not unlock a new route")
	var campaign=load("res://core/alola_campaign.gd")
	expect(campaign.partner(game.save_data).is_empty(),"old starter cannot take the new starter's place")
	game.save_data.money+=27
	game._flags().a_home=true
	game._persist()
	await switch("sun",true)
	expect(game._flags().a_version=="sun" and game._flags().a_champion and game._flags().as_ub_complete and game._flags()["alola_1:5,4"],"resume local individuals, quest chain and pickups")
	expect(game._bag_count("Ｚ手环")==1 and game.save_data.regional_badges.alola.size()==1 and game.save_data.hall_of_fame.alola[0].name=="首冠伙伴","restore original ring and Hall of Fame")
	expect(game.save_data.money==purse+27 and game.save_data.boxes[0].mons.size()==14 and int(campaign.partner(game.save_data).species_id)==725,"wallet and PC shared and starter identified by edition")
	await title()
	game.title_screen.continue_button.pressed.emit()
	await process_frame
	await switch("ultra_moon",true)
	expect(game._flags().a_home and game._flags().a_version=="ultra_moon" and game.save_data.boxes[0].mons.size()==14,"cold resume and switch preserve both stories")
	game.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("ALOLA EDITIONS ", "FAIL" if failed else "PASS"," checks=",checks)
	quit(1 if failed else 0)
