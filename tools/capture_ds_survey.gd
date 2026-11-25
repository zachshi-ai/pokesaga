extends SceneTree
## Capture the production Godot viewport for each edition and registered field.
## Godot --resolution 480x320 --path . -s tools/capture_ds_survey.gd -- hgss /tmp/views
const SETS={"hgss":["johto","hgss/maps"], "platinum":["sinnoh","platinum_native/maps"],"flower":["sinnoh","platinum_native/flower"],"bw":["unova","unova_native/bw"],"b2":["unova","unova_native/b2"],"crystal":["johto","regions/johto/maps"],"sinnoh_transit":["sinnoh","regions/sinnoh/maps"],"unova_transit":["unova","regions/unova/maps"]}
func _initialize():run.call_deferred()
func run():
	var args=OS.get_cmdline_user_args()
	var era=args[0];var folder=args[1];var r=SETS[era][0]
	var db=root.get_node("Data")
	if r=="unova":db.set_unova_era("bw" if era=="bw" else "b2")
	var world=load("res://core/world.gd").new()
	root.add_child(world)
	world.taken={"s_flower_path":era=="flower"}
	await process_frame
	DirAccess.make_dir_recursive_absolute(folder+"/"+era)
	for f in DirAccess.get_files_at("res://content/"+SETS[era][1]):
		if f.get_extension()!="json":continue
		var mid=f.get_basename()
		if era in ["crystal","sinnoh_transit","unova_transit"]:
			if not mid in db.load_region(r).map_ids:continue
			if era=="crystal" and FileAccess.file_exists("res://content/hgss/maps/"+f):continue
			if era=="sinnoh_transit" and FileAccess.file_exists("res://content/platinum_native/maps/"+f):continue
			if era=="unova_transit" and not mid.begins_with("unova_pass_"):continue
		if args.size()>2 and not mid in args.slice(2):continue
		world.load_map(db.load_map(r,mid))
		world.finish_walk()
		await process_frame
		await RenderingServer.frame_post_draw
		var img=root.get_texture().get_image()
		img.resize(240,160,Image.INTERPOLATE_NEAREST)
		img.save_png(folder+"/"+era+"/"+mid+".png")
	quit()
