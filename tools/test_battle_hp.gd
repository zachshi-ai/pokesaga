extends SceneTree
## Sample actual presentation frames of both attacks in one deterministic turn.


var failed := false

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, why: String) -> void:
	if not ok:
		failed = true
		push_error(why)

func run() -> void:
	var View = load("res://scenes/battle_ui.gd")
	var Combat = load("res://core/battle.gd")
	root.get_node("Data").load_core_tables()
	var me: Dictionary = Combat.make_combatant(25,28,[84])
	var foe: Dictionary = Combat.make_combatant(133,28,[33])
	me.stats.spe = 200
	var v = View.new()
	root.add_child(v)
	v.setup([me],[foe],9)
	v._process(2.0)
	var initial := int(foe.hp)
	var mine := int(me.hp)
	v._on_command_kind("fight")
	v._on_move(0)
	expect(initial > int(foe.hp) and mine > int(me.hp),"fixture must damage both battlers")
	expect(v.enemy_hp.get_meta("shown_hp")==initial and v.player_hp.get_meta("shown_hp")==mine,"bars jumped immediately to the turn result")
	var enemy_mid := false
	var player_mid := false
	for i in 1200:
		v._process(1.0/60)
		var now := int(v.enemy_hp.get_meta("shown_hp"))
		var player := int(v.player_hp.get_meta("shown_hp"))
		if int(foe.hp)<now and now<initial:
			enemy_mid = true
			expect(v.msg.text.contains("使用了"), "damage must begin during the move announcement")
			expect(player==mine, "counterattack displayed before first damage")
			expect(v.enemy_hp.get_node("HP").text.begins_with(str(now)+"/"),"digits disagree with bar")
		if int(me.hp)<player and player<mine:
			player_mid = true
			expect(now==int(foe.hp),"second attack started before first finished")
		if v.state=="menu": break
	expect(enemy_mid and player_mid and v.enemy_hp.get_meta("shown_hp")==int(foe.hp) and v.player_hp.get_meta("shown_hp")==int(me.hp), "both HP bars must pass through intermediate frames and land exactly")
	print("BATTLE HP ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
