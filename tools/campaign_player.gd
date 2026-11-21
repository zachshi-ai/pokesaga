extends SceneTree
## Controller for the fresh-save campaign replay. Only accepts playable inputs.
const Save := preload("res://core/save_game.gd")
const DIR := {"u":"up","d":"down","l":"left","r":"right"}
var game
var world
var db
var mode := "travel"
var requested_ball := ""
var requested_species := 0
var turns := 0
var steps := 0
var obstruction := []
var fights := []
var lines := []
var problem := ""

func _initialize() -> void:
	call_deferred("run")

func current() -> Array:
	return [world.map_data.id, world.player_pos.x, world.player_pos.y]

func button(node: Node, prefix: String) -> Button:
	for child in node.find_children("*","Button",true,false):
		if child.is_visible_in_tree() and not child.disabled and str(child.text).begins_with(prefix):
			return child
	return null

func click(prefix: String) -> bool:
	if game.menu_layer.get_child_count() == 0:
		return false
	var b := button(game.menu_layer.get_child(-1),prefix)
	if b:
		b.pressed.emit()
	return b != null

func count_item(item_name: String) -> int:
	for item in game.bag_items:
		if item.name == item_name: return int(item.count)
	return 0

func soften_move(ui, enemy: Dictionary) -> int:
	if int(enemy.hp) < int(enemy.max_hp) * 0.65:
		return -1
	var mon: Dictionary = ui.battle.cur_a()
	var choice := -1
	var highest := 0.0
	for i in mon.moves.size():
		if int(mon.pp[i]) <= 0: continue
		var mv: Dictionary = db.move_of(int(mon.moves[i]))
		var power := int(mv.get("power", 0))
		if power <= 0 or power > 90: continue
		var special := str(mv.get("category", "")) == "special"
		var offense := float(mon.get("stats", {}).get("spa" if special else "atk", 1))
		var defense := maxf(1.0, float(enemy.get("stats", {}).get("spd" if special else "def", 1)))
		var stab := 1.5 if str(mv.type) in mon.types else 1.0
		var damage: float = ((2.0 * int(mon.level) / 5.0 + 2) * power * offense / defense / 50.0 + 2) * stab * ui.battle.effectiveness_on(str(mv.type), enemy)
		if damage > highest and damage < float(enemy.hp) * 0.6:
			choice = i
			highest = damage
	return choice

func battle() -> void:
	var ui = game.active_battle
	var wild: bool = str(ui.trainer_name).is_empty()
	var enemy: Dictionary = ui.battle.cur_b()
	var owned: bool = game.save_data.dex.caught.any(func(n): return int(n) == int(enemy.species_id))
	var capture: bool = wild and mode == "collect" and not owned
	for frame in 3500:
		if game.active_battle == null: break
		if ui.state == "menu":
			turns += 1
			var ball := ""
			if wild and mode=="throw" and (requested_species==0 or int(enemy.species_id)==requested_species) and count_item(requested_ball)>0:
				ball=requested_ball
			elif capture:
				for kind in ["超级球","精灵球","高级球"]:
					if count_item(kind) > 0:
						ball = kind
						break
			var weaken := soften_move(ui, enemy) if capture and ball != "" else -1
			if weaken >= 0:
				ui._on_command_kind("fight")
				ui._on_move(weaken)
			elif ball != "":
				ui._on_command_kind("bag")
				var throw_button := button(ui.get_node("BallPanel"), ball)
				if not throw_button:
					problem = "Missing ball control " + ball
					return
				throw_button.pressed.emit()
			elif wild and mode != "train":
				ui._on_command_kind("flee")
			else:
				var mon: Dictionary = ui.battle.cur_a()
				var best := -1
				var high := -1.0
				for i in mon.moves.size():
					if int(mon.pp[i]) <= 0: continue
					var mv: Dictionary = db.move_of(int(mon.moves[i]))
					var stab := 1.5 if str(mv.type) in mon.types else 1.0
					var power: float = float(mv.get("power",0)) * stab * ui.battle.effectiveness_on(str(mv.type),ui.battle.cur_b())
					if str(mv.get("key","")) in ["SELF_DESTRUCT","EXPLOSION","MISTY_EXPLOSION"]:
						power = 0.0
					if power > high:
						best = i
						high = power
				ui._on_command_kind("fight")
				ui._on_move(maxi(0,best))
		ui._process(5.0)
	if game.active_battle != null:
		problem = "Battle did not finish: " + str(ui.trainer_name)
		return
	if not wild or ui.battle.winner in ["caught","b"] or ui.battle.fishing_encounter:
		fights.append([str(ui.trainer_name),enemy.name,enemy.level,ui.battle.winner])
	await process_frame

