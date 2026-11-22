extends "res://scenes/battle_ui.gd"

var companion := false
var orders := {}
var selection := 0
var target := 0
var boxes := {"a":[],"b":[]}
var sprites := {"a":[],"b":[]}
var target_buttons := []
var animations := {}

func _battle_engine(seed_value: int):
	return preload("res://core/double_battle.gd").new(seed_value)

func _build() -> void:
	super._build()
	boxes.a = [player_hp,_make_hpbox(Vector2.ZERO,battle.cur_a(),true)]
	boxes.b = [enemy_hp,_make_hpbox(Vector2.ZERO,battle.cur_b(),false)]
	sprites.a = [player_sprite,_make_sprite(battle.cur_a(),Vector2.ZERO,1.55,true)]
	sprites.b = [enemy_sprite,_make_sprite(battle.cur_b(),Vector2.ZERO,1.35)]
	for i in 2:
		boxes.b[i].position=Vector2(3,i*45+2)
		boxes.a[i].position=Vector2(310,132+i*45)
		boxes.a[i].scale=Vector2(0.81,0.81)
		boxes.b[i].scale=Vector2(0.8,0.8)
		var button := Button.new()
		button.add_theme_font_size_override("font_size",11)
		button.position=Vector2(164,5+i*44)
		button.size=Vector2(56,33)
		button.pressed.connect(_select_target.bind(i))
		target_buttons.append(button)
		add_child(button)
	_refresh_hp()

func _select_target(i: int) -> void:
	if state!="menu" or not battle.viable("b",i): return
	target=i
	battle.focus(selection,target)
	_refresh_targets()

func _refresh_targets() -> void:
	for i in 2:
		target_buttons[i].text = "目标 ✓" if i==target else "瞄准"
		target_buttons[i].disabled = not battle.viable("b",i)

func _open_commands(focus_key := "fight", prompt := "") -> void:
	if orders.is_empty():
		selection=battle.choose_lane("a",0)
	target=battle.choose_lane("b",maxi(0,target))
	if selection<0 or target<0:return
	battle.focus(selection,target)
	super._open_commands(focus_key,prompt)
	_refresh_targets()

func _on_move(i: int) -> void:
	if state=="menu": _select_action("move:%d"%i)

func _do_switch(i: int) -> void:
	if i in battle.lanes.a or player_team[i].get("trainer_group","first")=="second":
		_open_commands("switch","这位伙伴已在场上，或由大吾指挥。")
		return
	_select_action("switch:%d"%i)

func _select_action(choice: String) -> void:
	orders[selection]={"move":choice,"target":target}
	for i in 2:
		if orders.has(i) or not battle.viable("a",i): continue
		if companion and battle.groups.a[i]=="second": continue
		selection=i
		_open_commands()
		return
	_begin_resolve()
	pending.clear()
	_queue_turn(choice,"")
	msg.text=""
	wait=_dur(0.1)

func _queue_turn(player: String,_opponent: String) -> void:
	if not orders.has(selection): orders[selection]={"move":player,"target":target}
	line_offset=pending.size()
	if frontier_rules!=null and frontier_rules.kind=="palace":
		for lane in orders:
			if str(orders[lane].move).begins_with("move:"):
				battle.focus(lane,battle.choose_lane("b",int(orders[lane].target)))
				orders[lane].move=frontier_rules.choose(battle,"a",true)
	battle.round_actions(orders)
	pending.append_array(battle.log)
	battle.log.clear()
	orders.clear()
	if health_cues.has(pending.size()): pending.append("")

func _queue_health(line: int, side: String, slot: int, mon: Dictionary) -> void:
	if state!="resolve":return
	var lane: int = battle.lanes[side].find(slot)
	if lane<0:return
	var index := line_offset+line
	var samples: Array = health_cues.get_or_add(index,[])
	samples.append({"side":side,"lane":lane,"slot":slot,"mon":mon.duplicate()})

func _play_health(index: int) -> void:
	for sample in health_cues.get(index,[]):
		var box = boxes[sample.side][sample.lane]
		var before := int(box.get_meta("shown_hp",sample.mon.hp))
		var same := int(box.get_meta("slot",-1))==int(sample.slot)
		var key: String = "%s%d"%[sample.side,sample.lane]
		if animations.has(key): animations[key].kill()
		_update_hpbox(box,sample.mon)
		box.set_meta("slot",sample.slot)
		if same and before!=int(sample.mon.hp):
			var draw_hp := func(hp: float): _draw_hp(box,roundi(hp),int(sample.mon.max_hp))
			draw_hp.call(before)
			var tween := create_tween()
			tween.tween_method(draw_hp,float(before),float(sample.mon.hp),_dur(0.42))
			animations[key]=tween

func _refresh_hp() -> void:
	if boxes.a.size()!=2: return
	for side: String in ["a","b"]:
		var group: Array = battle.team_a if side=="a" else battle.team_b
		for i in 2:
			var idx: int=battle.lanes[side][i]
			var box: Control=boxes[side][i]
			var sprite: TextureRect=sprites[side][i]
			box.visible=idx>=0
			sprite.visible=idx>=0
			if idx<0:continue
			_update_hpbox(box,group[idx])
			box.set_meta("slot",idx)
			_apply_appearance(sprite,group[idx])
			var factor:=1.55 if side=="a" else 1.35
			var feet:=float(sprite.texture.get_meta("feet",56))
			sprite.scale=Vector2.ONE*factor
			var ground_y:=float((213-i*25) if side=="a" else (115+i*14))-feet*factor
			sprite.position=Vector2((34+i*94) if side=="a" else (248+i*90),ground_y)
			sprite.set_meta("ground_y",ground_y)
	_refresh_targets()
	_refresh_field_label()
