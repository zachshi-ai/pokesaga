extends SceneTree

var world
var db
var failures: Array = []
func _initialize() -> void:
	call_deferred("run")

func field(mid: String) -> void:
	world.load_map(db.load_map("hoenn",mid))
	world.finish_walk()

func check(ok: bool, what: String) -> void:
	if not ok: failures.append(what)

func run() -> void:
	db=root.get_node("Data")
	world=load("res://core/world.gd").new()
	root.add_child(world)
	world.warp_ready.connect(func(target):
		field(target.map)
		world.arrive(target))
	field("em_inside_of_truck")
	check(world.tile_size==Vector2i(5,5),"truck size")
	for i in world.npcs.size():
		var img: Texture2D=world._npc_nodes[i*2+1].texture
		check(img is AtlasTexture and img.atlas.resource_path.ends_with("/MovingBox.png"),"truck crate %d actual sprite"%i)
	for key in ["right","right","right"]:
		check(world.step(world.WARP_DIR[key]),"truck step")
		world.tick_walk(0.3)
	check(world.map_data.id=="littleroot_town" and world.player_pos==Vector2i(3,10),"truck original exit")
	var cases={"em_oldale_town_pokemon_center_1f":"heal","em_oldale_town_mart":"shop"}
	for mid in cases:
		field(mid)
		var service: Array=world.npcs.filter(func(n):return n.get(cases[mid],false))
		check(not service.is_empty(),"staff "+mid)
		if service.is_empty():continue
		var townie: Dictionary=service[0]
		var face_found:=false
		for d in world.WARP_DIR:
			for reach in [1,2]:
				var at:=Vector2i(townie.at[0],townie.at[1])-Vector2i(world.WARP_DIR[d])*int(reach)
				if not world.can_enter(at,Vector2i.ZERO,true): continue
				world.warp_to(at)
				world.facing=d
				world.step_interact()
				face_found=world.last_npc.get(cases[mid],false)
				if face_found: break
			if face_found:break
		check(face_found,"counter A "+mid)
	field("em_sootopolis_city_gym_1f")
	check(world.map_data.mechanisms.stairs.size()==6,"ice stairs")
	field("hoenn_sootopolis")
	world.refresh_story_actors({"h_kyogre":true,"h_duel":true})
	check(world.emerald_collision[44][28]==1,"solid island below Groudon in the lake encounter")
	var animated_tiles: Array=world.map_data.mechanisms.legends.filter(func(cell):return int(cell[2])>=49152)
	check(animated_tiles.size()>600,"original storm-water animation bank")
	world.refresh_story_actors({"h_kyogre":true,"h_peace":true})
	check(world.emerald_collision[44][28]==0,"ordinary lake returns after Rayquaza")
	for mid in ["hoenn_woods","em_mauville_city_gym","em_petalburg_city_gym","em_fortree_city_gym","em_mossdeep_city_gym","em_sky_pillar_2f"]:
		field(mid)
		check(world.tile_size==Vector2i(world.map_data.size[0],world.map_data.size[1]),"native size "+mid)
	for gfx in ["MOM","PROF_BIRCH","RIVAL_MAY_NORMAL","BIRCHS_BAG","TRUCK"]:
		var sprite:=Sprite2D.new()
		preload("res://core/hoenn_field.gd").draw(sprite,{"source_gfx":"OBJ_EVENT_GFX_"+gfx},"up")
		check(sprite.texture is AtlasTexture and sprite.texture.atlas.resource_path.contains("/hoenn_native/actors/"),"source sprite "+gfx)
		sprite.free()
	world.free()
	print("HOENN FIELD ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)
