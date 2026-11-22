extends "res://scenes/battle_ui.gd"

var rotate_buttons: Array[Button] = []

func _battle_engine(seed_value: int):
	return preload("res://core/rotation_battle.gd").new(seed_value)

func _build() -> void:
	super._build()
	for i in 3:
		var button:=_choice("",_rotate.bind(i),13)
		UI.place(self,button,8+i*85,168,82,35)
		button.hide()
		rotate_buttons.append(button)

func _rotate(seat: int) -> void:
	if state!="menu" or seat>=battle.platform.a.size():return
	if battle.rotate("a",battle.platform.a[seat]):
		_refresh_hp()
		_open_commands()

func _open_commands(focus_key: String="fight",prompt: String="") -> void:
	super._open_commands(focus_key,prompt)
	for i in rotate_buttons.size():
		var button:=rotate_buttons[i]
		button.visible=i<battle.platform.a.size()
		if button.visible:
			var slot: int=battle.platform.a[i]
			button.disabled=slot==battle.active_a
			button.text=("▶ " if button.disabled else "")+str(player_team[slot].name)
			button.accessibility_name="轮转至"+str(player_team[slot].name)

func _on_command_kind(kind: String) -> void:
	for button in rotate_buttons:button.hide()
	super._on_command_kind(kind)

func _do_switch(index: int) -> void:
	if index in battle.platform.a:
		_rotate(battle.platform.a.find(index))
	else:super._do_switch(index)
