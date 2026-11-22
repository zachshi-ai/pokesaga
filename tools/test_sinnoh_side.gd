extends SceneTree
## Exercise Platinum rewards from real field actors, A/touch menus and the shared save.
var Side
const Save=preload("res://core/save_game.gd")
var Party
var game
var world
var failed:=PackedStringArray()
var checks:=0

func _initialize():call_deferred("run")

func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failed.append(label)
		push_error(label)

func switch(header: String):
	var mid: String=Side.maps()["MAP_HEADER_"+header]
	var map: Dictionary=root.get_node("Data").load_map("sinnoh",mid)
	world.load_map(map)
	world.refresh_story_actors(game._flags())
	game._apply_defeated()

func find_row(script: String) -> Dictionary:
	for row in world.npcs+world.objects:
		if Side.script_of(row)==script:return row
	return {}

func interact(script: String) -> bool:
	var exists:=false
	for row in world.npcs+world.objects:
		if Side.script_of(row)!=script:continue
		exists=true
		var at:=Vector2i(int(row.at[0]),int(row.at[1]))
		for pair in [[Vector2i.DOWN,"up"],[Vector2i.LEFT,"right"],[Vector2i.RIGHT,"left"],[Vector2i.UP,"down"]]:
			var pos:=at+Vector2i(pair[0])
			if not world.is_blocked(pos):
				world.warp_to(pos)
				world.facing=pair[1]
				game._on_action()
				return true
	if not exists:
		check(false,"missing field actor "+script)
		return false
	check(false,"no adjacent approach "+script)
	return false

func click(part: String) -> bool:
	var ui=game.menu_layer.get_child(-1)
	for b in ui.find_children("*","Button",true,false):
		if str(b.text).contains(part) and not b.disabled:
			b.pressed.emit()
			return true
	check(false,"touch button "+part)
	return false

