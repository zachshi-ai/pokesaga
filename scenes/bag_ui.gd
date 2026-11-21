extends Control

const UI := preload("res://core/field_ui.gd")
const ATLAS := preload("res://assets/ui/field/bag_icons.png")
const CATEGORIES := [
	["ball","精灵球","精灵球"],["heal","回复药","伤药"],["key","重要道具","其他"],
	["battle","战斗","力量强化"],
	["berry","树果","橙橙果"],["held","携带物","携带"],["evo","进化道具","火之石"],
	["tera","太晶","太晶"],["tm","学习器","TM"],["other","其他","其他"]
]
signal closed

var on_use: Callable
var items: Array = []
var row_box: VBoxContainer
var scroller: ScrollContainer
var tab_buttons: Array = []
var cur_cat := "heal"
var names: Dictionary = {}
var hero_title: Label
var totals: Label
var empty_state: Label

func setup(p_items: Array) -> void:
	items = p_items
	names = Data.load_json("res://content/ui_item_icons.json")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UI.sheet(self)
	UI.header(p,"旅行背包","",handle_back)
	var sx := 117.0
	var cats := UI.scroll(p,Vector2(8,55),Vector2(103,size.y-63))
	var category_list := UI.list_box(cats,4)
	for group in CATEGORIES:
		var b := UI.button("     "+str(group[1]),_switch.bind(str(group[0])))
		b.custom_minimum_size.y = 37
		b.set_meta("cat",group[0])
		var ico := _icon(str(group[2]))
		UI.place(b,ico,3,5,28,27)
		category_list.add_child(b)
		tab_buttons.append(b)
	var banner := Panel.new()
	banner.add_theme_stylebox_override("panel",UI.box(UI.GREEN,UI.GREEN))
	UI.place(p,banner,sx,55,size.x-sx-8,60)
	var satchel := UI.art("res://assets/emerald/ui/bag.png")
	satchel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	UI.place(banner,satchel,banner.size.x-78,4,66,52)
	hero_title = UI.label("",19,UI.CARD)
	UI.place(banner,hero_title,12,4,170,29)
	totals = UI.label("",11,UI.SUN)
	UI.place(banner,totals,12,33,160,20)
	scroller = UI.scroll(p,Vector2(sx,122),Vector2(size.x-sx-8,size.y-130))
	row_box = UI.list_box(scroller,4)
	empty_state = UI.wrapped("",14,UI.MUTED)
	UI.place(p,empty_state,sx+12,135,size.x-sx-38,65)
	_switch(cur_cat)

func _icon(key: String) -> TextureRect:
	var v := UI.art("")
	var idx := int(names.get(key,-1))
	if idx>=0:
		var region := AtlasTexture.new()
		region.atlas = ATLAS
		region.region = Rect2((idx%16)*24,(idx/16)*24,24,24)
		v.texture = region
	return v

func _switch(cat: String) -> void:
	cur_cat = cat
	scroller.scroll_vertical = 0
	for btn in tab_buttons:
		UI.style_button(btn,btn.get_meta("cat")==cat)
	refresh()

func _category(obj: Dictionary) -> String:
	var name := str(obj.get("name",""))
	if name.contains("招式学习器") or name.contains("秘传学习器"):
		return "tm"
	var key := str(obj.get("category","other"))
	for group in CATEGORIES:
		if key == group[0]: return key
	return "other"

func refresh() -> void:
	UI.clear(row_box)
	var fallback := "其他"
	for group in CATEGORIES:
		if group[0]==cur_cat:
			hero_title.text = str(group[1])
			fallback = str(group[2])
	var count := 0
	for obj in items:
		if not obj is Dictionary or int(obj.get("count",0))<=0 or _category(obj)!=cur_cat: continue
		count += 1
		var nm := str(obj.get("name",""))
		var b := UI.button("",_use.bind(nm))
		b.custom_minimum_size.y = 47
		row_box.add_child(b)
		var key := nm if names.has(nm) else fallback
		if nm.contains("秘传学习器"): key = "HM"
		elif nm.contains("招式学习器"): key = "TM"
		UI.place(b,_icon(key),6,4,38,38)
		var name_label := UI.label(nm,15)
		name_label.clip_text = true
		var transfer := nm == Data.REGION_TRANSFER_ITEM
		UI.place(b,name_label,53,5,scroller.size.x-147,20 if transfer else 36)
		var qty := UI.label("×%d   ›" % int(obj.count),14,UI.GREEN)
		if transfer:
			UI.place(b,UI.label("前往各地区和异空间",11,UI.MUTED),53,25,scroller.size.x-147,17)
			qty.text = "选地区  ›"
			b.accessibility_name = nm + "，选择目的地"
		qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UI.place(b,qty,scroller.size.x-91,5,65,36)
	totals.text = "%d 种道具" % count
	empty_state.visible = count==0
	empty_state.text = "这个口袋还没有道具。"

func _use(nm: String) -> void:
	if on_use.is_valid():
		on_use.call(nm)

func handle_back() -> bool:
	closed.emit()
	queue_free()
	return true
