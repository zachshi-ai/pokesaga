extends Control

const UI := preload("res://core/field_ui.gd")
const Party := preload("res://core/party.gd")
const Growth := preload("res://core/growth.gd")

signal closed
signal reordered
signal evolve_with(slot: int, item_name: String)
signal tera_change(slot: int, tera_type: String)
signal held_change(slot: int, held_key: String, item_name: String)

var party: Array = []
var bag: Array = []
var region: String = ""
var detail: Control
var list: Control
var chooser: Control
var selected := -1
var page_scroll := 0
var scroll_list: ScrollContainer

func setup(p_party: Array, p_bag: Array = [], p_region: String = "") -> void:
	party = p_party
	bag = p_bag
	region = p_region
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

func _build() -> void:
	UI.clear(self)
	detail = null
	chooser = null
	var base := UI.sheet(self)
	UI.header(base,"同行队伍","%d / %d 只" % [Party.occupied(party), Party.MAX_SIZE],handle_back)
	var left := 145.0
	var side := Panel.new()
	side.add_theme_stylebox_override("panel",UI.box(UI.GREEN,UI.GREEN,7))
	UI.place(base,side,8,54,left,base.size.y-62)
	UI.party_panel(side,1,1,left-2,86)
	var lead: Dictionary = {}
	for entry in party:
		if entry is Dictionary and not entry.is_empty():
			lead = entry
			break
	if not lead.is_empty():
		var id := int(lead.get("species_id",0))
		var mon := UI.member_portrait(lead)
		UI.place(side,mon,13,30,left-26,119)
		UI.place(side,UI.label("首发   No.%03d"%id,12,UI.SUN),12,148,left-18,22)
		UI.place(side,UI.label(str(lead.get("name","")),20,UI.CARD),12,170,left-15,31)
		var types: PackedStringArray = []
		for t in lead.get("types", []):
			types.append(Data.type_name(str(t)))
		UI.place(side,UI.label("Lv.%d   %s" % [int(lead.get("level",1))," / ".join(types)],12,UI.CARD),12,203,left-15,22)
	else:
		UI.place(side,UI.wrapped("在真新镇研究所领取第一只宝可梦。",14,UI.CARD),12,105,left-24,80)
	var sx := left+17
	scroll_list = UI.scroll(base,Vector2(sx,54),Vector2(base.size.x-sx-7,base.size.y-61))
	var slots := GridContainer.new()
	slots.columns = 2
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots.add_theme_constant_override("h_separation",5)
	slots.add_theme_constant_override("v_separation",5)
	scroll_list.add_child(slots)
	list = slots
	for i in Party.MAX_SIZE:
		var m: Dictionary = party[i] if i<party.size() and party[i] is Dictionary else {}
		var b := UI.button("",_open_detail.bind(i))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0,65 if not m.is_empty() else 42)
		list.add_child(b)
		b.disabled = m.is_empty()
		if m.is_empty():
			b.text = "%02d  ·  空位" % (i+1)
			continue
		var thumb := UI.member_portrait(m)
		UI.place(b,thumb,3,13,41,42)
		UI.place(b,UI.label("%02d  /  Lv.%d" % [i+1,int(m.get("level",1))],10,UI.MUTED),48,4,98,17)
		var name_label := UI.label(str({"star":"★","square":"◇"}.get(Party.shiny_kind(m),""))+str(m.get("name","")),14)
		name_label.clip_text = true
		UI.place(b,name_label,47,21,94,22)
		var hp := int(m.get("hp",0))
		var mx := maxi(1,int(m.get("max_hp",1)))
		UI.meter(b,48,45,72,float(hp)/mx)
		UI.place(b,UI.label("%d / %d" % [hp,mx],10,UI.MUTED),48,49,92,13)
	scroll_list.set_deferred("scroll_vertical",page_scroll)