func run():
	Side=load("res://core/sinnoh_side.gd")
	Party=load("res://core/party.gd")
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await preload("regional_start.gd").enter(game,"sinnoh")
	world=game.world
	game._close_all_dialogs()
	var party: Array=Party.compact([Party.make(66,15,[2]),Party.make(400,18,[33])])
	game.save_data.party=party
	check(not Side.field_unlocked(game,"ROCK_SMASH"),"foreign move or party cannot open map")
	switch("OREBURGH_GATE_1F")
	interact("OreburghGate1F_Hiker")
	game._close_all_dialogs()
	check(game._bag_count("神奥秘传学习器 06")==1,"Hiker gives first machine via A")
	interact("OreburghGate1F_Hiker")
	game._close_all_dialogs()
	check(game._bag_count("神奥秘传学习器 06")==1,"repeat does not duplicate HM")
	game._use_bag_item("神奥秘传学习器 06")
	click("腕力")
	game._close_all_dialogs()
	check(game.save_data.party[0].moves.has(249) and not Side.field_unlocked(game,"ROCK_SMASH"),"teaching works before badge but field stays closed")
	game._flags().s_badge_1=true
	check(Side.field_unlocked(game,"ROCK_SMASH"),"local badge unlocks field for known move")
	switch("OREBURGH_CITY_NORTH_HOUSE_1F")
	interact("OreburghCityNorthHouse1F_SchoolKidF")
	click("腕力")
	game._close_all_dialogs()
	check(int(game.save_data.party[0].species_id)==63 and game.save_data.party[0].name=="Kazza","Machop is replaced once by traded Abra in same slot")
	check(Side.gate(game,{"map":Side.maps().MAP_HEADER_FLOWER_PARADISE})!="","locked flower paradise blocks regional shortcut")
	switch("ROUTE_217")
	interact("VisibleItems_Route217_HM08")
	game._close_all_dialogs()
	check(game._bag_count("神奥秘传学习器 08")==1 and find_row("VisibleItems_Route217_HM08").is_empty(),"Rock Climb pickup in snow hides only after collection")
	switch("SOLACEON_RUINS_ROOM_7")
	interact("VisibleItems_SolaceonRuinsRoom7_HM05")
	game._close_all_dialogs()
	check(game._bag_count("神奥秘传学习器 05")==1,"Defog in last room")
	switch("IRON_ISLAND")
	interact("IronIsland_Riley")
	game._close_all_dialogs()
	check(game._bag_count("神奥秘传学习器 04")==1,"Riley gives Strength outside mine")
	switch("HEARTHOME_CITY_NORTHWEST_HOUSE")
	interact("HearthomeCityNorthwestHouse_Bebe")
	click("好")
	game._close_all_dialogs()
	check(Side.with_species(game,133) and game._flags().get("s_bebe_eevee",false),"Bebe gives level 20 Eevee")
	switch("POKEMON_MANSION_OFFICE")
	interact("PokemonMansionOffice_Book")
	game._close_all_dialogs()
	check(game.save_data.dex.seen.has(490) and not game.save_data.dex.caught.has(490),"Manaphy illustration registers seen only")
	switch("JUBILIFE_CITY_MART")
	game._flags().s_dex=true
	world.refresh_story_actors(game._flags())
	interact("MysteryGiftDeliveryman_Deliveryman")
	click("秘密钥匙")
	game._close_all_dialogs()
	check(game._bag_count("秘密钥匙")==1 and Side.gate(game,{"map":Side.maps().MAP_HEADER_ROTOMS_ROOM})=="","Mystery Gift delivered in shop unlocks specific room")
	switch("ETERNA_CITY_UNDERGROUND_MAN_HOUSE")
	interact("EternaCityUndergroundManHouse_UndergroundMan")
	game._close_all_dialogs()
	switch("ETERNA_CITY")
	game._use_bag_item("探险套装")
	if click("调查岩壁"):
		var cells: Array=game.menu_layer.get_child(-1).find_children("*","GridContainer",true,false)
		if not cells.is_empty():
			check(cells[0].get_child_count()==20,"twenty touch excavation cells")
			cells[0].get_child(0).pressed.emit()
			check(int(game.save_data.sinnoh_underground.wall.hits)==14,"dig consumes wall strength")
		click("离开岩壁")
		click("回到地面")
	check(Side.give_egg(game,175,"s_side_test_egg") and Side.give_egg(game,447,"s_side_test_egg_riley"),"two independent gifts can incubate together")
	game._close_all_dialogs()
	game.save_data.sinnoh_eggs[0].steps=1
	Side.tick_eggs(game)
	game._close_all_dialogs()
	check(Side.with_species(game,175) and Side.egg_count(game.save_data)==1 and int(game.save_data.get("s_eggs_hatched",0))==1,"hatch one egg without clearing another")
	extra_checks()
	service_checks()
	game._persist()
	var read: Dictionary=Save.load_game()
	check(read.flags.get("s_pick_VisibleItems_Route217_HM08",false) and read.flags.get("s_trade_OreburghCityNorthHouse1F_SchoolKidF",false) and read.flags.get("s_secret_key",false) and read.sinnoh_eggs.size()==1,"pickup, trade and egg progress survive disk roundtrip")
	Save.clear_test_slot()
	game.queue_free()
	await process_frame
	print("Platinum side events ",checks," checks ", "PASS" if failed.is_empty() else "FAIL", " ", failed)
	quit(0 if failed.is_empty() else 1)

