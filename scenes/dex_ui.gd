extends Control

const UI := preload("res://core/field_ui.gd")
const Catalog := preload("res://core/dex_catalog.gd")
const Art := preload("res://core/dex_art.gd")
const Effects := preload("res://core/dex_effect.gd")
const Records := preload("res://core/dex_variants.gd")
const SHINE_LABEL := {"none":"普通","star":"★ 星星闪","square":"◇ 方块闪"}
const REGIONS := ["全国","关都","城都","丰缘","神奥","合众","卡洛斯","阿罗拉","伽勒尔","帕底亚"]
const GEN_RANGE := [[1,151],[152,251],[252,386],[387,493],[494,649],[650,721],[722,809],[810,905],[906,1025]]
const PER_PAGE := 6
signal closed

var seen: Array = []
var caught: Array = []
var ids: Array = []
var page := 0
var gen := 1
var status := 0
var query := ""
var grid: GridContainer
var region_button: Button
var filter_button: Button
var prev_btn: Button
var next_btn: Button
var page_text: Label
var empty_label: Label
var detail: Control
var chooser: Control

var records: Dictionary = {}
var seen_species: Array = []
var entry := 0
var options: Array = []
var current: Dictionary = {}
var shiny_kind := "none"
var tera := ""
var giant := false
var form_subcategory := ""

func setup(p_seen: Array, p_caught: Array, p_records: Dictionary={}) -> void:
	UI.clear(self)
	records = p_records
	seen_species.clear()
	for id in p_seen+p_caught:
		if not seen_species.has(int(id)): seen_species.append(int(id))
	caught = Catalog.aggregate(p_caught)
	seen = Catalog.aggregate(seen_species)
	ids = Catalog.entry_ids()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UI.sheet(self)
	UI.header(p,"精灵图鉴","见过 %d  ·  已捕获 %d"%[seen.size(),caught.size()],handle_back)
	region_button = UI.button("",_choose_region)
	UI.place(p,region_button,8,53,89,36)
	filter_button = UI.button("",_cycle_status)
	UI.place(p,filter_button,102,53,93,36)
	var search := LineEdit.new()
	search.placeholder_text = "按名称或编号搜索全国"
	search.clear_button_enabled = true
	search.add_theme_font_size_override("font_size",13)
	search.add_theme_color_override("font_color",UI.INK)
	search.add_theme_color_override("font_placeholder_color",UI.MUTED)
	search.add_theme_stylebox_override("normal",UI.box(UI.CARD))
	search.text_changed.connect(func(value: String) -> void:
		query=value.strip_edges()
		page=0
		_refresh())
	search.text_submitted.connect(func(_v: String) -> void: search.release_focus())
	UI.place(p,search,200,53,size.x-208,36)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",5)
	grid.add_theme_constant_override("v_separation",5)
	UI.place(p,grid,8,95,size.x-16,size.y-144)
	empty_label = UI.label("没有符合条件的记录",15,UI.MUTED)
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(p,empty_label,8,105,size.x-16,100)
	prev_btn = UI.button("‹  上一页",_turn.bind(-1))
	next_btn = UI.button("下一页  ›",_turn.bind(1))
	UI.place(p,prev_btn,8,size.y-42,94,36)
	UI.place(p,next_btn,size.x-102,size.y-42,94,36)
	page_text = UI.label("",13,UI.MUTED)
	page_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(p,page_text,103,size.y-42,size.x-206,36)
	_refresh()

func _choose_region() -> void:
	chooser=UI.sheet(self)
	UI.header(chooser,"选择地区","",handle_back)
	var g := GridContainer.new()
	g.columns=3
	g.add_theme_constant_override("h_separation",6)
	g.add_theme_constant_override("v_separation",6)
	UI.place(chooser,g,10,57,size.x-20,size.y-67)
	for i in REGIONS.size():
		var b:=UI.button(REGIONS[i],_region.bind(i),i==gen)
		b.custom_minimum_size=Vector2((size.x-32)/3,48)
		g.add_child(b)

