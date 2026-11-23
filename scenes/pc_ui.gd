extends Control
## Shared 12-member party and 200-box storage. Select the specific member to deposit.
const Party := preload("res://core/party.gd")
const UI := preload("res://core/field_ui.gd")
const BOXES := Party.BOX_COUNT
const PER_BOX := Party.BOX_SIZE
signal closed

var boxes: Array = []
var party: Array = []
var box_index := 0
var on_change := Callable()
var showing_party := false
var notice := ""
var contents: Control

func setup(p_boxes: Array, p_party: Array) -> void:
	boxes=p_boxes
	party=p_party
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refresh()

func _current() -> Dictionary:
	while boxes.size()<=box_index:
		boxes.append({"name":"箱子 %d"%[boxes.size()+1],"mons":[]})
	if not boxes[box_index] is Dictionary:
		boxes[box_index]={"name":"箱子 %d"%[box_index+1],"mons":[]}
	if not boxes[box_index].get("mons") is Array: boxes[box_index].mons=[]
	return boxes[box_index]

func _refresh() -> void:
	UI.clear(self)
	var p:=UI.sheet(self)
	UI.header(p,"宝可梦电脑","队伍 %d / %d" % [Party.occupied(party),Party.MAX_SIZE],handle_back)
	UI.place(p,UI.button("从队伍存入",_mode.bind(true),showing_party),8,54,105,36)
	UI.place(p,UI.button("从箱子取出",_mode.bind(false),not showing_party),118,54,105,36)
	UI.place(p,UI.button("‹",_turn.bind(-1)),size.x-162,54,39,36)
	var tag:=UI.label("%d/%d"%[box_index+1,BOXES],13)
	tag.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	UI.place(p,tag,size.x-120,54,66,36)
	UI.place(p,UI.button("›",_turn.bind(1)),size.x-47,54,39,36)
	var box:=_current()
	var values:Array=party if showing_party else box.mons
	var sc:=UI.scroll(p,Vector2(9,98),size-Vector2(18,134))
	var grid:=GridContainer.new()
	grid.columns=3
	grid.add_theme_constant_override("h_separation",5)
	grid.add_theme_constant_override("v_separation",5)
	sc.add_child(grid)
	contents=grid
	for i in values.size():
		if not values[i] is Dictionary or values[i].is_empty(): continue
		var mon:Dictionary=values[i]
		var b:=UI.button("",_select.bind(i))
		b.custom_minimum_size=Vector2((size.x-40)/3,54)
		grid.add_child(b)
		UI.place(b,UI.member_portrait(mon),2,3,46,46)
		UI.place(b,UI.label(str(mon.get("name","")),13),51,5,b.custom_minimum_size.x-54,23)
		UI.place(b,UI.label("Lv.%d"%int(mon.get("level",1)),11,UI.MUTED),51,28,82,19)
	var tip:="点选队员存入%s" % box.name if showing_party else "点选宝可梦取回队伍"
	if grid.get_child_count()==0:
		grid.add_child(UI.label("队伍为空" if showing_party else "这个箱子是空的。",14,UI.MUTED))
	UI.place(p,UI.label(notice if notice!="" else tip,13),11,size.y-32,size.x-24,28)

func _mode(value:bool) -> void:
	showing_party=value
	notice=""
	_refresh()

func _turn(dir:int) -> void:
	box_index=posmod(box_index+dir,BOXES)
	notice=""
	_refresh()

func _select(i:int) -> void:
	var box:=_current()
	var src:Array=party if showing_party else box.mons
	if i<0 or i>=src.size() or not src[i] is Dictionary or src[i].is_empty(): return
	var dst:Array=box.mons if showing_party else party
	var m:Dictionary=src[i]
	var cap:=PER_BOX if showing_party else Party.MAX_SIZE
	if not Party.insert_into(dst,m,cap):
		notice="这个箱子已满。" if showing_party else "队伍已满 12 只。先选一只存入。"
	else:
		src[i]={}
		if showing_party:
			Party.restore_trim(m,true)
			party.assign(Party.compact(party))
		notice="%s已%s" % [str(m.get("name","")),("存入"+str(box.name)) if showing_party else "回到队伍"]
		if on_change.is_valid(): on_change.call(boxes,party)
	_refresh()

func _click_box(i:int) -> void:
	_mode(false)
	_select(i)

func handle_back() -> bool:
	closed.emit()
	queue_free()
	return true