func extra_checks():
	# Replay postgame interactions from the same new save, with main story
	# prerequisites supplied by the separate end-to-end campaign playthrough.
	var campaign: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/sinnoh_campaign.json"))
	for event in campaign.events:game._flags()[event.id]=true
	game._flags().s_starter=387
	switch("PASTORIA_CITY_OBSERVATORY_GATE_1F")
	game.save_data.money=1300
	check(Side.gate(game,{"map":Side.maps().MAP_HEADER_GREAT_MARSH_6})!="","Marsh entry cannot bypass admission")
	interact("PastoriaCityObservatoryGate1F_CashierM")
	click("开始游猎")
	game._close_all_dialogs()
	check(Side.source(game)=="GREAT_MARSH_6" and int(game.save_data.money)==800 and int(game.save_data.s_marsh.balls)==30,"purchased Marsh visit arrives in Area 6 with 30 balls")
	game._start_wild_battle(194,25)
	var safari=game.menu_layer.get_node_or_null("SinnohSafariEncounter")
	check(is_instance_valid(safari) and game.active_battle==null,"normal encounter becomes a Safari encounter")
	if is_instance_valid(safari):safari.action_chosen.emit("run")
	game.save_data.s_marsh.steps=1
	Side.step(game)
	game._close_all_dialogs()
	check(Side.source(game)=="PASTORIA_CITY_OBSERVATORY_GATE_1F" and not game.save_data.has("s_marsh"),"last step returns through gate and removes unused balls")
	switch("MINING_MUSEUM")
	Side.give(game,"SKULL_FOSSIL")
	interact("MiningMuseum_FossilResearcher")
	click(Side.item_name("SKULL_FOSSIL"))
	game._close_all_dialogs()
	check(game._bag_count(Side.item_name("SKULL_FOSSIL"))==0 and int(game._flags().s_fossil_pending)==408,"museum takes only the selected fossil")
	switch("OREBURGH_CITY")
	Side.step(game)
	switch("MINING_MUSEUM")
	interact("MiningMuseum_FossilResearcher")
	game._close_all_dialogs()
	check(Side.with_species(game,408) and int(game._flags().s_fossil_pending)==0,"returning to researcher yields Cranidos")
	switch("FLOAROMA_MEADOW")
	Side.give(game,"HONEY")
	interact("Platinum_HoneyTree")
	click("涂蜜")
	game._close_all_dialogs()
	check(game._bag_count(Side.item_name("HONEY"))==0 and game.save_data.has("sinnoh_honey"),"Honey applied to original field model, retained on save")
	switch("POKEMON_MANSION_OFFICE")
	game._flags().s_dex=true
	game._flags().s_champion=true
	game._flags().erase("s_national_dex")
	switch("SANDGEM_TOWN_POKEMON_RESEARCH_LAB")
	interact("SandgemTownLab_ProfRowan")
	game._close_all_dialogs()
	check(not game._flags().get("s_national_dex",false),"championship alone cannot unlock national dex")
	var record: Array=Side.data().dex.duplicate()
	game.save_data.dex.seen=record
	game._flags().erase("s_champion")
	game._flags().erase("s_visited_sinnoh_eterna")
	interact("SandgemTownLab_ProfRowan")
	game._close_all_dialogs()
	check(not game._flags().get("s_national_dex",false),"previous regions' complete sightings cannot skip the first Eterna visit")
	game._flags().s_visited_sinnoh_eterna=true
	interact("SandgemTownLab_ProfRowan")
	game._close_all_dialogs()
	check(game._flags().get("s_national_dex",false) and game._bag_count("宝可追踪")==1,"Rowan checks all 210 distinct regional sightings")
	game._flags().s_champion=true # Resume the postgame fixture for the remaining excursions.
	switch("CANALAVE_CITY_SAILOR_ELDRITCH_HOUSE")
	interact("CanalaveCitySailorEldritchHouse_LittleBoy")
	game._close_all_dialogs()
	check(game._flags().get("s_sailor_son",false),"nightmare starts only after national dex")
	switch("CANALAVE_CITY")
	interact("CanalaveCity_SailorEldritch")
	click("满月岛")
	game._close_all_dialogs()
	check(Side.source(game)=="FULLMOON_ISLAND","talk to the father and sail to Fullmoon")
	switch("FULLMOON_ISLAND_FOREST")
	interact("FullmoonIslandForest_Cresselia")
	game._close_all_dialogs()
	check(game.save_data.get("sinnoh_roamers",{}).has("488") and find_row("FullmoonIslandForest_Cresselia").is_empty(),"Cresselia leaves and becomes a persistent roamer")
	interact("VisibleItems_FullmoonIslandForest_LunarWing")
	game._close_all_dialogs()
	check(game._bag_count(Side.item_name("LUNAR_WING"))==1,"lunar wing becomes reachable only after Cresselia leaves")
	switch("CANALAVE_CITY_SAILOR_ELDRITCH_HOUSE")
	interact("CanalaveCitySailorEldritchHouse_LittleBoy")
	game._close_all_dialogs()
	check(game._bag_count(Side.item_name("LUNAR_WING"))==0 and game._flags().get("s_son_cured",false),"lunar wing is consumed by waking the child")
	switch("JUBILIFE_CITY_MART")
	interact("MysteryGiftDeliveryman_Deliveryman")
	click("命运相遇")
	game._close_all_dialogs()
	var tgt: Dictionary=Side.destination(game,{"region":"sinnoh","map":Side.maps().MAP_HEADER_ROUTE_228_ROCK_PEAK_RUINS})
	check(tgt.map==Side.maps().MAP_HEADER_ROCK_PEAK_RUINS,"fateful Regigigas opens the original event chamber")
	switch("ROCK_PEAK_RUINS")
	for event in world.map_data.get("coord_events",[]):
		if str(event.get("source_script","")).contains("_Dot"):
			world.warp_to(Vector2i(int(event.at[0]),int(event.at[1])))
			Side.step(game)
	check(game.save_data.get("s_regi_floor",{}).get("dots",[]).size()==7,"all seven actual floor panels light individually")

