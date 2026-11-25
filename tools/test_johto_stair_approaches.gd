extends "res://tools/test_3ds_field_survey.gd"
## Native positions for residents whose Crystal coordinates had blocked the approach to a staircase.
const STAIRS := {
	"johto_celadon_dept_store_3f": ["johto_celadon_dept_store_4f", [6,8]],
	"johto_cerulean_pokecenter_1f": ["hgss_cerulean_pokecenter_b1f", [14,17]],
	"johto_ecruteak_tin_tower_entrance": ["johto_wise_trios_room", [3,19]],
	"johto_fuchsia_pokecenter_1f": ["hgss_fuchsia_pokecenter_b1f", [14,17]],
	"johto_goldenrod_dept_store_2f": ["johto_goldenrod_dept_store_1f", [18,7]],
	"johto_goldenrod_dept_store_5f": ["johto_goldenrod_dept_store_4f", [18,7]],
	"johto_olivine_pokecenter_1f": ["hgss_olivine_pokecenter_b1f", [14,17]],
	"johto_viridian_pokecenter_1f": ["hgss_viridian_pokecenter_b1f", [14,17]],
}
const GUARDED := {
	"johto_azalea_town": ["hgss_azalea_gym_entrance", "j_well_clear"],
	"johto_blackthorn_city": ["johto_blackthorn_gym_1f", "j_radio_free"]
}

func run() -> void:
	db=root.get_node("Data")
	root.add_child(world)
	world.warp_ready.connect(on_warp)
	for mid in STAIRS:
		var source: Dictionary = db.load_map("johto",mid)
		world.load_map(source)
		var doors := Passages.active(source).filter(func(w):return w.to.map==STAIRS[mid][0] and pos(w.at)==pos(STAIRS[mid][1]))
		if doors.size()!=1 or not near_gate(doors[0]):
			push_error("Could not take the stairs in "+mid)
			quit(1)
			return
		put_at(received)
		var backs := Passages.active(world.map_data).filter(func(w):return w.to.map==mid)
		var landing := world.player_pos
		var back_ok := false
		for door in backs:
			world.warp_to(landing)
			if cross(door,4000):
				back_ok=true
				break
		if not back_ok:
			push_error("Cannot return to "+mid)
			quit(1)
			return
	for mid in GUARDED:
		var source: Dictionary=db.load_map("johto",mid)
		var door: Dictionary=Passages.active(source).filter(func(w):return w.to.map==GUARDED[mid][0])[0]
		world.taken.clear()
		world.load_map(source)
		if near_gate(door):
			push_error("Gym opens before "+GUARDED[mid][1])
			quit(1)
			return
		world.taken[GUARDED[mid][1]]=true
		world.load_map(source)
		if not near_gate(door):
			push_error("Gym still blocked after "+GUARDED[mid][1])
			quit(1)
			return
	print("JOHTO STAIR APPROACHES PASS ",STAIRS.size()," two-way staircases, two story gates in both states, ",total_steps," steps")
	quit()
