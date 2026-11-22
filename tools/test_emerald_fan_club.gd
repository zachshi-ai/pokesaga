extends SceneTree
const Fan:=preload("res://core/emerald_fan_club.gd")
const Save:=preload("res://core/save_game.gd")
var g
var checks:=0
var failed:=false
func _initialize():run.call_deferred()
func check(ok:bool,why:String):
	checks+=1
	if not ok:failed=true;push_error("Emerald Fan Club: "+why)
func click(prefix:String)->bool:
	for ui in g.menu_layer.get_children():
		if not ui.is_visible_in_tree() or ui.is_queued_for_deletion():continue
		for b in ui.find_children("*","Button",true,false):
			if b.is_visible_in_tree() and b.text.begins_with(prefix):
				b.pressed.emit();return true
	check(false,"button "+prefix);return false
func clear():g._close_all_dialogs()
func enter(mid:String):
	clear()
	var m:Dictionary=root.get_node("Data").load_map("hoenn",mid)
	g._do_warp({"region":"hoenn","map":mid,"at":m.spawn})
	clear()
func act(script:String):
	for npc in g.world.npcs:
		if str(npc.get("source_script","")).ends_with(script):
			var pos:=Vector2i(int(npc.at[0]),int(npc.at[1]))
			for pair in [[Vector2i.DOWN,"up"],[Vector2i.UP,"down"],[Vector2i.LEFT,"right"],[Vector2i.RIGHT,"left"]]:
				var next:Vector2i=pos+pair[0]
				if g.world.is_blocked(next) or not g.world._npc_at(next).is_empty():continue
				g.world.warp_to(next);g.world.facing=pair[1];g._on_action();return
	check(false,"map actor "+script)
func msg()->String:
	return "" if g._dialogs.is_empty() else " ".join(g._dialogs.back().lines)
func switch_id(id:int):
	g.save_data.js_trainer_id=7280+id
	Fan.state(g).erase("id")
	check(Fan.state(g).id==id/2,"trainer ID variant "+str(id))