func service_checks():
	var services=load("res://core/sinnoh_services.gd")
	game._close_all_dialogs()
	switch("JUBILIFE_CITY_MART")
	game.save_data.money=5000
	var before:=int(game._bag_count("精灵球"))
	check(services.goods(Side,"JubilifeCityMart_CommonVendor",{}).has("POKE_BALL") and not services.goods(Side,"JubilifeCityMart_CommonVendor",{}).has("ULTRA_BALL"),"fresh Sinnoh shop keys use local badge count")
	check(services.goods(Side,"JubilifeCityMart_SpecialtyVendor",{}).has("HEAL_BALL"),"adjacent vendor sells Jubilife's specialty")
	interact("JubilifeCityMart_CommonVendor")
	click("精灵球")
	click("10 件")
	check(game._bag_count("精灵球")==before+10 and game.save_data.money==3000 and game._bag_count(Side.item_name("PREMIER_BALL"))>0,"buy ten common balls, pay the actual price, receive one Premier Ball")
	switch("JUBILIFE_CITY_POKECENTER_1F")
	var actor: Dictionary=find_row("JubilifeCityPokecenter1F_Nurse")
	var n:=Vector2i(int(actor.at[0]),int(actor.at[1]))
	game.save_data.party[0].hp=1
	world.warp_to(n+Vector2i.DOWN*2)
	world.facing="up"
	game._on_action()
	if not game._dialogs.is_empty():
		game._dialogs[-1].answered.emit(true)
	game._close_all_dialogs()
	check(int(game.save_data.party[0].hp)==int(game.save_data.party[0].max_hp),"nurse accessed from the public side of the center counter restores party")
	interact("Platinum_StoragePC")
	var pc=game.menu_layer.get_child(-1)
	var has_pc: bool=pc.get_script()!=null and pc.get_script().resource_path=="res://scenes/pc_ui.gd"
	check(has_pc,"A on the center PC tile opens the shared storage UI")
	if has_pc:pc.closed.emit()
	game._close_all_dialogs()
	switch("ROUTE_209_LOST_TOWER_5F")
	interact("Route209LostTower5F_OldWoman1")
	game._close_all_dialogs()
	check(not game._flags().get("s_gift_Route209LostTower5F_OldWoman1",false),"lost tower elder withholds Spell Tag in fog")
	var bird: Dictionary=Party.make(398,45,[432])
	game.save_data.party=Party.compact([bird])
	game._flags().s_badge_3=true
	game._flags().s_hm_5=true
	Side.teach(game,5)
	click("在这里使用")
	game._close_all_dialogs()
	interact("Route209LostTower5F_OldWoman1")
	game._close_all_dialogs()
	interact("Route209LostTower5F_OldWoman2")
	game._close_all_dialogs()
	check(game._flags().get("s_defog_lost_tower",false) and game._bag_count(Side.item_name("CLEANSE_TAG"))>0 and game._bag_count(Side.item_name("SPELL_TAG"))>0,"using locally unlocked Defog unlocks both distinct fifth-floor rewards")
	switch("ROUTE_214")
	var base: Dictionary={"region":"sinnoh","map":Side.maps().MAP_HEADER_RUIN_MANIAC_CAVE_SHORT}
	for i in 9:game.save_data.dex_variants["201|UNOWN_%s|none|"%char(65+i)]=1
	check(Side.destination(game,base).map==Side.maps().MAP_HEADER_RUIN_MANIAC_CAVE_SHORT,"nine distinct letters keep short excavation")
	game.save_data.dex_variants["201|UNOWN_J|none|"]=1
	check(Side.destination(game,base).map==Side.maps().MAP_HEADER_RUIN_MANIAC_CAVE_LONG,"tenth distinct letter grows cave")
	for i in 26:game.save_data.dex_variants["201|UNOWN_%s|none|"%char(65+i)]=1
	check(Side.destination(game,base).map==Side.maps().MAP_HEADER_MANIAC_TUNNEL,"twenty-six independently seen letters finish tunnel")
	switch("SOLACEON_RUINS_MANIAC_TUNNEL_ROOM")
	check(Side.wild_form(game,201,"") in ["UNOWN_EXCLAMATION","UNOWN_QUESTION"],"secret room rolls only punctuation forms")
	switch("SURVIVAL_AREA")
	game._flags().s_stark_finished=true
	switch("BATTLEGROUND")
	var offered:=find_row("Battleground_Trainer1")
	check(offered.has("s_club") and offered.get("name","") in Side.CLUB_NAMES,"daily battleground actor uses a named original trainer")
	switch("IRON_ISLAND_B2F_LEFT_ROOM")
	game._flags().s_riley_joined=true
	game._flags().s_iron_won=false
	var pp:=int(game.save_data.party[0].pp[0])
	game.save_data.party[0].hp=1
	game.save_data.party[0].pp[0]=0
	Side.heal_companions(game)
	check(int(game.save_data.party[0].hp)==int(game.save_data.party[0].max_hp) and int(game.save_data.party[0].pp[0])==pp,"active Riley restores health and PP on his floor")
	switch("FOOTSTEP_HOUSE")
	game.save_data.party[0].friendship=255
	interact("FootstepHouse_DrFootstep")
	game._close_all_dialogs()
	check(game.save_data.party[0].get("sinnoh_awards",[]).has("足迹奖章"),"footprint ribbon attaches to the qualifying individual")
	switch("POKETCH_CO_1F")
	interact("PoketchCo1F_PoketchCoPresident")
	game._close_all_dialogs()
	check(game.save_data.get("s_apps",[]).has("备忘录"),"Poketch president installs first earned app")
	switch("SPEAR_PILLAR")
	game._flags().s_national_dex=true
	Side.give(game,"AZURE_FLUTE")
	var origin: Array=world.map_data.platinum_origin
	world.warp_to(Vector2i(31-int(origin[0]),52-int(origin[1])))
	game._use_bag_item(Side.item_name("AZURE_FLUTE"))
	click("吹奏")
	check(Side.source(game)=="HALL_OF_ORIGIN" and game._flags().get("s_flute_played",false),"authorized Azure Flute event changes map at original Spear Pillar tablet")
