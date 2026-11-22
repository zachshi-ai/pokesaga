extends SceneTree

var Party: Script
var Growth: Script
const Save := preload("res://core/save_game.gd")
var Shop: Script
var PartyUI: Script
# Ordinary-form stone paths present in FireRed/LeafGreen and Emerald's evolution tables.
const CLASSIC_STONES := {
	"FIRE_STONE": [[37,38],[58,59],[133,136]],
	"WATER_STONE": [[61,62],[90,91],[120,121],[133,134],[271,272]],
	"THUNDER_STONE": [[25,26],[133,135]],
	"LEAF_STONE": [[44,45],[70,71],[102,103],[274,275]],
	"MOON_STONE": [[30,31],[33,34],[35,36],[39,40],[300,301]],
	"SUN_STONE": [[44,182],[191,192]],
}
const MARKETS := {
	"sinnoh":"sinnoh_canalave", "galar":"galar_hammerlocke", "hisui":"hisui_jubilife",
	"paldea":"paldea_mesagoza", "kitakami":"kitakami_mossui", "hoenn":"em_oldale_town_mart",
	"kalos":"kalos_ambrette"
}
var failed := false
var game
var db

func _initialize():
	call_deferred("run")

func expect(ok: bool, reason: String):
	if not ok:
		failed = true
		push_error(reason)

func button(parent: Node, text: String) -> Button:
	for b in parent.find_children("*", "Button", true, false):
		if b.text == text and not b.is_queued_for_deletion():
			return b
	expect(false, "Missing button " + text)
	return null

func tap(parent: Node, text: String):
	var b := button(parent, text)
	if b != null:
		b.pressed.emit()

func panel(kind: Script):
	for child in game.menu_layer.get_children():
		if child.get_script() == kind and not child.is_queued_for_deletion():
			return child
	expect(false, "Missing panel " + kind.resource_path)
	return null

func check_rules() -> void:
	var seen := {}
	var count := 0
	for sp in db.species.values():
		for form in [sp] + sp.get("forms", []):
			for rule in form.get("evolves", []):
				if rule.get("how") != "item":
					continue
				var form_id := "" if form == sp else str(form.key)
				var mon: Dictionary = Party.make(int(sp.id), 40, [33], form_id)
				if rule.has("sex"): mon.sex = rule.sex
				var target: Dictionary = Growth.evolution_for_item(mon, str(rule.item))
				expect(int(target.get("to", 0)) == int(rule.to) and target.get("form", "") == rule.get("form", ""), "Invalid target %s %s" % [sp.id, rule])
				expect(Party.evolve(mon, int(rule.to), str(rule.get("form", ""))), "Invalid destination %s" % rule)
				seen[rule.item] = true
				count += 1
	expect(seen.size() == 40 and seen.size() == db.evo_items.size() and count == 91, "Incomplete evolution coverage")
	for key in db.evo_items:
		expect(seen.has(key), "Unusable evolution item " + str(key))
	for id in [281, 361]:
		var mon: Dictionary = Party.make(id, 40, [])
		mon.sex = "female" if id == 281 else "male"
		expect(Growth.evolution_for_item(mon, "DAWN_STONE").is_empty(), "Wrong sex accepted for Dawn Stone")
	print("Evolution catalog: ", count, " rules, ", seen.size(), " unique items")

func check_classic_stones() -> void:
	var count := 0
	for stone in CLASSIC_STONES:
		for pair in CLASSIC_STONES[stone]:
			var mon: Dictionary = Party.make(pair[0], 20, [33])
			for region in ["kanto", "sevii", "johto", "hoenn"]:
				var target: Dictionary = Growth.evolution_for_item(mon, stone, region)
				expect(int(target.get("to", 0)) == pair[1] and target.get("form", "") == "", "Wrong stone target %s %s in %s" % [pair, stone, region])
			count += 1
	for pair in [[25,26,"THUNDER_STONE"],[102,103,"LEAF_STONE"]]:
		var mon: Dictionary = Party.make(pair[0], 20, [33])
		var stone: String = db.evo_item_name(pair[2])
		expect(Growth.evolution_for_item(mon, pair[2], "alola").is_empty(), "Mainland target unlocked in Alola")
		for form in db.species_of(pair[0]).get("forms", []):
			var special: Dictionary = Party.make(pair[0], 20, [33], form.key)
			expect(Growth.evolution_for_item(special, pair[2], "kanto").is_empty(), "Special form stone-evolved " + str(form.key))
		game.save_data.party = [mon]
		game._give_bag_item(stone, "evo")
		var amount: int = game._bag_count(stone)
		game._evolve_with_item(0, stone, null)
		expect(game.save_data.party[0].species_id == pair[1] and game.save_data.party[0].get("form", "") == "" and game._bag_count(stone) == amount - 1, "Stone or item consumption failed for %s" % pair[0])
	expect(count == 21, "Classic stone path count differs")
	print("Classic stones: ", count, " paths, four map regions and special-form restrictions verified")