func _region(i:int) -> void:
	gen=i
	page=0
	handle_back()
	_refresh()

func _cycle_status() -> void:
	status=(status+1)%3
	page=0
	_refresh()

func _turn(d:int) -> void:
	page+=d
	_refresh()

func _refresh() -> void:
	UI.clear(grid)
	region_button.text = str(REGIONS[gen])+"  ▾"
	filter_button.text = str(["全部","已见","已捕获"][status])+"  ↻"
	var pool: Array = []
	for raw in ids:
		var id:=int(raw)
		if gen>0 and query.is_empty() and not _in_region(id): continue
		if (status==1 and not seen.has(id)) or (status==2 and not caught.has(id)): continue
		if not query.is_empty() and not Catalog.matches(id,query):
			continue
		pool.append(id)
	var pages := maxi(1,ceili(float(pool.size())/PER_PAGE))
	page=clampi(page,0,pages-1)
	empty_label.visible=pool.is_empty()
	prev_btn.disabled=page==0
	next_btn.disabled=page+1>=pages
	page_text.text="%d / %d   ·   %d 条记录" % [page+1,pages,pool.size()]
	var cw:float=(size.x-26)/3
	var ch:float=(size.y-148)/2
	for k in range(page*PER_PAGE,mini((page+1)*PER_PAGE,pool.size())):
		var id:int=pool[k]
		var met:=seen.has(id)
		var captured:=caught.has(id)
		var b:=UI.button("",_open_result.bind(id))
		b.custom_minimum_size=Vector2(cw,ch)
		grid.add_child(b)
		if met:
			UI.place(b,UI.portrait(id),2,4,61,ch-7)
		else:
			var hidden:=UI.label("?",27,UI.MUTED)
			hidden.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			UI.place(b,hidden,2,6,56,ch-12)
		UI.place(b,UI.label("No.%03d"%id,10,UI.MUTED),61,6,cw-64,17)
		var nm:=UI.label(Catalog.entry_name(id) if met else "未发现",14,UI.INK if met else UI.MUTED)
		nm.clip_text=true
		UI.place(b,nm,60,25,cw-63,23)
		UI.place(b,UI.label("● 已捕获" if captured else ("已见" if met else "—"),10,UI.GREEN),61,ch-25,cw-63,18)

func _in_region(id: int) -> bool:
	var limits: Array = GEN_RANGE[gen-1]
	if id>=int(limits[0]) and id<=int(limits[1]): return true
	for v in Catalog.variants(id):
		if int(v.species_id)>=int(limits[0]) and int(v.species_id)<=int(limits[1]): return true
	return false

func _open_result(id: int) -> void:
	_show_detail(id)
	if query.is_empty() or not seen.has(id): return
	current = Catalog.preferred_variant(id,query)
	_draw_detail()

func _show_detail(id: int) -> void:
	entry = Catalog.entry_id(id)
	options = Catalog.variants(entry)
	if options.is_empty():
		return
	current = options[0]
	var wanted := id
	if not seen_species.has(id):
		for option in options:
			if seen_species.has(int(option.species_id)):
				wanted = int(option.species_id)
				break
	for option in options:
		if int(option.species_id)==wanted:
			current = option
			break
	shiny_kind = "none"
	tera = ""
	giant = false
	_draw_detail()

