extends ColorRect
## Four touch targets fit the 480px GBA-style handheld layout.
signal finished(won: bool)
const Contest := preload("res://core/emerald_contest.gd")
const Art := preload("res://core/dex_art.gd")
const CREAM := Color("#fff5da")
const GOLD := Color("#ffd582")
const MUTED := Color("#a7d5ca")
var contest: Contest
var db
var column := VBoxContainer.new()
var mode := "choose"
var last_results: Array=[]
var done := false

func setup(runner: Contest, database) -> void:
	contest=runner
	db=database
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color=Color("#162d37")
	mouse_filter=Control.MOUSE_FILTER_STOP
	var margin:=MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right"]:margin.add_theme_constant_override("margin_"+side,12)
	for side in ["top","bottom"]:margin.add_theme_constant_override("margin_"+side,6)
	margin.add_child(column)
	column.add_theme_constant_override("separation",4)
	render()

func label_at(parent: Control, value: String, size: int, ink:=CREAM) -> Label:
	var text:=Label.new()
	text.text=value
	text.add_theme_font_size_override("font_size",size)
	text.add_theme_color_override("font_color",ink)
	text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	text.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(text)
	return text

func button_at(parent: Control, title: String, action: Callable) -> Button:
	var button:=Button.new()
	button.text=title
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.custom_minimum_size=Vector2(0,37)
	button.add_theme_font_size_override("font_size",13)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("#294b54")
	style.set_border_width_all(1)
	style.border_color=Color("#659e98")
	style.set_corner_radius_all(5)
	button.add_theme_stylebox_override("normal",style)
	parent.add_child(button)
	button.pressed.connect(action,CONNECT_ONE_SHOT)
	return button

func render() -> void:
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	label_at(column,"%s · %s级华丽大赛" % [Contest.CATEGORIES[contest.category],Contest.RANKS[contest.rank]],17,GOLD)
	var stage:=TextureRect.new()
	stage.texture=load("res://assets/contest_audience.png")
	stage.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	stage.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	stage.custom_minimum_size=Vector2(0,87)
	column.add_child(stage)
	var scoreboard:=HBoxContainer.new()
	stage.add_child(scoreboard)
	scoreboard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in contest.entrants.size():
		var n: Dictionary=contest.entrants[i]
		var tile:=VBoxContainer.new()
		tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tile.add_theme_constant_override("separation",0)
		scoreboard.add_child(tile)
		var name_tag:=label_at(tile,n.name,12,GOLD if i==0 else CREAM)
		name_tag.add_theme_color_override("font_outline_color",Color("#21303a"))
		name_tag.add_theme_constant_override("outline_size",4)
		var portrait:=TextureRect.new()
		portrait.texture=Art.battle_texture(n.species,n.form,n.shiny,false)
		portrait.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size=Vector2(0,50)
		tile.add_child(portrait)
		var score_tag:=label_at(tile,"初审 %d" % n.opening if contest.round_number==0 else "表演 %+d" % n.points,11,CREAM)
		score_tag.add_theme_color_override("font_outline_color",Color("#243044"))
		score_tag.add_theme_constant_override("outline_size",4)
	if mode=="confirm":
		label_at(column,"要离开本次比赛吗？",16)
		button_at(column,"继续比赛",func():mode="choose";render())
		button_at(column,"退出比赛",func():end(false))
		return
	if mode=="results":
		for i in contest.entrants.size():
			var index: int=contest.standings()[i]
			label_at(column,"第 %d 名　%s　%d 分" % [i+1,contest.entrants[index].name,contest.total(index)],13,GOLD if index==0 else CREAM)
		button_at(column,"领取结果",func():end(contest.standings()[0]==0))
		return
	if mode=="round":
		for row in last_results:
			var n: Dictionary=contest.entrants[row.index]
			var move_name: String=db.move_of(row.move).get("name","") if row.move else "暂停表演"
			label_at(column,"%s　%s　%+d" % [n.name,move_name,n.appeal],12)
		button_at(column,"查看名次" if contest.round_number==5 else "下一回合",func():
			mode="results" if contest.round_number==5 else "choose"
			render())
		return
	label_at(column,"第 %d / 5 回合　　观众热度 %d / 5" % [contest.round_number+1,contest.crowd],14)
	var names: Array=[]
	for i in contest.order:names.append(str(contest.entrants[i].name))
	label_at(column,"出场顺序　"+" → ".join(names),11,MUTED)
	var grid:=GridContainer.new()
	grid.columns=2
	column.add_child(grid)
	for id in contest.entrants[0].moves:
		var m: Dictionary=Contest.data().moves[str(id)]
		var title:="%s　%s　♥%d" % [db.move_of(id).get("name",""),Contest.CATEGORIES[m.category],int(m.appeal)/10]
		button_at(grid,title,func():
			last_results=contest.turn(id)
			mode="round"
			render())

func end(won: bool) -> void:
	if done:return
	done=true
	hide()
	finished.emit(won)
	queue_free()

func handle_back() -> void:
	if mode in ["results","round"]:return
	mode="choose" if mode=="confirm" else "confirm"
	render()
