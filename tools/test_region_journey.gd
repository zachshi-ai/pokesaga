extends SceneTree

const Save := preload("res://core/save_game.gd")
const Chapters := preload("res://core/region_journey.gd")
var game
var failed := false
var checks := 0

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("REGION JOURNEY: "+label)

func _initialize() -> void: run.call_deferred()

func title() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame

func press(page, label: String) -> bool:
	for b in page.find_children("*","Button",true,false):
		if b.is_visible_in_tree() and not b.disabled and b.text == label:
			b.pressed.emit()
			return true
	expect(false,"missing button "+label)
	return false

func fixture() -> Dictionary:
	var sample := OS.get_environment("POKESAGA_TRANSFER_SAVE")
	var old: Dictionary
	if sample != "":
		old = JSON.parse_string(FileAccess.get_file_as_string(sample))
	else:
		old = Save.empty()
		old.origin="johto"
		old.region="johto"
		old.map="johto_new_bark_town"
		old.pos=[8,10]
		old.money=9850
		old.flags={"johto_dex":true,"got_dex":true,"j_starter_species":158,"j2_badge_brock":true,"beat_brock":true}
		old.badges=["灰色徽章","飞翼徽章"]
		old.dex={"caught":[158],"seen":[158]}
		old.hall_of_fame={"johto":[{"species_id":158,"level":58}]}
	var count := 0
	for m in old.party:
		if m is Dictionary and not m.is_empty(): count+=1
	for i in range(count,12):
		var mon = load("res://core/party.gd").make(158,16+i,[10,55])
		mon.hp=5+i
		mon.reward_test_index=i
		if i==11:
			mon.shiny=true
			mon.shiny_kind="square"
			mon.held="剩饭"
		old.party.insert(count,mon)
		count+=1
	old.party=old.party.filter(func(m):return m is Dictionary and not m.is_empty())
	old.boxes=[{"name":"旧箱子","mons":[old.party[0].duplicate(true)]}]
	return JSON.parse_string(JSON.stringify(old))

func check_branch(old: Dictionary, mode: String, field: bool) -> void:
	expect(Save.save(old.duplicate(true)),"write disposable legacy slot")
	await title()
	game.title_screen.continue_button.pressed.emit()
	await process_frame
	game._close_all_dialogs()
	var region_before := str(game.world.map_data.region)
	var room_before := str(game.world.map_data.id)
	if not preload("regional_start.gd").open_trip(game,"hoenn"): return
	await process_frame
	if not field:
		game._on_back()
		await process_frame
		var cancelled := Save.existing()
		expect(game.world.map_data.region==region_before and game.world.map_data.id==room_before and not cancelled.chapters.has("hoenn") and cancelled.party==old.party,"cancelling departure leaves old region and party intact")
		if not preload("regional_start.gd").open_trip(game,"hoenn"): return
		await process_frame
	if not press(game.menu_layer,"乘坐搬家货车"): return
	await process_frame
	if not press(game.menu_layer,"寄存队伍，重新组队" if field else "带现有队伍出发"): return
	await process_frame
	for frame in 600:
		if not game._escort_active: break
		await process_frame
	var loaded := Save.existing()
	expect(loaded.origin=="johto" and loaded.region=="hoenn" and loaded.map=="em_inside_of_truck","same slot begins at the moving van")
	expect(game.world.map_data.id=="em_inside_of_truck" and game.world.player_pos==Vector2i(2,2),"actual playing location")
	expect(loaded.chapters.get("hoenn")==mode and loaded.chapters.has("johto"),"both chapters remain recorded")
	expect(loaded.flags.h_started and not loaded.flags.get("h_badge_1",false) and not loaded.flags.get("h_partner",false),"old power cannot complete Emerald events")
	expect(loaded.get("money")==old.money and loaded.hall_of_fame==old.hall_of_fame and loaded.dex==old.dex,"money, dex and earlier Hall of Fame retained")
	expect(loaded.badges==old.badges and Chapters.badges(loaded,"hoenn").is_empty() and "灰色徽章" not in Chapters.badges(loaded,"kanto"),"overlapping gym names cannot unlock another story")
	expect(not loaded.flags.get("beat_brock",false) and loaded.flags.get("j2_badge_brock",false),"Brock's Johto win stays in Johto")
	if mode=="boxed":
		expect(loaded.party.is_empty(),"all twelve slots emptied")
		expect(loaded.boxes[0].mons.slice(1)==old.party and loaded.boxes[0].mons[0]==old.boxes[0].mons[0],"entire party follows existing PC occupant in order")
	else:
		expect(loaded.party==old.party and loaded.boxes==old.boxes,"all carried mons, HP, PP, form and held items intact")
	expect(not FileAccess.file_exists(Save.slot+".previous"),"chapter transfer does not replace the original file with a new game")
	await title()
	game.title_screen.continue_button.pressed.emit()
	await process_frame
	expect(game.save_data.chapters.get("hoenn")==mode and not game._offer_chapter("hoenn"),"reload cannot register or deposit twice")

func run() -> void:
	Save.use_test_slot()
	await title()
	var old:=fixture()
	await check_branch(old,"carried",false)
	await check_branch(old,"boxed",true)
	var tight:=old.duplicate(true)
	var slots: Array=[]
	for n in 30: slots.append({"species_id":25})
	tight.boxes=[]
	for i in 200: tight.boxes.append({"mons":slots.duplicate(true)})
	tight.boxes[199].mons.pop_back()
	var before:=JSON.stringify(tight)
	expect(Chapters.begin(tight,"hoenn","boxed").is_empty() and before==JSON.stringify(tight),"a single free PC slot cannot cause partial deposits")
	game.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("UNIFIED REGIONAL JOURNEY ", "FAIL" if failed else "PASS", " checks=",checks)
	quit(int(failed))