func settle() -> void:
	for tick in 1200:
		if problem: return
		if is_instance_valid(game.active_battle):
			await battle()
		elif not game._dialogs.is_empty():
			var dlg = game._dialogs.back()
			var line = dlg.lines[clampi(dlg.index - 1,0,dlg.lines.size()-1)] if not dlg.lines.is_empty() else ""
			if lines.is_empty() or lines.back() != line:
				lines.append(line)
			if dlg.is_waiting_answer(): dlg.btn_yes.pressed.emit()
			else: game._on_action()
		elif game._escort_active or (world.map_data.id == "johto_azalea_gym" and game.panel_open > 0 and preload("res://core/hgss_azalea.gd").data().pads.any(func(at): return world.player_pos==Vector2i(int(at[0]),int(at[1])))):
			await process_frame
		else:
			return
	problem = "Dialog or movement never finished"

func status() -> Dictionary:
	var mons := []
	for mon in game.save_data.party:
		if mon is Dictionary and not mon.is_empty():
			mons.append([mon.name,mon.species_id,mon.level,mon.hp,mon.max_hp,mon.moves,mon.pp])
	var items := {}
	for it in game.bag_items:
		if int(it.count)>0: items[it.name] = it.count
	var panels := []
	if game.panel_open > 0 and game.menu_layer.get_child_count() > 0:
		for b in game.menu_layer.get_child(-1).find_children("*","Button",true,false):
			if b.is_visible_in_tree() and not b.disabled: panels.append(b.text)
	return {"pos":current(),"party":mons,"bag":items,"flags":game._flags().keys().filter(func(k): return game._flags()[k]),
		"badges":game.save_data.badges,"money":game.save_data.money,"dex":game.save_data.dex.caught,"defeated":game.save_data.get("defeated",{}),
		"actors":world.npcs.map(func(n):return [n.at,n.get("role",""),n.get("name",""),n.get("shop",false),n.get("legacy_at",n.at),n.get("story_map",world.map_data.id),n.get("heal",false),n.get("hgss_source","")]),
		"bins":[game._flags().get("surge_bin",-1),game._flags().get("surge_second_bin",-1)],"history":game.save_data.get("return_passages",{}),"buttons":panels,"panels":game.panel_open,"held":game.save_data.party.map(func(m):return m.get("held","")),"problem":problem,"fights":fights,
		"dialog":lines,"turns":turns,"steps":steps,"obstruction":obstruction,"hall":game.save_data.get("hall_of_fame",{})}

