extends SceneTree
## Exercise the visible command windows as they change with the active battler.
var combat
var view
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("BATTLE COMMANDS: " + message)

func begin(team: Array, bag := [], trainer := "") -> void:
	if is_instance_valid(view):
		root.remove_child(view)
		view.queue_free()
	view = load("res://scenes/battle_ui.gd").new()
	root.add_child(view)
	view.setup(team,[combat.make_combatant(3,28,[33])],7,bag,trainer)
	view._process(2.0)

func settle() -> void:
	for n in 40:
		if view.state == "menu": break
		view._process(2.0)
	expect(view.state == "menu","next command turn")

func pick(prefix: String) -> bool:
	for b in view.find_children("*","Button",true,false):
		if b.is_visible_in_tree() and not b.disabled and (b.text.begins_with(prefix) or b.accessibility_name.begins_with(prefix)):
			b.pressed.emit()
			return true
	expect(false,"missing action " + prefix)
	return false

func check_struggle(moves: Array, asleep := false) -> void:
	var mon: Dictionary = combat.make_combatant(25,35,moves)
	mon.pp.fill(0)
	begin([mon])
	mon.stats.spe = 1
	if asleep:
		mon.status = "slp"
		mon.status_turns = 3
	view.battle.field.terrain = "psychic"
	view.battle.field.terrain_turns = 3
	pick("战斗")
	if pick("挣扎"):
		expect(view.state == "resolve" and str(view.pending).contains("挣扎") != asleep,"Struggle respects terrain and sleep")
		expect(not mon.moved_first,"Struggle does not inherit a depleted move's priority")
		expect(mon.moves == moves,"Struggle changed the saved moves")

func run() -> void:
	root.get_node("Data").load_core_tables()
	combat = load("res://core/battle.gd")
	var starter: Dictionary = combat.make_combatant(6,50,[53,19,337,163])
	starter.tera_type = "fire"
	var team := [starter]
	for sid in [25,39,555,650,100,282,478,215,312,1000,894]:
		team.append(combat.make_combatant(sid,35,[33,84]))
	begin(team)
	expect(view.menu.find_children("*","Button",true,false).size()==4,"main command count")
	var bounds: Rect2 = view.menu.get_global_rect()
	for a in view.menu.find_children("*","Button",true,false):
		expect(bounds.encloses(a.get_global_rect()),"command escaped frame")
		expect(a.size.y >= 40,"main touch height")
	pick("战斗")
	expect(view.move_menu.visible and not view.menu.visible,"moves cover commands")
	expect(view.move_menu.get_node("Move0").accessibility_name=="喷射火焰","initial moves")
	pick("特殊行动")
	var sheet: Control = view.get_node("SpecialPanel")
	expect(view.menu.get_node("fight").get_focus_mode_with_override()==Control.FOCUS_NONE,"underlying command focus")
	expect(view.move_menu.get_node("Move0").get_focus_mode_with_override()==Control.FOCUS_NONE,"underlying move focus")
	var focused := root.gui_get_focus_owner()
	for step in 12:
		expect(focused!=null and sheet.is_ancestor_of(focused),"modal focus escaped")
		if not focused: break
		focused = focused.find_next_valid_focus()
	pick("Z 招式")
	expect(view.has_node("ZPanel"),"Z moves")
	view.handle_back()
	expect(view.has_node("SpecialPanel"),"back from Z moves")
	view.handle_back()
	expect(view.move_menu.visible and view.sheet==null,"back to moves")
	view.handle_back()
	pick("宝可梦")
	await process_frame
	var scroll: ScrollContainer = view.sheet.find_children("*","ScrollContainer",true,false)[0]
	var choices := scroll.find_children("*","Button",true,false)
	expect(choices.size()==12 and choices[0].disabled,"12 teammates")
	var last: Button = choices.back()
	last.grab_focus()
	await process_frame
	expect(scroll.scroll_vertical>0 and scroll.get_global_rect().has_point(last.get_global_rect().get_center()),"twelfth teammate reachable")
	last.pressed.emit()
	settle()
	expect(view.battle.active_a==11,"switched to twelfth teammate")
	pick("战斗")
	expect(view.move_menu.get_node("Move0").accessibility_name=="撞击" and not view.move_menu.has_node("Move2"),"moves refreshed on switch")
	view.handle_back()
	pick("背包")
	expect(root.gui_get_focus_owner().name=="Return","empty bag focus")
	view.handle_back()
	begin([starter],[],"小茂")
	pick("宝可梦")
	expect(root.gui_get_focus_owner().name=="Return","no available teammate focus")
	view.handle_back()
	pick("背包")
	expect(view.menu.visible and view.sheet==null and view.msg.text.contains("不能投球"),"trainer bag")
	pick("战斗")
	pick("特殊行动")
	pick("Mega")
	settle()
	pick("战斗")
	expect(not view.move_menu.has_node("Special"),"spent actions gone")
	# A trainer's pivot move must keep the fight active with or without a reserve.
	for has_reserve in [false,true]:
		var pivot: Dictionary = combat.make_combatant(398,30,[369])
		var friends: Array=[pivot]
		if has_reserve: friends.append(combat.make_combatant(25,30,[84]))
		var match_engine=combat.new(41)
		match_engine.start([combat.make_combatant(9,60,[150])],friends)
		match_engine.run_turn("move:0","move:0")
		expect(not match_engine.over and match_engine.active_b==int(has_reserve),"trainer U-turn continues battle")
	check_struggle([98,84])
	check_struggle([98],true)
	check_struggle([])
	print("BATTLE COMMANDS ","PASS" if failures==0 else "FAIL")
	quit(1 if failures else 0)