func run():
	Save.use_test_slot()
	g=load("res://scenes/boot.tscn").instantiate();root.add_child(g);await process_frame
	await preload("regional_start.gd").enter(g,"hoenn")
	g.rng.seed=9891203
	enter("hoenn_dewford")
	var db:=Fan.data();check(db.words.size()==1815 and db.water.size()==447,"native vocabulary and all 447 river tiles")
	var s:=Fan.state(g)
	check(Fan.permitted(g,18).is_empty() and Fan.permitted(g,21).is_empty(),"champion and national vocabulary gates are separate")
	g._flags().h_champion=true
	check(Fan.permitted(g,18).size()==154 and Fan.permitted(g,19).size()==200 and Fan.permitted(g,21).is_empty(),"league opens both complete move word sets")
	g._flags().h_national_dex=true
	check(Fan.permitted(g,21).size()==251 and Fan.permitted(g,1).size()==21,"National Dex and hidden trainer words follow native availability")
	g._manual_save()
	check(s.stats.get("SAVED_GAME",0)>0,"real manual save records a storyteller statistic")
	var initial:=Fan.trends(g).duplicate(true)
	check(initial.size()==5 and initial[0].score>=initial[1].score,"five ranked local phrases")
	act("TrendyPhraseBoy");click("我听说");click("生活");click("家务");click("爱好");click("音乐");click("投稿")
	check(Fan.phrase(s.trends[0].words)=="家务 音乐" and int(s.trends[0].rand)==int(initial[0].rand),"field submission updates the initial phrase while preserving first Feebas seed")
	clear();act("TrendyPhraseBoy");click("没错");clear()
	enter("em_dewford_town_hall")
	act("EventScript_Woman");check("家务 音乐" in msg(),"fan hall adopts the phrase");clear()
	g.world.warp_to(Vector2i(7,2));g.world.facing="up";g._on_action();check("家务 音乐" in msg(),"painting responds to A with the actual phrase");clear()
	g.world.warp_to(Vector2i(0,2));g.world.facing="up";g._on_action();check("家务 音乐" in msg(),"bookcase responds to A with the actual phrase");clear()
	var day:int=s.day
	var aged:=Fan.trends(g,day+5)
	check(int(s.day)==day+5 and aged.size()==5 and aged[0].score>=aged[1].score,"clock ages and reorders saved phrases")
	enter("em_mauville_city_pokemon_center_1f")
	switch_id(0)
	var music:=Fan.song_audio(s.lyrics)
	check(music.data.size()>50000 and music.get_length()>2 and music.data.count(0)<music.data.size()*0.85,"audible multisyllable default song is rendered from original samples")
	act("MauvilleOldMan");click("听他唱歌");check("摇摆" in msg(),"Bard sings six words in the center");clear()
	click("改一句歌词");click("第2词");click("生活");click("商店");clear();click("就这样唱");clear()
	check(s.song_changed and Fan.name_of(s.lyrics[1])=="商店" and Fan.song_audio(s.lyrics).data!=music.data,"Bard previews and saves one real vocal replacement")
	act("MauvilleOldMan");click("听他唱歌");clear();check(s.song_changed,"confirmed song is retained on revisit")
	switch_id(2);act("MauvilleOldMan");clear();act("MauvilleOldMan");clear()
	check(s.taught.size()==1 and Fan.permitted(g,20)==s.taught,"Hipster teaches exactly one usable trendy saying")
	switch_id(4);g._flags().get_or_add("h_decorations",{}).PRETTY_FLOWERS=1
	act("MauvilleOldMan");click("夜巡灵玩偶");click("漂亮的花");click("交换装饰");clear()
	check(g._flags().h_decorations.get("DUSKULL_DOLL",0)==1 and g._flags().h_decorations.PRETTY_FLOWERS==0 and s.traded,"Trader transfers decorations into the real base PC inventory")
	act("MauvilleOldMan");check("上次" in msg(),"Trader rejects another offer");clear()
	switch_id(6)
	s.stats={"STARTED_TRENDS":1}
	act("MauvilleOldMan");click("听听传说");click("讲述自己的事迹");clear()
	check(s.story=="STARTED_TRENDS" and s.story_count==1,"storyteller selects eligible real statistic")
	Fan.record(g,"STARTED_TRENDS");act("MauvilleOldMan");click("听听传说");check("2次" in msg() and s.story_count==2,"storyteller records and narrates higher score");clear()
	switch_id(8);act("MauvilleOldMan");click("听他说说")
	var count:=0
	while g._dialogs.is_empty() and count<11:
		if not click("我不这么想"):break
		count+=1
	check(count>=1 and count<=10 and "下次" in msg(),"Giddy reacts to no and finishes within ten tales");clear()
	enter("hoenn_119")
	g.save_data.party=[g.PartyScript.make(260,55,[57])]
	var ids:=Fan.fishing_numbers(int(Fan.trends(g)[0].rand));check(ids.size()==6 and ids.min()>=4 and ids.max()<=447,"six Emerald fishing numbers excluding the first three")
	var got:=false
	for index in ids:
		var loc:Array=db.water[int(index)-1];var pos:=Vector2i(int(loc[0]),int(loc[1]))
		for pair in [[Vector2i.DOWN,"up"],[Vector2i.UP,"down"],[Vector2i.LEFT,"right"],[Vector2i.RIGHT,"left"]]:
			var stand:Vector2i=pos+pair[0]
			if g.world.is_blocked(stand) and not g.world.is_water(stand):continue
			g.world.surfing=g.world.is_water(stand);g.world.warp_to(stand);g.world.facing=pair[1]
			for n in 14:
				g._fish("破旧钓竿")
				if not is_instance_valid(g.active_battle):clear();continue
				var opponent:Dictionary=g.active_battle.battle.cur_b()
				got=int(opponent.species_id)==349 and int(opponent.level)>=20 and int(opponent.level)<=25
				g.active_battle.finished.emit("fled");await process_frame;clear()
				if got:break
			if got:break
		if got:break
	check(got,"normal fishing controller hooks Feebas on a correct Route 119 tile")
	g._persist();var loaded:=Save.existing()
	check(loaded.h_fan_club.song_changed and loaded.h_fan_club.traded and loaded.h_fan_club.story_count==2 and loaded.h_fan_club.taught.size()==1,"shared save round trip preserves all recorded events")
	Save.clear_test_slot();g.queue_free();await process_frame
	print("EMERALD FAN CLUB ",checks," checks ","FAIL" if failed else "PASS");quit(int(failed))
