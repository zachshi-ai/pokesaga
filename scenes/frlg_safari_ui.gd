extends ColorRect
## Safari encounters have no player combatant. Catch, feed, distract or leave.
signal action_chosen(action: String)
var info: Label
var moves: Dictionary={}

func setup(mon: Dictionary,status: String, actions := [["ball","扔原野球"],["bait","投食"],["rock","扔石头"],["run","离开"]]) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color=Color("#294942")
	var view:=VBoxContainer.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.offset_left=18
	view.offset_right=-18
	view.offset_top=6
	view.offset_bottom=-8
	var name_label:=Label.new()
	name_label.text="%s　Lv.%d"%[mon.name,mon.level]
	name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	view.add_child(name_label)
	var pic:=TextureRect.new()
	pic.texture=load(Data.sprite_path(int(mon.species_id),str(mon.get("form",""))))
	pic.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	pic.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical=Control.SIZE_EXPAND_FILL
	view.add_child(pic)
	info=Label.new()
	info.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	info.text=status
	view.add_child(info)
	var grid:=GridContainer.new()
	grid.columns=2
	grid.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	view.add_child(grid)
	for entry in actions:
		var b:=Button.new()
		b.text=entry[1]
		b.custom_minimum_size=Vector2(125,32)
		b.pressed.connect(func():action_chosen.emit(entry[0]))
		grid.add_child(b)
		moves[entry[0]]=b
