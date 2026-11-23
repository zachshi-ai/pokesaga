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
var z_inputs := 0
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
	if int(enemy.hp) < int(enemy.max_hp) * 0.3:
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

func matchup_move(ui,paired: bool) -> Array:
	var best: Array=[-1,0]
	var highest:=-1.0
	for lane in (2 if paired else 1):
		if paired:
			if not ui.battle.viable("b",lane):continue
			ui.target_buttons[lane].pressed.emit()
		var mon: Dictionary=ui.battle.cur_a()
		var foe: Dictionary=ui.battle.cur_b()
		for index in mon.moves.size():
			if mon.pp[index]<=0:continue
			var move: Dictionary=db.move_of(mon.moves[index])
			var power:=float(move.get("power",0))
			if move.get("key","") in ["EXPLOSION","SELF_DESTRUCT","MISTY_EXPLOSION"]:continue
			var special: bool=move.get("category","")=="special"
			var atk:=float(mon.stats.get("spa" if special else "atk",1))
			var defense:=maxf(1,float(foe.stats.get("spd" if special else "def",1)))
			var effectiveness: float=ui.battle.effectiveness_on(move.type,foe)
			var score:=power*atk/defense*effectiveness*(1.5 if move.type in mon.types else 1.0)*minf(1.0,float(move.get("accuracy",100))/100.0)
			if move.get("key","") in ["SUCKER_PUNCH","FUTURE_SIGHT"]:score*=0.65
			score*=float(foe.max_hp)/maxi(1,int(foe.hp))
			if score>highest:highest=score;best=[index,lane]
	return best

func battle() -> void:
	var ui = game.active_battle
	var wild: bool = str(ui.trainer_name).is_empty()
	var enemy: Dictionary = ui.battle.cur_b()
	var owned: bool = game.save_data.dex.caught.any(func(n): return int(n) == int(enemy.species_id))
	var capture: bool = wild and mode == "collect" and not owned
	for frame in 3500:
		if game.active_battle != ui: break
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
			var weaken := soften_move(ui, enemy) if (capture or mode=="throw") and ball not in ["", "大师球"] else -1
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
				var paired: bool = ui.get_script().resource_path=="res://scenes/double_battle_ui.gd"
				if paired:
					var foe_lane: int = ui.battle.choose_lane("b",1 if turns%2==0 else 0)
					if foe_lane>=0: ui.target_buttons[foe_lane].pressed.emit()
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
				if world.map_data.get("region","") in ["kalos","alola"] or game.world.map_data.get("mechanisms",{}).has("hill") or str(ui.trainer_name) in ["花月","芙蓉","波妮","源治","米可利"]:
					var selected:=matchup_move(ui,paired)
					best=int(selected[0])
					if paired:ui.target_buttons[selected[1]].pressed.emit()
				ui.menu.get_node("fight").pressed.emit()
				if not paired and world.map_data.get("region","")=="kalos":
					var forms: Array=ui.battle.available_forms("a")
					var more=ui.move_menu.get_node_or_null("Special")
					if more!=null and not forms.is_empty():
						more.pressed.emit()
						var form_button=button(ui.get_node("SpecialPanel"),str(forms[0].label))
						if form_button:
							form_button.pressed.emit()
							print("MEGA INPUT ",ui.trainer_name," ",forms[0].key)
				if not paired and world.map_data.get("region","")=="alola" and ui._has_z_move():
					ui.move_menu.get_node("Special").pressed.emit()
					button(ui.get_node("SpecialPanel"),"Z 招式").pressed.emit()
					for candidate in ui.get_node("ZPanel").find_children("*","Button",true,false):
						if not candidate.disabled and str(candidate.text).contains(" → "):
							candidate.pressed.emit()
							z_inputs+=1
							break
					ui._process(5.0)
					continue
				var move_button: Button = ui.move_menu.get_node("Move%d"%best if best>=0 else "Struggle")
				move_button.pressed.emit()
		ui._process(5.0)
	if game.active_battle == ui:
		problem = "Battle did not finish: %s, state=%s, turn=%s" % [ui.trainer_name,ui.state,turns]
		return
	if not wild or mode=="wild-survey" or ui.battle.winner in ["caught","b"] or ui.battle.fishing_encounter:
		fights.append([str(ui.trainer_name),enemy.name,enemy.level,ui.battle.winner])
	await process_frame

