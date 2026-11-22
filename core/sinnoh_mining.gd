extends RefCounted

const FOSSILS := ["SKULL_FOSSIL","ARMOR_FOSSIL","HELIX_FOSSIL","DOME_FOSSIL","OLD_AMBER","ROOT_FOSSIL","CLAW_FOSSIL"]
const STONES := ["FIRE_STONE","WATER_STONE","LEAF_STONE","THUNDER_STONE","HARD_STONE","EVERSTONE","HEART_SCALE","REVIVE","STAR_PIECE","ODD_KEYSTONE"]

static func enter(g) -> void:
	var state: Dictionary=g.save_data.get_or_add("sinnoh_underground",{})
	if state.is_empty():
		state.greeted=false
	g._pick("地下通道",["调查岩壁","与地下探险者打招呼","回到地面"],func(i):
		if i==0: dig(g)
		elif i==1:
			if not state.get("greeted",false):
				state.greeted=true
				g._flags().s_underground_greetings=int(g._flags().get("s_underground_greetings",0))+1
				g._persist()
			g._dialog(["地下的探险者向你打了招呼。","回到地面再次进入，才会遇到下一位探险者。"],"地下通道").closed.connect(func():enter(g))
		else:
			g.save_data.erase("sinnoh_underground")
			g._persist())

static func dig(g) -> void:
	var state: Dictionary=g.save_data.sinnoh_underground
	if not state.has("wall"):
		var keys:=STONES.duplicate()
		keys.append_array(FOSSILS if g._flags().get("s_national_dex",false) else ["SKULL_FOSSIL","ARMOR_FOSSIL"])
		var covered: Array=[]
		for i in 20:covered.append(g.rng.randi_range(1,3))
		var gems: Dictionary={}
		while gems.size()<3:
			gems[str(g.rng.randi_range(0,19))]=keys[g.rng.randi_range(0,keys.size()-1)]
		state.wall={"layers":covered,"rewards":gems,"hits":15,"hammer":false}
		g._persist()
	var ui:=ColorRect.new()
	ui.color=Color("#182227")
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.menu_layer.add_child(ui)
	g.panel_open+=1
	g._set_hud_visible(false)
	var column:=VBoxContainer.new()
	ui.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left=12
	column.offset_right=-12
	column.offset_top=8
	column.offset_bottom=-8
	var title:=Label.new()
	column.add_child(title)
	var grid:=GridContainer.new()
	grid.columns=5
	grid.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(grid)
	var controls:=HBoxContainer.new()
	column.add_child(controls)
	var mode:=Button.new()
	mode.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	controls.add_child(mode)
	var back:=Button.new()
	back.text="离开岩壁"
	back.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	controls.add_child(back)
	var wall: Dictionary=state.wall
	var draw:=func():
		title.text="地下通道 · 岩壁    稳定度 %d    剩余宝物 %d"%[int(wall.hits),wall.rewards.size()]
		mode.text="切换为镐" if wall.hammer else "切换为锤"
		for i in grid.get_child_count():
			var cell: Button=grid.get_child(i)
			var n:=int(wall.layers[i])
			cell.text=["·","░","▒","▓"][n]
			cell.modulate=[Color("#90928a"),Color("#ead5a9"),Color("#dea15a"),Color("#ba6f45")][n]
	var close:=func():
		if ui.is_queued_for_deletion():return
		ui.queue_free()
		g.panel_open-=1
		g._set_hud_visible(true)
	for i in 20:
		var btn:=Button.new()
		btn.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical=Control.SIZE_EXPAND_FILL
		grid.add_child(btn)
		btn.pressed.connect(func():
			if int(wall.hits)<=0 or wall.rewards.is_empty():return
			if int(wall.layers[i])==0:return
			wall.hits=int(wall.hits)-(2 if wall.hammer else 1)
			var offsets: Array=[Vector2i.ZERO,Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT] if wall.hammer else [Vector2i.ZERO]
			var found: Array=[]
			for offset in offsets:
				var p:=Vector2i(i%5,i/5)+Vector2i(offset)
				if p.x<0 or p.x>=5 or p.y<0 or p.y>=4:continue
				var j:=p.y*5+p.x
				wall.layers[j]=maxi(0,int(wall.layers[j])-(2 if j==i else 1))
				if int(wall.layers[j])==0 and wall.rewards.has(str(j)):
					var key:=str(wall.rewards[str(j)])
					wall.rewards.erase(str(j))
					var side=load("res://core/sinnoh_side.gd")
					side.give(g,key)
					found.append(side.item_name(key))
			draw.call()
			if wall.rewards.is_empty() or int(wall.hits)<=0:
				state.erase("wall")
				close.call()
				g._dialog(["获得%s。"%("、".join(found)) if not found.is_empty() else "岩层塌落，这面岩壁的挖掘结束了。"],"地下通道").closed.connect(func():enter(g))
			elif not found.is_empty():g._show_toast("挖到了%s！"%("、".join(found)))
			g._persist())
	mode.pressed.connect(func():
		wall.hammer=not wall.hammer
		draw.call())
	back.pressed.connect(func():
		state.erase("wall")
		g._persist()
		close.call()
		enter(g))
	draw.call()