func check_markets() -> void:
	var bought := {}
	game.save_data.money = 500000
	for region in MARKETS:
		if region=="hoenn":
			var travel := preload("regional_start.gd")
			expect(travel.open_trip(game,"hoenn"),"take regular transport to Hoenn")
			await process_frame
			expect(travel.press(game.menu_layer,"直接抵达"),"skip the optional moving van")
			await process_frame
			game._close_all_dialogs()
		var mid: String = MARKETS[region]
		game._do_warp({"region":region, "map":mid, "at":db.load_map(region, mid).spawn})
		game._close_all_dialogs()
		var clerk := {}
		for n in game.world.npcs:
			if n.get("shop", false):
				clerk = n
				break
		expect(not clerk.is_empty(), mid + " has no merchant")
		if clerk.is_empty(): continue
		var spot := Vector2i(clerk.at[0], clerk.at[1])
		var approached := false
		for dir in [Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT]:
			if not game.world.is_blocked(spot - dir):
				game.world.warp_to(spot - dir)
				game.world.facing = {Vector2i.UP:"up",Vector2i.DOWN:"down",Vector2i.LEFT:"left",Vector2i.RIGHT:"right"}[dir]
				game._on_action()
				approached = true
				break
		expect(approached, mid + " merchant is inaccessible")
		var shop = panel(Shop)
		if shop == null: continue
		var tab := button(shop, "进化材料产地")
		if tab != null: tab.button_pressed = true
		expect(shop.evolution_catalog.size() == 40, "Incomplete in-game catalog")
		var rejected := false
		for b in shop.rows.get_children():
			if b is Button and b.disabled and b.text.ends_with("有售"):
				rejected = true
				break
		expect(rejected, "Missing source label for an imported item")
		for i in shop.goods.size():
			var row: Dictionary = shop.goods[i]
			if not row.has("evo") or bought.has(row.evo): continue
			expect(str(row.get("region", region)) == region, "Wrong store for " + row.name)
			var money := int(game.save_data.money)
			var start := int(game._bag_count(row.name))
			shop._buy(i)
			shop._buy(i)
			expect(int(game.save_data.money) == money - 2 * int(row.price) and game._bag_count(row.name) == start + 2, "Broken repeat sale for " + row.name)
			bought[row.evo] = true
		tap(shop, "返回")
		await process_frame
	expect(bought.size() == 40, "Reachable markets only stocked %d items" % bought.size())
	print("Regional markets supplied ", bought.size(), " items, each purchased twice")

func collect_visible_item(region: String, mid: String, at: Vector2i):
	game._do_warp({"region":region, "map":mid, "at":db.load_map(region, mid).spawn})
	game._close_all_dialogs()
	for side in [Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT]:
		if not game.world.is_blocked(at - side):
			game.world.warp_to(at - side)
			game.world.facing = {Vector2i.UP:"up",Vector2i.DOWN:"down",Vector2i.LEFT:"left",Vector2i.RIGHT:"right"}[side]
			game._on_action()
			game._close_all_dialogs()
			return
	expect(false, "No approach to item in " + mid)