func settle() -> void:
	for tick in 1200:
		if problem: return
		if is_instance_valid(game.active_battle):
			await battle()
		elif game.menu_layer.has_node("SafariEncounter"):
			var safari=game.menu_layer.get_node("SafariEncounter")
			if not safari.is_queued_for_deletion():safari.moves["ball" if mode=="collect" else "run"].pressed.emit()
			await process_frame
		elif game.menu_layer.get_child_count()>0 and game.menu_layer.get_child(-1).has_method("make_block"):
			var blender=game.menu_layer.get_child(-1)
			if not blender.is_queued_for_deletion():
				for frame in 1200:
					if blender.done:break
					blender._process(1.0/60.0)
					if absf(wrapf(blender.angle-PI/2,-PI,PI))<0.17:blender.action.pressed.emit()
				blender.action.pressed.emit()
			await process_frame
		elif not game._dialogs.is_empty():
			var dlg = game._dialogs.back()
			var line = dlg.lines[clampi(dlg.index - 1,0,dlg.lines.size()-1)] if not dlg.lines.is_empty() else ""
			if lines.is_empty() or lines.back() != line:
				lines.append(line)
			if dlg.is_waiting_answer(): dlg.btn_yes.pressed.emit()
			else: game._on_action()
		elif world.map_data.id in ["four_island_icefall_cave_b1f","sinnoh_snowpoint_city_gym"] and world.auto_step_dir()!=Vector2i.ZERO:
			world.tick_walk(1.0)
			game._process(1.0/60.0)
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
	return {"pos":current(),"elevation":world.last_elevation,"tower_mode":str(game._flags().get("fr_tower",{}).get("mode","")),"party":mons,"bag":items,"flags":game._flags().keys().filter(func(k): return game._flags()[k]),
		"z_inputs":z_inputs,"ice":{"k_ice_turn_pink":game._flags().get("k_ice_turn_pink",0),"k_ice_turn_blue":game._flags().get("k_ice_turn_blue",0),"k_ice_turn_green":game._flags().get("k_ice_turn_green",0),"k_ice_turn_yellow":game._flags().get("k_ice_turn_yellow",0)},
		"pl_obstacles":world.objects.filter(func(o):return o.get("kind","") in ["rock","cut","boulder"]).map(func(o):return [o.at,o.kind]) if world.map_data.has("platinum_native") else [],
		"pl_gym_state":game._flags().get("pl_gym_"+str(world.map_data.id),{}),"pl_gym_collision":world.emerald_collision if world.map_data.has("platinum_gym") else [],
		"gym_button":int(game._flags().get("h_wattson_switch",0)),"gym_local":world.hoenn_local,"badges":game.save_data.badges,"money":game.save_data.money,"dex":game.save_data.dex.caught,"defeated":game.save_data.get("defeated",{}),
		"actors":world.npcs.map(func(n):return [n.at,n.get("role",""),n.get("name",""),n.get("shop",false),n.get("legacy_at",n.at),n.get("story_map",world.map_data.id),n.get("heal",false),n.get("hgss_source",""),n.get("local_id",-1),n.get("source_script",""),n.get("kalos_trainer",n.get("unova_trainer",""))]),
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
		"start": game.ui_layer.get_node("StartKey").pressed.emit()
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
	var args := OS.get_cmdline_user_args()
	var region := ""
	var mode := "carried"
	var fresh := false
	for candidate in ["hoenn","johto","sinnoh","unova","kalos","alola"]:
		if "new-"+candidate in args or candidate+"-carried" in args or candidate+"-boxed" in args:
			region=candidate
			mode="boxed" if candidate+"-boxed" in args else "carried"
			fresh="new-"+candidate in args
			break
	if not region.is_empty():
		if fresh == is_instance_valid(game.title_screen.continue_button):
			push_error("Unexpected save slot for regional journey")
			quit(1)
			return
		var version := "y" if "y" in args else "x"
		if region=="alola":
			for key in ["sun","moon","ultra_sun","ultra_moon"]:
				if key in args:version=key
		if not await preload("regional_start.gd").enter(game,region,mode,version):
			quit(1)
			return
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
