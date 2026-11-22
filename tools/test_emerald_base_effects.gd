extends "test_hoenn_items.gd"

const Effects := preload("res://core/hoenn_base_effects.gd")
const Room := "em_secret_base_red_cave1"

func walk(to: Vector2i, dir: Vector2i) -> void:
	game.world.warp_to(to-dir)
	check(game.world.step(dir),"walk onto furniture")
	game.world.tick_walk(1.0)

func run() -> void:
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await preload("regional_start.gd").enter(game,"hoenn")
	dismiss()
	var f: Dictionary=game._flags()
	f.h_base_site="test_room"
	f.h_base_furniture=[{"id":"RED_BALLOON","at":[3,5]},{"id":"SLIDE","at":[5,1]},{"id":"BREAKABLE_DOOR","at":[2,1]},{"id":"SAND_ORNAMENT","at":[3,1]},{"id":"JUMP_MAT","at":[2,4]},{"id":"C_HIGH_NOTE_MAT","at":[4,4]},{"id":"SPIN_MAT","at":[6,6]}]
	game.world.taken=f
	visit(Room)
	walk(Vector2i(3,5),Vector2i.DOWN)
	for i in 35:await process_frame
	check(game.world.hoenn_local.decor_frames["RED_BALLOON/3/5"]==2,"balloon animates to its popped tile")
	walk(Vector2i(2,2),Vector2i.UP)
	check(game.world.hoenn_local.decor_frames.has("BREAKABLE_DOOR/2/1"),"walking through the door opens both tiles")
	game.world.warp_to(Vector2i(3,3))
	game.world.facing="up"
	game._on_action()
	check(game.world.hoenn_local.decor_frames.has("SAND_ORNAMENT/3/1"),"A breaks the sand ornament")
	walk(Vector2i(2,4),Vector2i.DOWN)
	check(game.world.hoenn_local.get("decor_busy",false),"jump mat starts its two hops")
	for i in 65:await process_frame
	check(not game.world.hoenn_local.get("decor_busy",false),"mat returns input to the player")
	walk(Vector2i(6,6),Vector2i.RIGHT)
	for i in 70:await process_frame
	check(game.world.player_pos==Vector2i(5,6),"spin mat returns player in the opposite direction")
	game.world.warp_to(Vector2i(6,2))
	check(game.world.auto_step_dir()==Vector2i.DOWN,"slide moves player downhill")
	game.world.warp_to(Vector2i(5,2))
	check(not game.world.can_step(Vector2i.LEFT),"slide ladder blocks sideways exit")
	walk(Vector2i(4,4),Vector2i.DOWN)
	for sound in Effects.NOTE_SOUNDS.values()+Effects.POP_SOUNDS.values()+["breakable_door","ledge"]:
		var audio=load("res://assets/audio/sfx/%s.wav"%sound)
		check(audio is AudioStreamWAV and audio.get_length()>0,"furniture sound "+sound)
	visit(Room)
	check(not game.world.hoenn_local.has("decor_frames") and f.h_base_furniture.size()==7,"reentry restores intact decorations")
	visit("hoenn_league")
	game.save_data.money=3000
	game._open_shop()
	var shop=game.menu_layer.get_child(-1)
	check(shop.goods.size()==7 and shop.goods[5].name=="活力碎片","Ever Grande League original shop supplies")
	shop._buy(5)
	check(game._bag_count("活力碎片")>0 and game.save_data.money==1500,"buy a Revive at the League")
	shop._buy(6)
	shop.closed.emit()
	shop.queue_free()
	preload("res://core/johto_items.gd").use(game,"黄金喷雾")
	check(int(game.save_data.get("js_repel",0))==250,"use the League's Max Repel")
	Save.clear_test_slot()
	print("BASE EFFECTS ", "FAIL" if failed else "PASS"," ",checks)
	quit(1 if failed else 0)