func check_field_equipment() -> void:
	var battle_script = load("res://core/battle.gd")
	var mon: Dictionary = Party.make(25, 50, [33])
	mon.berry = ""
	game.save_data.party = [mon]
	game.bag_items = []
	collect_visible_item("kanto", "mt_moon_1f", Vector2i(11,35))
	tap(game.menu_layer, "皮卡丘")
	game._close_all_dialogs()
	await process_frame
	var mv := int(db.tm_map["招式学习器 09"])
	var saved := Save.load_game()
	expect(saved.party[0].moves.has(float(mv)) and saved.party[0].pp.size() == 2 and int(saved.party[0].pp[1]) == int(db.move_of(mv).pp), "TM09 pickup, teaching or PP failed")
	collect_visible_item("kanto", "safarizone_north", Vector2i(29,17))
	game._open_party()
	var ui = panel(PartyUI)
	if ui == null: return
	ui._open_detail(0)
	tap(ui.detail, "携带物品 · 无")
	tap(ui.chooser, "先制之爪    ×1")
	await process_frame
	expect(game.save_data.party[0].held == "QUICK_CLAW" and game._bag_count("先制之爪") == 0, "Quick Claw pickup did not equip")
	game._on_back()
	game._on_back()
	await process_frame

	var a: Dictionary = battle_script.make_combatant(113, 50, [150])
	var b: Dictionary = battle_script.make_combatant(143, 50, [150])
	var duel = battle_script.new(13)
	duel.start([a],[b])
	a = duel.cur_a()
	b = duel.cur_b()
	var claw := false
	for seed_value in 80:
		a.held = "QUICK_CLAW"
		a.stats.spe = 1
		b.stats.spe = 130
		a.hp = a.max_hp
		b.hp = b.max_hp
		a.pp[0] = 30
		b.pp[0] = 30
		duel.rng.seed = seed_value
		duel.run_turn("move:0","move:0")
		if a.moved_first: claw = true; break
	expect(claw, "Quick Claw did not change action order")
	a.stats.atk = 220
	a.stats.spa = 220
	for pair in [["SILK_SCARF",33],["NEVER_MELT_ICE",58],["SEA_INCENSE",57],["BLACK_GLASSES",242]]:
		a.held = ""
		duel.rng.seed = 200
		var base := int(duel.damage(a,b,db.move_of(pair[1])))
		a.held = pair[0]
		duel.rng.seed = 200
		expect(duel.damage(a,b,db.move_of(pair[1])) > base, "Held power missing: " + pair[0])
	var old := [{"name":"ITEM_QUICK_CLAW","count":2},{"name":"先制之爪","count":1},{"name":"ITEM_TM09","count":1},{"name":"ITEM_HM07","count":1},{"name":"ITEM_X_DEFEND","count":3}]
	var fixed: Array = db.normalize_bag(old)
	expect(fixed.size()==4 and fixed[0].held=="QUICK_CLAW" and fixed[0].count==3 and fixed[1].category=="tm" and fixed[2].name=="秘传学习器 07" and fixed[3].name=="防御强化", "Legacy machine/held/battle item normalization")
	for boost in ["X_ATTACK","X_DEFEND","X_SPEED","X_ACCURACY","X_SPECIAL"]:
		var stat: String = duel.X_STAGES[boost]
		var before := int(a.stages.get(stat, 0))
		expect(duel.use_battle_item("a", boost) and a.stages[stat] == before+1, "Battle boost failed: "+boost)
	expect(duel.use_battle_item("a","GUARD_SPEC"), "Guard Spec activation")
	duel.acting_side = "b"
	var attack := int(a.stages.atk)
	duel._apply_stage(a,"atk",-1,duel.log)
	expect(a.stages.atk==attack and not duel.use_battle_item("a","GUARD_SPEC"), "Guard Spec prevention or duplicate consumption")
	for turn in 5: duel.run_turn("none","none")
	expect(duel.guard_turns.a == 0 and duel.use_battle_item("a","DIRE_HIT") and not duel.use_battle_item("a","DIRE_HIT"), "Booster duration or repeat use")
	var trainee: Dictionary = Party.make(25, 50, [33])
	trainee.held = "MACHO_BRACE"
	Growth.award_effort(trainee, 1)
	expect(int(trainee.effort.spa)==2, "Macho Brace effort")
	trainee.held = "SOOTHE_BELL"
	trainee.friendship = 70
	Growth.level_friendship(trainee)
	expect(trainee.friendship==77, "Soothe Bell friendship")
	print("Field pickups, taught move PP, Quick Claw, power items, training and battle boosts passed")

func check_battle_bag() -> void:
	game.save_data.party = [Party.make(25,50,[85])]
	game.bag_items = []
	collect_visible_item("kanto","s_s_anne_2_f_room4",Vector2i(2,4))
	expect(game._bag_count("力量强化")==1, "X Attack missing after pickup")
	game._start_battle({"name":"测试训练家", "battle":{"species":129,"level":2,"moves":[150]}})
	var view = game.active_battle
	for tick in 30:
		if view.state == "menu": break
		view._process(2.0)
	view._on_command_kind("bag")
	tap(view.sheet,"力量强化    ×1")
	expect(view.battle.cur_a().stages.atk==1 and game._bag_count("力量强化")==0, "Trainer battle UI failed to consume X Attack and raise attack")
	for tick in 100:
		if game.active_battle == null: break
		if view.state == "menu":
			view._on_command_kind("fight")
			view._on_move(0)
		view._process(2.0)
	expect(game.active_battle == null and game._bag_count("力量强化")==0, "Trainer battle did not finish")
	var stored := Save.load_game()
	expect(stored.bag.all(func(row): return row.name != "力量强化" or int(row.count)==0), "Used battle item reappeared in save")
	print("Picked up X Attack, consumed it in a trainer battle and verified its saved quantity")