func _draw_detail() -> void:
	if is_instance_valid(detail):
		remove_child(detail)
		detail.queue_free()
	detail = UI.sheet(self)
	var known := seen.has(entry)
	UI.header(detail,Catalog.entry_name(entry) if known else "未发现","图鉴 No.%04d"%entry,handle_back)
	if not known:
		UI.place(detail,UI.label("?",48,UI.MUTED),48,90,90,95)
		UI.place(detail,UI.wrapped("在野外遇见或捕获后，可以在这里查看形态。",16),158,85,290,96)
		return
	var side := Panel.new()
	side.add_theme_stylebox_override("panel",UI.box(UI.PALE))
	UI.place(detail,side,8,55,175,detail.size.y-63)
	var pic := UI.art("")
	pic.texture = Art.texture(int(current.species_id),str(current.art_key),shiny_kind!="none")
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var extent := 154 if giant or current.kind=="gmax" else 136
	UI.place(side,pic,(175-extent)/2.0,26,extent,extent)
	var effect := Effects.new()
	effect.shine = shiny_kind
	effect.tera = tera
	effect.giant = giant or current.kind=="gmax"
	UI.place(side,effect,4,3,167,177)
	var scope := UI.label(str(current.label),15)
	scope.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scope.clip_text = true
	UI.place(side,scope,4,181,167,25)
	var state := 0
	if not giant:
		for alias in Catalog.record_forms(current):
			state = maxi(state,Records.status(records,int(current.species_id),str(alias),shiny_kind,tera))
	var observed := UI.label(["外观预览","已见过此外观","已拥有此外观"][state],12,UI.GREEN)
	observed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(side,observed,4,209,167,26)
	var x := 191.0
	var w := detail.size.x-x-8
	var info := Catalog.stats(current)
	var types: PackedStringArray = []
	for key in info.get("types",[]): types.append(Data.type_name(str(key)))
	var info_line := " / ".join(types)
	if not tera.is_empty():
		info_line += "    →    太晶 · "+_type_name(tera)
	UI.place(detail,UI.label(info_line,14,UI.GREEN),x+3,55,w-6,26)
	UI.place(detail,UI.button("形态    "+str(current.label)+"   ▾",_pick_forms),x,85,w,40)
	UI.place(detail,UI.button("闪光    "+SHINE_LABEL[shiny_kind]+"   ▾",_pick_shine),x,131,w,40)
	var battle_label := "常态"
	if giant: battle_label = "极巨化"
	elif not tera.is_empty(): battle_label = "太晶 · "+_type_name(tera)
	elif current.kind in ["mega","gmax"]: battle_label = Catalog.category(current)
	UI.place(detail,UI.button("战斗状态    "+battle_label+"   ▾",_pick_battle),x,177,w,40)
	UI.place(detail,UI.button("查看种族值与特性   ›",_pick_stats),x,223,w,40)
	var hint := UI.label("%d 种形态   ·   %s" % [options.size(), "该编号已捕获" if caught.has(entry) else "该编号已见"],11,UI.MUTED)
	UI.place(detail,hint,x+4,270,w-8,28)

func _type_name(value: String) -> String:
	return "星晶" if value=="stellar" else Data.type_name(value)

func _modal(title: String) -> void:
	if is_instance_valid(chooser):
		remove_child(chooser)
		chooser.queue_free()
	chooser = UI.sheet(self)
	UI.header(chooser,title,"No.%04d  %s"%[entry,Catalog.entry_name(entry)],handle_back)

func _choices(top := 55.0) -> GridContainer:
	var sc := UI.scroll(chooser,Vector2(10,top),Vector2(size.x-20,size.y-top-8))
	var g := GridContainer.new()
	g.columns = 2
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation",6)
	g.add_theme_constant_override("v_separation",6)
	sc.add_child(g)
	return g

