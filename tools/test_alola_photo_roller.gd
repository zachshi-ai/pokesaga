extends SceneTree
## Test the controls, persisted photos, all legal Roller sequences and the earned clothing on Brendan's real sprite.
var game
var failed:=false
var source
var presses:=0
var photo_file:=""
func _initialize() -> void:run.call_deferred()
func frames() -> void:await process_frame;await process_frame
func ck(ok:bool,why:String) -> void:
	if not ok:failed=true;push_error(why)
func click(label:String) -> bool:
	for b in game.menu_layer.find_children("*","Button",true,false):
		if b.is_visible_in_tree() and not b.disabled and b.text.begins_with(label):b.pressed.emit();presses+=1;await frames();return true
	ck(false,"No button "+label);return false
func clear() -> void:game._close_all_dialogs();await frames()
func at(mid:String) -> void:
	var d:Dictionary=root.get_node("Data").load_map("alola",mid)
	game._do_warp({"region":"alola","map":mid,"alola_native":true,"at":d.spawn})
	await frames();await clear()
	ck(game.world.map_data.id==mid,mid)
	var o:Dictionary=d.objects.filter(func(obj):return obj.has("alola_club"))[0]
	var key:=Vector2i(o.at[0],o.at[1]);var w=game.world
	var dirs:={"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}
	var start:Vector2i=w.player_pos;var todo:Array=[start];var parent:Dictionary={start:null}
	var facing:="";var dest:=Vector2i.ZERO
	while facing=="" and not todo.is_empty():
		var p:Vector2i=todo.pop_front()
		for direction in dirs:
			var delta:Vector2i=dirs[direction];var xy:=p+delta
			if xy==key:facing=direction;dest=p;break
			if parent.has(xy) or not w.warp_at(xy).is_empty() or not w.can_enter(xy,delta):continue
			todo.append(xy);parent[xy]=[p,delta]
	if facing=="":ck(false,"Cannot physically reach camera/console "+mid);return
	var steps:Array=[]
	while dest!=start:
		var leg:Array=parent[dest];steps.push_front(leg[1]);dest=leg[0]
	for step in steps:ck(w.step(step),"blocked during approach");w.tick_walk(1)
	w.facing=facing;game._on_action();await frames()
func run() -> void:
	source=load("res://core/save_game.gd");source.use_test_slot()
	var args:=OS.get_cmdline_user_args()
	var data:Dictionary=source.empty() if args.is_empty() else JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if args.is_empty():
		data.region="alola";data.map="alola_home";data.pos=[8,7]
		data.chapters={"alola":"carried"};data.flags={"a_version":"ultra_sun","a_started":true,"a_hala":true,"a_guzma_garden":true,"a_nihilego":true,"a_electric":true,"a_grass":true,"a_hokulani":true}
	data.erase("alola_photos");data.flags.erase("a_roller_prize");data.flags.erase("a_roller_rank");data.flags.a_trial_guide_outfit=true
	source.save(data);game=load("res://scenes/boot.tscn").instantiate();root.add_child(game);await frames()
	game.title_screen.continue_button.pressed.emit();await frames();await clear()
	if game.save_data.party.is_empty():game.save_data.party=[load("res://core/party.gd").make(728,12,[55])]
	await at("alola_observatory_151")
	if not await click("入门"):finish();return
	var keys:=["左上磁铁","右上磁铁","左下磁铁","右下磁铁"]
	for i in 4:await click(keys[0])
	var ui=game.menu_layer.get_child(-1);ck(ui.message.contains("再试一次"),"four bad moves bounded")
	await click("重新开始")
	var paths:Array=[[2,0,1],[0,3,3],[2,2,2,3],[1,0,1,3]]
	var starting:int=game._bag_count("PP极限提升剂")
	for i in 4:
		if i>0:await click("下一关")
		for n in paths[i]:await click(keys[n])
		ck(int(game._flags().get("a_roller_rank",0))==i+1,"passed Roller "+str(i))
	ck(game._bag_count("PP极限提升剂")==starting+1,"single PP Max reward")
	await click("离开");await at("alola_photo_hauoli");await click("更衣");await click("考验向导服")
	ck(game.world._player_sprite.texture.resource_path.contains("guide_player_emerald"),"outfit replaces field sheet")
	game._on_action();await frames();await click("和伙伴合照");await click(game.save_data.party[0].name)
	var studio=game.menu_layer.get_child(-1)
	await click("背景");await click("花园");await click("姿势");await click("跃起");await click("边框");await click("夕阳边框")
	await click("贴纸");await click("花朵")
	var ev:=InputEventMouseButton.new();ev.button_index=MOUSE_BUTTON_LEFT;ev.pressed=true;ev.position=Vector2(50,55)
	studio.preview_rect.gui_input.emit(ev);await frames();ck(studio.stamps.size()==1,"touch placed sticker")
	await click("拍照");ck(game.save_data.get("alola_photos",[]).size()==1,"photo in shared save")
	if failed:finish();return
	photo_file="user://alola-album/"+str(game.save_data.alola_photos[0].file)
	var img:=Image.load_from_file(photo_file);ck(img.get_size()==Vector2i(320,184),"PNG saved to application storage")
	var out:=OS.get_environment("POKESAGA_PHOTO_TEST_PREVIEW")
	if out.is_absolute_path():img.save_png(out)
	await click("返回");await at("alola_photo_konikoni");await click("翻看相册")
	var gallery=game.menu_layer.get_child(-1);ck(gallery.index==0 and gallery.picture.get_data()==img.get_data(),"second studio reopened same pixels")
	await click("返回");game.queue_free();await frames();game=load("res://scenes/boot.tscn").instantiate();root.add_child(game);await frames()
	game.title_screen.continue_button.pressed.emit();await frames();await clear()
	game._use_bag_item("阿罗拉相册");await frames()
	ck(game.menu_layer.get_child(-1).index==0 and game._flags().a_guide_worn and int(game._flags().a_roller_rank)==4,"album, clothing and four stages survive restart")
	finish()
func finish() -> void:
	if photo_file!="":DirAccess.remove_absolute(ProjectSettings.globalize_path(photo_file))
	source.clear_test_slot()
	print("ALOLA ROLLER AND PHOTO ", "FAIL" if failed else "PASS"," UI inputs=",presses)
	quit(1 if failed else 0)