func act(cmd: Dictionary) -> void:
	match str(cmd.action):
		"walk":
			for leg in cmd.legs:
				var before := current()
				world.tick_walk(1.0)
				game._move(DIR[leg[0]])
				world.tick_walk(1.0)
				await settle()
				if game.panel_open > 0 and lines.any(func(t):return "捡到了" in str(t)):
					game._on_back()
					await process_frame
				steps += 1
				var expected: Array = leg[1]
				if world.map_data.id != expected[0] or world.player_pos != Vector2i(int(expected[1]),int(expected[2])) or game.panel_open > 0 or problem:
					obstruction = [before,leg[0],expected]
					break
		"turn":
			# A directional press against an unwalkable tile turns the field sprite.
			world.tick_walk(1.0)
			game._move(DIR[cmd.dir])
			world.tick_walk(1.0)
		"face":
			# Attempting to walk against the person, counter, tree or wall turns to face it.
			world.tick_walk(1.0)
			world.facing = DIR[cmd.dir]
			game._on_action()
		"click":
			if not click(cmd.label): problem = "Missing button: " + str(cmd.label)
		"back": game._on_back()
		"hm": game._open_hm()
		"throw_with":
			requested_ball=cmd.item
			requested_species=int(cmd.get("species",0))
			mode="throw"
		"equip":
			game._open_party()
			var team=game.menu_layer.get_child(-1)
			team._open_detail(int(cmd.slot))
			if not click("携带物品") or not click(cmd.item):
				problem="Missing held item "+str(cmd.item)
			while is_instance_valid(team) and not team.is_queued_for_deletion(): team.handle_back()
		"lead":
			game._open_party()
			var party_ui = game.menu_layer.get_child(-1)
			var slot := int(cmd.slot)
			if slot > 0 and slot < party_ui.party.size() and not party_ui.party[slot].is_empty():
				party_ui._open_detail(slot)
				click("设为首发")
			party_ui.handle_back()
		"deposit":
			game._open_pc()
			var pc = game.menu_layer.get_child(-1)
			pc._mode(true)
			var slot := int(cmd.slot)
			if slot >= 0 and slot < pc.contents.get_child_count() and pc.contents.get_child(slot) is Button:
				pc.contents.get_child(slot).pressed.emit()
			else:
				problem = "No party member at slot %d" % slot
			pc.handle_back()
		"use", "key_item":
			game._open_bag()
			var bag = game._bag_ui
			var item_name := str(cmd.item)
			var row_index := -1
			for row in bag.items:
				if str(row.name) != item_name or int(row.count) <= 0: continue
				bag._switch(bag._category(row))
				for label in bag.row_box.find_children("*", "Label", true, false):
					if label.text == item_name and not label.get_parent().is_queued_for_deletion():
						label.get_parent().pressed.emit()
						row_index = int(cmd.get("slot", 0))
						break
				break
			if cmd.action == "key_item" and row_index >= 0:
				pass
			elif row_index >= 0 and row_index < game.save_data.party.size():
				var mon: Dictionary = game.save_data.party[row_index]
				if mon.is_empty() or not click(str(mon.name) + " "):
					problem = "Cannot use " + item_name + " on party member"
			else:
				problem = "Item absent from bag: " + item_name
			if cmd.action == "use" and is_instance_valid(bag): bag.handle_back()
		"mode": mode = str(cmd.value)
		"save": game._persist()
		"shop":
			var shop = game.menu_layer.get_child(-1)
			if shop.get_script() != load("res://scenes/shop_ui.gd"):
				problem = "Player is not shopping"
				return
			for i in shop.goods.size():
				if shop.goods[i].name == cmd.item:
					for j in int(cmd.amount):
						shop._buy(i)
					break
		"status": pass
		_: problem = "Unknown controller input"
	await settle()

func run() -> void:
	var folder := OS.get_environment("POKESAGA_CHAPTER_TEST_DIR")
	if not folder.is_absolute_path():
		quit(1)
		return
	Save.slot = folder.path_join("save.json")
	var calendar := OS.get_environment("POKESAGA_CHAPTER_TEST_DATE")
	if calendar!="":
		var day := Time.get_datetime_dict_from_datetime_string(calendar,true)
		preload("res://core/johto_rival.gd").local_date = func(): return day
	seed(843)
	game = load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	world = game.world
	db = root.get_node("Data")
	if OS.get_cmdline_user_args().has("new-johto"):
		if game.title_screen.continue_button != null:
			push_error("Johto new-game replay requires an empty slot")
			quit(1)
			return
		game.title_screen.johto_button.pressed.emit()
	elif game.title_screen.continue_button == null:
		push_error("First chapter save missing")
		quit(1)
		return
	else:
		game.title_screen.continue_button.pressed.emit()
	await process_frame
	game.rng.seed = 843
	game.appearance_rng.seed = 933
	while true:
		print("STATE ",JSON.stringify(status()))
		var line := OS.read_string_from_stdin(131072).strip_edges()
		if line.is_empty(): break
		var cmd = JSON.parse_string(line)
		if cmd.action == "quit": break
		fights.clear()
		obstruction.clear()
		lines.clear()
		problem = ""
		await act(cmd)
		await process_frame
		if cmd.action in ["back","key_item","click","use","hm","lead"]:
			await process_frame  # Finish disposing the menu before another button press.
	preload("res://core/johto_rival.gd").local_date = Time.get_date_dict_from_system
	quit()