func _choice(parent: Control, value: String, callback: Callable, active := false) -> void:
	var b := UI.button(value, callback, active)
	b.custom_minimum_size = Vector2((size.x-40)/2,42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	parent.add_child(b)

func _pick_forms() -> void:
	_modal("选择形态")
	var cats := {}
	for option in options:
		var cat := Catalog.category(option)
		cats[cat] = int(cats.get(cat,0))+1
	if options.size()<=8 or cats.size()<2:
		_form_list("")
		return
	var g := _choices()
	for cat in cats:
		_choice(g,"%s   ·   %d"%[cat,cats[cat]],_form_list.bind(cat),cat==Catalog.category(current))

func _form_list(category: String) -> void:
	_modal(category if not category.is_empty() else "选择形态")
	var search := LineEdit.new()
	search.placeholder_text = "搜索形态名称"
	search.clear_button_enabled = true
	search.add_theme_font_size_override("font_size",14)
	search.add_theme_color_override("font_color",UI.INK)
	search.add_theme_color_override("font_placeholder_color",UI.MUTED)
	search.add_theme_stylebox_override("normal",UI.box(UI.CARD))
	search.text_submitted.connect(func(_s: String) -> void: search.release_focus())
	var many := options.size()>8
	if many:
		UI.place(chooser,search,10,54,size.x-20,36)
	else:
		search.free()
	var g := _choices(97.0 if many else 55.0)
	var fill := func(q: String) -> void:
		UI.clear(g)
		for option in options:
			if not category.is_empty() and Catalog.category(option)!=category: continue
			if not q.is_empty() and not (str(option.label)+" "+str(option.art_key)).containsn(q): continue
			_choice(g,str(option.label),_select_form.bind(option),current.key==option.key)
		if g.get_child_count()==0:
			g.add_child(UI.label("没有匹配的形态",14,UI.MUTED))
	if many: search.text_changed.connect(fill)
	fill.call("")
	form_subcategory = category

func _select_form(option: Dictionary) -> void:
	current = option
	tera = ""
	giant = false
	_finish_pick()

func _pick_shine() -> void:
	_modal("选择闪光")
	var g := _choices()
	for key in SHINE_LABEL:
		_choice(g,SHINE_LABEL[key],_select_shine.bind(key),key==shiny_kind)

func _select_shine(key: String) -> void:
	shiny_kind = key
	_finish_pick()

func _pick_battle() -> void:
	_modal("选择战斗状态")
	var g := _choices()
	if current.kind in ["mega","gmax"]:
		_choice(g,Catalog.category(current),_finish_pick,true)
		_choice(g,"返回基础形态",_select_form.bind(options[0]))
		return
	_choice(g,"常态",_select_battle.bind(""),tera.is_empty() and not giant)
	if not int(current.species_id) in [888,889,890] and Catalog.tera_types(current).size()>1:
		_choice(g,"极巨化展示",_select_battle.bind("giant"),giant)
	for key in Catalog.tera_types(current):
		_choice(g,"太晶 · "+_type_name(key),_select_battle.bind(key),key==tera)

func _select_battle(value: String) -> void:
	giant = value=="giant"
	tera = "" if giant else value
	_finish_pick()

func _pick_stats() -> void:
	_modal("种族值与特性")
	var sc := UI.scroll(chooser,Vector2(14,56),size-Vector2(28,66))
	var rows := UI.list_box(sc,8)
	var info := Catalog.stats(current)
	var base: Dictionary = info.get("base",{})
	rows.add_child(UI.label(str(current.label),17,UI.GREEN))
	rows.add_child(UI.wrapped("HP  %d       攻击  %d       防御  %d\n特攻  %d       特防  %d       速度  %d"%[int(base.get("hp",0)),int(base.get("atk",0)),int(base.get("def",0)),int(base.get("spa",0)),int(base.get("spd",0)),int(base.get("spe",0))],15))
	rows.add_child(UI.label("捕获率   %d"%int(info.get("catch_rate",0)),13,UI.MUTED))
	for id in info.get("abilities",[]):
		var ability_name := str((Data.abilities.get(int(id),{}) as Dictionary).get("name",""))
		var desc := str(Data.ability_effect(ability_name).get("desc",""))
		rows.add_child(UI.wrapped(ability_name+"    "+desc,13))

func _finish_pick() -> void:
	form_subcategory = ""
	handle_back()
	_draw_detail()

func handle_back() -> bool:
	if is_instance_valid(chooser) and not form_subcategory.is_empty():
		form_subcategory = ""
		_pick_forms()
		return true
	var modal: Control = chooser if is_instance_valid(chooser) else detail
	if is_instance_valid(modal):
		remove_child(modal)
		modal.queue_free()
		if modal==chooser: chooser=null
		else: detail=null
	else:
		closed.emit()
		queue_free()
	return true
