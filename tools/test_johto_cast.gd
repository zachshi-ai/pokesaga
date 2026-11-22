extends SceneTree
## Johto event art must keep Brendan and the old title, and each named identity.
const Cast := preload("res://core/johto_gba_cast.gd")
const Save := preload("res://core/save_game.gd")
var failed := false
var checks := 0

func _initialize():
	call_deferred("run")

func expect(value: bool,label: String):
	checks+=1
	if not value:
		failed=true
		push_error(label)

func shot(label: String) -> void:
	var folder:=OS.get_environment("JOHTO_CAST_SCREENSHOTS")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	await create_timer(2.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+label+".png")

func check_named_actor(world, db, mid: String, role: String, identity: String, flags: Dictionary) -> void:
	world.load_map(db.load_map("johto",mid))
	world.refresh_story_actors(flags)
	var index: int = world.npcs.find_custom(func(n): return n.get("role","")==role)
	expect(index>=0, "missing story actor "+role)
	if index<0: return
	var actor: Sprite2D = world._npc_nodes[index*2+1]
	expect(actor.get_meta("johto_identity","")==identity, role+" field art")
	expect(actor.texture!=world.PLAYER_WALK and world._player_sprite.texture==world.PLAYER_WALK, role+" and Brendan have distinct sheets")

func run():
	var sprite:=Sprite2D.new()
	for key in Cast.book():
		for face in Cast.SOURCE_FRAMES:
			for stride in [0,1,2]:
				Cast.draw(sprite,key,face,stride)
				var region: Rect2=sprite.texture.region
				expect(Rect2(Vector2.ZERO,sprite.texture.atlas.get_size()).encloses(region),key+face+str(stride))
	sprite.free()
	Save.use_test_slot()
	var game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await preload("regional_start.gd").enter(game,"johto")
	await process_frame
	var world=game.world
	expect(game.title_screen==null and world.map_data.id=="johto_players_house_2f","direct Johto start in bedroom")
	expect(world._player_sprite.texture==world.PLAYER_WALK and world._player_sprite.hframes==9,"original Emerald Brendan walk sheet")
	expect(world._field_actor_scale()==1.0,"native full-scale sprite on 16px terrain")
	var foot_y: float=world._player_sprite.position.y+world.PLAYER_WALK.get_height()*0.5
	expect(foot_y==(world.player_pos.y+1)*16,"Brendan stands on the actual walk tile")
	await shot("bedroom")
	game._do_warp({"region":"johto","map":"johto_elms_lab","at":[3,2]})
	game._close_all_dialogs()
	var machine: Dictionary=world._npc_at(Vector2i(8,4))
	expect(machine.get("starter_balls",-1)==3,"three balls on the single lab device")
	var elm_idx:int=world.npcs.find_custom(func(n):return n.get("role","")=="j_elm")
	expect(elm_idx>=0 and world._npc_nodes[elm_idx*2+1].get_meta("johto_identity","")=="elm","Elm wears his own GBA field sprite")
	if machine.get("starter_balls",-1)==3:
		game._flags().johto_elm_told=true
		world.warp_to(Vector2i(8,5))
		world.facing="up"
		world._sync_player()
		await shot("elm-lab")
		game._on_action()
		var buttons=game.menu_layer.get_child(-1).find_children("*","Button",true,false)
		var choices=buttons.filter(func(n):return n.text in ["菊草叶 · 草","火球鼠 · 火","小锯鳄 · 水"])
		expect(choices.size()==3,"all three choices via native action")
		if choices.size()==3:
			choices[2].pressed.emit()
			expect(Save.existing().flags.get("j_starter_species",0)==158,"Totodile saved through the standard award")
			expect(world._npc_at(Vector2i(8,4)).get("starter_balls",-1)==2,"chosen ball leaves the lab device")
			game._close_all_dialogs()
			game._on_action()
			expect(game.save_data.party.filter(func(n):return n is Dictionary and not n.is_empty()).size()==1,"one starter per save")
	var db=root.get_node("Data")
	check_named_actor(world,db,"johto_new_bark_town","j_watching_rival","silver",{})
	world.refresh_story_actors({"j_mystery_egg":true})
	expect(world.npcs.all(func(n): return n.get("role","")!="j_watching_rival"),"Silver leaves the lab window on schedule")
	check_named_actor(world,db,"johto_goldenrod_gym","j_gym3","whitney",{})
	check_named_actor(world,db,"johto_silver_cave_room_3","j2_red","red_normal",{"j2_silver_pass":true})
	world.refresh_story_actors({"j2_silver_pass":true,"j2_red_away":true})
	expect(world.npcs.all(func(n): return n.get("role","")!="j2_red"),"Red leaves the summit after the battle")
	world.load_map(db.load_map("kanto","pallet_town_players_house_2f"))
	expect(world._player_sprite.texture==world.PLAYER_WALK,"Brendan persists on returning to Kanto")
	Save.clear_test_slot()
	print("JOHTO EMERALD CAST ",checks," checks ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
