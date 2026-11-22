extends "res://scenes/battle_ui.gd"
## Poké Dude controls both parties. Every battle object and item is local to the TV.
const NARRATION := [
	["先观察谁先出手。小拉达使用必杀门牙，波波以起风还击。","双方依次行动。体力降到零时，胜方获得经验。"],
	["走路草会用毒粉。小拉达中毒时，回合结束还会受到伤害。","从背包使用解毒药。治疗占用这一回合，对手仍然可以行动。","状态恢复后，小拉达继续用必杀门牙。"],
	["蚊香蝌蚪的泡沫打在草属性身上威力很低。","换上巴大蝶。换人占用一回合，草招式对虫和飞行属性的效果很差。","巴大蝶用念力攻击走路草的毒属性。"],
	["先让巴大蝶使用念力，削弱胖丁的体力。","再用催眠粉。睡着的宝可梦更容易捕获。","从精灵球口袋投出精灵球。"],
]
const SEEDS := [11,1,1,1]
var footage: Dictionary
var lesson:=0
var turn_no:=0
var move_index:=0
var proceed:=Button.new()
var leave:=Button.new()
var completed_turns: Array=[]

func play_lesson(index: int,record: Dictionary) -> void:
	lesson=index
	footage=record
	var first: Array=[]
	var foe: Array=[]
	for entry in record.party:
		var member: Dictionary=Battle.make_combatant(int(entry[2]),int(entry[1]),entry[3])
		if entry[0]=="PLAYER":first.append(member)
		else:foe.append(member)
	setup(first,foe,SEEDS[lesson])
	proceed.text="演示下一步"
	proceed.pressed.connect(next_input)
	add_child(proceed)
	proceed.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	proceed.offset_left=-123;proceed.offset_top=-48;proceed.offset_bottom=-5;proceed.offset_right=-5
	proceed.hide()
	leave.text="退出教学"
	add_child(leave)
	leave.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	leave.offset_left=-85;leave.offset_bottom=34
	leave.pressed.connect(handle_back)
	set_meta("choice_back",handle_back)

func _open_commands(_focus_key: String="fight",_prompt: String="") -> void:
	menu.hide()
	move_menu.hide()
	msg.show()
	msg.size.x=315
	msg.text=NARRATION[lesson][mini(turn_no,NARRATION[lesson].size()-1)]
	proceed.show()
	proceed.grab_focus()
	bg.queue_redraw()

func next_input() -> void:
	if state!="menu":return
	proceed.hide()
	var action:int=footage.actions[mini(turn_no,footage.actions.size()-1)][0]
	var opponent:int=footage.moves[mini(turn_no,footage.moves.size()-1)][1]
	completed_turns.append(action)
	turn_no+=1
	if action==1 and lesson==3:
		_throw("精灵球")
		return
	_begin_resolve()
	pending.clear()
	var player:="move:%d"%int(footage.moves[mini(move_index,footage.moves.size()-1)][0])
	if action==0:move_index+=1
	elif action==2:player="switch:1"
	elif action==1:
		player="item"
		battle.cur_a().status=""
		battle.cur_a().status_turns=0
		pending.append("演示员使用了解毒药。小拉达身上的毒解除了！")
	_queue_turn(player,"move:%d"%opponent)
	msg.text=""
	wait=_dur(0.1)

func handle_back() -> void:
	if is_queued_for_deletion():return
	state="finished"
	finished.emit("closed")
	queue_free()