func _open_detail(i: int) -> void:
	if i<0 or i>=party.size() or not party[i] is Dictionary or party[i].is_empty():
		return
	if is_instance_valid(detail):
		remove_child(detail)
		detail.queue_free()
	page_scroll = scroll_list.scroll_vertical
	selected = i
	var m: Dictionary = party[i]
	detail = UI.sheet(self)
	var sex := Growth.evolution_sex(m)
	var symbol := " ♀" if sex == "female" else (" ♂" if sex == "male" else "")
	UI.header(detail,str(m.get("name","")) + symbol,"队员 %02d / 12"%[i+1],handle_back)
	var side := Panel.new()
	side.add_theme_stylebox_override("panel",UI.box(UI.PALE))
	UI.place(detail,side,8,54,142,detail.size.y-62)
	var id := int(m.get("species_id",0))
	UI.place(side,UI.member_portrait(m),8,7,126,126)
	UI.place(side,UI.label("No.%03d   Lv.%d" % [id,int(m.get("level",1))],14),10,137,125,24)
	UI.place(side,UI.label("HP  "+str(m.get("hp_text","")),13),10,165,125,20)
	UI.meter(side,10,190,120,float(m.get("hp",0))/maxi(1,int(m.get("max_hp",1))))
	var first := UI.button("首发队员" if i==0 else "设为首发",_set_lead.bind(i),true)
	first.disabled = i==0
	UI.place(side,first,8,side.size.y-44,126,36)
	var sc := UI.scroll(detail,Vector2(159,55),detail.size-Vector2(166,63))
	var rows := UI.list_box(sc,6)
	var types: PackedStringArray = []
	for key in m.get("types",[]): types.append(Data.type_name(str(key)))
	rows.add_child(UI.wrapped(" / ".join(types)+"    "+str(m.get("nature",""))+"    "+str(m.get("ability_name","")),14))
	var stats: Dictionary = m.get("stats",{})
	rows.add_child(UI.wrapped("攻击 %d  防御 %d  特攻 %d\n特防 %d  速度 %d  经验 %d" % [int(stats.get("atk",0)),int(stats.get("def",0)),int(stats.get("spa",0)),int(stats.get("spd",0)),int(stats.get("spe",0)),int(m.get("exp",0))],13,UI.MUTED))
	var move_names: PackedStringArray = []
	var pp: Array = m.get("pp",[])
	for k in (m.get("moves",[]) as Array).size():
		var move := Data.move_of(int(m.moves[k]))
		move_names.append("%s  %d/%d" % [str(move.get("name","")),int(pp[k]) if k<pp.size() else 0,int(move.get("pp",0))])
	rows.add_child(UI.wrapped("招式\n"+"    ".join(move_names)))
	var awards: Array=[]
	if m.get("effort_ribbon",false):awards.append("努力奖章")
	if m.get("artist_ribbon",false):awards.append("美术奖章")
	var contest=preload("res://core/emerald_contest.gd")
	for category in m.get("contest_ribbons",{}):
		var rank:=int(m.contest_ribbons[category])
		if rank>0 and int(category)>=0 and int(category)<contest.CATEGORIES.size():
			awards.append(str(contest.CATEGORIES[int(category)])+"·"+str(contest.RANKS[mini(rank-1,contest.RANKS.size()-1)])+"奖章")
	if not awards.is_empty():rows.add_child(UI.wrapped("奖章　"+"　".join(awards)))
	var held := Data.item_name(str(m.held)) if not str(m.get("held","")).is_empty() else Data.berry_name(str(m.get("berry","")))
	rows.add_child(UI.button("携带物品 · "+(held if not held.is_empty() else "无"),_choose.bind("held")))
	rows.add_child(UI.button("太晶属性 · "+Data.type_name(str(m.get("tera_type","normal"))),_choose.bind("tera")))
	if not Growth.item_evolutions(m, region).is_empty():
		rows.add_child(UI.button("道具进化",_choose.bind("evo")))

func _set_lead(i: int) -> void:
	var old = party[0]
	party[0] = party[i]
	party[i] = old
	selected = -1
	_build()
	reordered.emit()

func _choose(kind: String) -> void:
	chooser = UI.sheet(self)
	var headings := {"held":"选择携带物品","tera":"使用太晶碎块","evo":"选择进化道具"}
	UI.header(chooser,headings[kind],str(party[selected].name),handle_back)
	var sc := UI.scroll(chooser,Vector2(12,55),chooser.size-Vector2(24,62))
	var rows := UI.list_box(sc)
	if kind=="held" and (str(party[selected].get("held",""))!="" or str(party[selected].get("berry",""))!=""):
		rows.add_child(UI.button("取下当前携带物品",_apply.bind("held","","")))
	for obj in bag:
		if not obj is Dictionary or int(obj.get("count",0))<1: continue
		var cat := str(obj.get("category",""))
		var item_name := str(obj.get("name",""))
		var key := ""
		if kind=="held" and cat in ["held","berry"]:
			key = "berry:"+str(obj.get("berry","")) if cat=="berry" else str(obj.get("held",""))
		elif kind=="tera" and cat=="tera":
			key = str(obj.get("tera",""))
		elif kind=="evo":
			var evo := Growth.evolution_for_item(party[selected], Data.bag_evo_key(obj), region)
			if not evo.is_empty():
				key = str(evo.to)
		if key.is_empty(): continue
		var title := "%s    ×%d" % [item_name,int(obj.count)]
		rows.add_child(UI.button(title,_confirm.bind(kind,key,item_name) if kind in ["evo","tera"] else _apply.bind(kind,key,item_name)))
	if rows.get_child_count()==0:
		rows.add_child(UI.wrapped("背包里没有可用于这只宝可梦的道具。"))

func _confirm(kind: String, key: String, title: String) -> void:
	UI.clear(chooser)
	UI.header(chooser,"确认使用",str(party[selected].name),handle_back)
	var desc := "改为%s属性" % Data.type_name(key) if kind=="tera" else "进化为%s" % str(Data.species_of(int(key)).get("name",""))
	UI.place(chooser,UI.wrapped("消耗 1 个%s，让%s%s。" % [title,party[selected].name,desc],16),24,73,chooser.size.x-48,68)
	UI.place(chooser,UI.button("确认使用",_apply.bind(kind,key,title),true),24,154,134,42)
	UI.place(chooser,UI.button("取消",handle_back),167,154,90,42)

func _apply(kind: String, key: String, title: String) -> void:
	var i := selected
	handle_back()
	if kind=="held": held_change.emit(i,key,title)
	elif kind=="tera": tera_change.emit(i,key)
	else: evolve_with.emit(i,title)
	call_deferred("refresh")

func refresh() -> void:
	if is_queued_for_deletion(): return
	var i := selected
	_build()
	if i>=0: _open_detail(i)

func handle_back() -> bool:
	if is_instance_valid(chooser):
		remove_child(chooser)
		chooser.queue_free()
		chooser = null
	elif is_instance_valid(detail):
		selected = -1
		_build()
	else:
		closed.emit()
		queue_free()
	return true
