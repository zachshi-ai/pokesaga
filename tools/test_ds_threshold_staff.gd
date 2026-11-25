extends "res://tools/audit_ds_fields.gd"
## Replay the actual passage once with a fresh chapter and once after its actor's departure.
## godot --headless --path . -s tools/test_ds_threshold_staff.gd

func run():
	db=root.get_node("Data")
	world=Walker.new()
	root.add_child(world)
	world.warp_ready.connect(func(to):arrival=to)
	var args := OS.get_cmdline_user_args()
	var fixture := args[0] if not args.is_empty() else "res://doc/field-audit/ds-door-staff.tsv"
	var reader:=FileAccess.open(fixture,FileAccess.READ)
	if reader == null:
		push_error("Missing door staff cases: "+fixture)
		quit(1)
		return
	reader.get_line()
	var failures:=0
	var count:=0
	while not reader.eof_reached():
		var row:=reader.get_csv_line("\t")
		if row.size()<8:continue
		var era: String=row[0]
		var region: String=SETS[era][0]
		if region=="unova":db.set_unova_era(era)
		var where:=Vector2i(int(row[2]),int(row[3]))
		for open: bool in [false,true]:
			world.taken={"s_flower_path":era=="flower","u2_started":era=="b2"}
			if open:
				for flag in row[6].split(",",false):world.taken[flag]=true
			world.load_map(db.load_map(region,row[1]))
			var gates: Array=world.map_data.warps.filter(func(w):return point(w.at)==where and w.to.map==row[4])
			var wanted: String=row[7] if open or row[1] in ["unova_10","sinnoh_224"] else "npc_at_threshold"
			var got: String=gate(gates[0]) if gates.size()==1 else "ambiguous threshold"
			if got!=wanted:
				failures+=1
				push_error("%s %s %s expected %s got %s"%[row[1],where,world.taken,wanted,got])
			count+=1
	# Earlier saves can have a complete film journal from before the gate was fixed.
	var films=load("res://core/unova_side_activities.gd")
	var save: Dictionary={"flags":{},"unova_films":{}}
	for n in films.FILMS.size():save.unova_films[str(n)]={"hit":n!=0}
	films.restore_dressing_room(save)
	if save.flags.has("us_dressing_room"):failures+=1
	save.unova_films["0"].hit=true
	films.restore_dressing_room(save)
	if not save.flags.get("us_dressing_room",false):failures+=1
	print("DS door staff ",count," conditional passage checks, failed ",failures)
	print("DS DOOR STAFF PASS" if failures == 0 and count == 42 else "DS DOOR STAFF FAIL")
	quit(int(failures > 0 or count != 42))
