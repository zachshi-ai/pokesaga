extends RefCounted
## Start the one shared adventure and take its regular travel item to a new region.
const NAMES := preload("res://core/region_journey.gd").NAMES

static func press(node: Node, caption: String) -> bool:
	for button in node.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and not button.disabled and str(button.text)==caption:
			button.pressed.emit()
			return true
	push_error("Missing regional travel control " + caption)
	return false

static func open_trip(g, region: String) -> bool:
	g._use_bag_item("地区转移器")
	var atlas = g.menu_layer.get_child(-1)
	return press(atlas,NAMES[region]) and press(atlas,"出发前往"+str(NAMES[region]))

static func dress_in_vaniville(g) -> bool:
	if g.world.map_data.id!="kalos_home_2f" or g.world.player_pos!=Vector2i(14,11):return false
	for leg in [[Vector2i.LEFT,6],[Vector2i.UP,3]]:
		for step in range(leg[1]):
			if not g.world.step(leg[0]):return false
			g.world.finish_walk()
	g.world.facing="up"
	g._on_action()
	while not g._dialogs.is_empty():g._on_action()
	return g._flags().get("k_dressed",false)

static func enter(g, region: String, mode := "carried", version := "x") -> bool:
	var tree: SceneTree = g.get_tree()
	if is_instance_valid(g.title_screen):
		if is_instance_valid(g.title_screen.continue_button):
			g.title_screen.continue_button.pressed.emit()
		else:
			g.title_screen.new_button.pressed.emit()
		await tree.process_frame
	for n in 80:
		if g._dialogs.is_empty(): break
		g._on_action()
	if not open_trip(g,region): return false
	await tree.process_frame
	if region=="hoenn":
		if not press(g.menu_layer,"乘坐搬家货车"): return false
		await tree.process_frame
	if not g.save_data.get("chapters",{}).has(region):
		if not press(g.menu_layer,"寄存队伍，重新组队" if mode=="boxed" else "带现有队伍出发"): return false
		if region=="kalos":
			await tree.process_frame
			if not press(g.menu_layer,"《Y》" if version=="y" else "《X》"):return false
	await tree.process_frame
	for frame in 600:
		if not g._escort_active: break
		await tree.process_frame
	return g.world.map_data.region==region and not g._escort_active