func check_field_pickup() -> void:
	var map_id := "six_island_water_path"
	var spot := Vector2i(17, 87)
	game._do_warp({"region":"sevii", "map":map_id, "at":[17,86]})
	game._close_all_dialogs()
	var start := int(game._bag_count("龙之鳞片"))
	for side in [Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT]:
		if not game.world.is_blocked(spot - side):
			game.world.warp_to(spot - side)
			game.world.facing = {Vector2i.UP:"up",Vector2i.DOWN:"down",Vector2i.LEFT:"left",Vector2i.RIGHT:"right"}[side]
			break
	game._on_action()
	game._close_all_dialogs()
	expect(game._bag_count("龙之鳞片") == start + 1, "Sevii map did not award its dragon scale")
	game._on_action()
	game._close_all_dialogs()
	expect(game._bag_count("龙之鳞片") == start + 1, "Previously collected pickup was duplicated")

func check_legacy_and_ui() -> void:
	var mon: Dictionary = Party.make(117, 40, [55])
	game.save_data.party = [mon, Party.make(440, 10, [1])]
	game.bag_items = [{"name":"ITEM_DRAGON_SCALE", "category":"other", "count":1},
		{"name":"DRAGON_SCALE", "count":1}, {"name":"龙之鳞片","count":1},
		{"name":"ITEM_OVAL_STONE","count":1}, {"name":"ITEM_UP_GRADE","count":1}]
	game._persist()
	game._restore_from_save()
	game._close_all_dialogs()
	expect(game._bag_count("龙之鳞片") == 3 and game._bag_count("升级数据") == 1, "Legacy stacks failed to merge")
	var merged = db.normalize_bag(game.bag_items)
	expect(merged == game.bag_items, "Legacy bag migration is not idempotent")

	game._open_bag()
	var bag = game._bag_ui
	bag._switch("evo")
	var labels = bag.row_box.find_children("*", "Label", true, false)
	for label in labels:
		if label.text == "龙之鳞片":
			label.get_parent().pressed.emit()
			break
	tap(game.menu_layer, "海刺龙")
	await process_frame
	expect(game.save_data.party[0].species_id == 230 and game._bag_count("龙之鳞片") == 2, "Bag evolution did not consume one scale")
	expect(bag.row_box.find_children("*","Label",true,false).any(func(l): return l.text.begins_with("×2")), "Open bag shows stale quantity")
	bag.handle_back()
	await process_frame

	game._open_party()
	var ui = panel(PartyUI)
	if ui == null: return
	ui._open_detail(1)
	tap(ui.detail, "道具进化")
	tap(ui.chooser, "浑圆之石    ×1")
	tap(ui.chooser, "确认使用")
	await process_frame
	expect(game.save_data.party[1].species_id == 113 and game._bag_count("浑圆之石") == 0, "Party evolution failed")
	var saved := Save.load_game()
	expect(int(saved.party[0].species_id) == 230 and int(saved.party[1].species_id) == 113, "Evolution not persisted")
	game.save_data.party[1] = Party.make(440, 10, [])
	game._evolve_with_item(1, "浑圆之石", null)
	expect(game.save_data.party[1].species_id == 440, "Evolved using an empty stack")
	game._evolve_with_item(1, "龙之鳞片", null)
	expect(game._bag_count("龙之鳞片") == 2, "Wrong species consumed an item")
	print("Bag, party, legacy IDs, repeated save and empty-stack checks passed")

func run():
	Party = load("res://core/party.gd")
	Growth = load("res://core/growth.gd")
	Shop = load("res://scenes/shop_ui.gd")
	PartyUI = load("res://scenes/party_ui.gd")
	Save.use_test_slot()
	game = load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	db = root.get_node("Data")
	game.title_screen.new_button.pressed.emit()
	await process_frame
	game._close_all_dialogs()
	check_rules()
	await check_markets()
	check_field_pickup()
	await check_field_equipment()
	await check_legacy_and_ui()
	await process_frame
	game._on_back()
	game._on_back()
	await process_frame
	check_battle_bag()
	check_classic_stones()
	Save.clear_test_slot()
	print("EVOLUTION ITEMS ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
