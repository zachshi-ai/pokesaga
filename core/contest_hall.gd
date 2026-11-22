extends RefCounted
const Contest := preload("res://core/emerald_contest.gd")
const Stage := preload("res://scenes/contest_stage.gd")
const Art := preload("res://core/dex_art.gd")
const KEYS := ["Cool","Beauty","Cute","Smart","Tough"]

static func talk(g, script: String) -> bool:
	if script=="LilycoveCity_ContestLobby_EventScript_ContestReceptionist":
		if not g._flags().get("h_item_pokeblock_case",false) and g._bag_count("宝可方块盒")==0:return false
		var options:=Contest.CATEGORIES.duplicate()
		options.append("离开")
		g._pick("报名参加哪一种华丽大赛？",options,func(i):
			if i<5:select_mon(g,i))
		return true
	if script in ["LilycoveCity_LilycoveMuseum_1F_EventScript_Curator","LilycoveCity_LilycoveMuseum_2F_EventScript_Curator"]:
		var count: int=g.save_data.get("contest_paintings",{}).size()
		if count==5 and not g._flags().get("h_glass_ornament",false):
			g._flags().h_glass_ornament=true
			preload("res://core/hoenn_base.gd").add_decoration(g,"GLASS_ORNAMENT")
			g._persist()
			g._dialog(["五幅画终于齐了！这座玻璃摆饰送给你。"],"馆长")
		else:
			g._flags().h_contest_gallery=true
			g._flags()["FLAG_HIDE_LILYCOVE_MUSEUM_CURATOR"]=true
			g.world.refresh_story_actors(g._flags())
			g._persist()
			if script.contains("_1F_"):
				g._dialog(["请上楼看看特别展厅。我想展出五种华丽大赛冠军的画像。"],"馆长").closed.connect(func():
					g._do_warp({"region":"hoenn","map":"em_lilycove_city_lilycove_museum_2f","at":[11,8],"hoenn_native":true}))
			else:g._dialog(["展厅里已有 %d 幅冠军画像。" % count],"馆长")
		return true
	return false

static func select_mon(g, cat: int) -> void:
	var slots: Array=[]
	var names: Array=[]
	for i in g.save_data.party.size():
		var mon=g.save_data.party[i]
		if not mon is Dictionary or mon.is_empty() or int(mon.get("hp",1))==0:continue
		if not mon.moves.any(func(id):return Contest.data().moves.has(str(int(id)))):continue
		slots.append(i)
		var ribbons: int=mon.get("contest_ribbons",{}).get(str(cat),0)
		names.append("%s　%s" % [mon.name,"尚未取得奖章" if ribbons==0 else Contest.RANKS[ribbons-1]+"奖章"])
	if slots.is_empty():
		g._dialog(["请带一只能上场、掌握丰缘时代招式的宝可梦。"],"华丽大赛接待员")
		return
	g._pick("选择参赛的宝可梦",names+["取消"],func(i):
		if i>=slots.size():return
		var mon: Dictionary=g.save_data.party[slots[i]]
		var max_rank: int=mini(3,int(mon.get("contest_ribbons",{}).get(str(cat),0)))
		g._pick("参赛级别",Contest.RANKS.slice(0,max_rank+1)+["取消"],func(rank):
			if rank<=max_rank:start(g,mon,cat,rank)))

static func start(g, mon: Dictionary, cat: int, rank: int) -> void:
	var runner:=Contest.new()
	runner.begin(mon,cat,rank,g._flags().get("h_champion",false),g.get_node("/root/Data"))
	var stage:=Stage.new()
	g.menu_layer.add_child(stage)
	g.panel_open+=1
	g._set_hud_visible(false)
	stage.finished.connect(func(won):
		g.panel_open=maxi(0,g.panel_open-1)
		g._set_hud_visible(g.panel_open==0)
		if runner.round_number!=5:return
		var winner: Dictionary=runner.entrants[runner.standings()[0]]
		g.save_data.get_or_add("contest_winners",{})[str(cat)]={"name":winner.name,"rank":rank,"species":winner.species}
		if won:
			var ribbons: Dictionary=mon.get_or_add("contest_ribbons",{})
			ribbons[str(cat)]=maxi(int(ribbons.get(str(cat),0)),rank+1)
		g._persist()
		if not won:return
		var dlg=g._dialog(["%s获得了%s%s奖章！" % [mon.name,Contest.CATEGORIES[cat],Contest.RANKS[rank]]],"华丽大赛接待员")
		if rank==3 and runner.total(0)>=800 and g._flags().get("h_contest_gallery",false):
			dlg.closed.connect(func():
				g._pick("画家想让这幅冠军画像在美术馆展出。",["同意展出","这次留念"],func(i):
					if i!=0:return
					g.save_data.get_or_add("contest_paintings",{})[str(cat)]={"name":mon.name,"species":mon.species_id,"form":mon.get("form",""),"shiny":mon.get("shiny",false)}
					mon.artist_ribbon=true
					g._persist()
					g._dialog(["我把画像送去美术馆。艺术家奖章请收好！"],"画家"))))
	stage.setup(runner,g.get_node("/root/Data"))

static func object_action(g, script: String) -> bool:
	if script.contains("ContestLobby_EventScript_ContestWinner"):
		var n:=int(script.right(1))-1
		var row: Dictionary=g.save_data.get("contest_winners",{}).get(str(n),{})
		g._dialog(["冠军榜等待着新的优胜者。" if row.is_empty() else "%s · %s级冠军　%s" % [Contest.CATEGORIES[n],Contest.RANKS[row.rank],row.name]])
		return true
	if not script.begins_with("LilycoveCity_LilycoveMuseum_2F_EventScript_") or not script.ends_with("Painting"):return false
	for i in KEYS.size():
		if not script.ends_with("_"+KEYS[i]+"Painting"):continue
		var portrait: Dictionary=g.save_data.get("contest_paintings",{}).get(str(i),{})
		if portrait.is_empty():g._dialog(["%s展位的画框还是空的。" % Contest.CATEGORIES[i]])
		else:show_painting(g,portrait,Contest.CATEGORIES[i])
		return true
	return false

static func show_painting(g, entry: Dictionary, caption: String) -> void:
	var curtain:=ColorRect.new()
	curtain.color=Color("#332b29")
	g.menu_layer.add_child(curtain)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.panel_open+=1
	g._set_hud_visible(false)
	var frame:=ColorRect.new()
	frame.color=Color("#ead6a5")
	curtain.add_child(frame)
	frame.position=Vector2(118,18)
	frame.size=Vector2(244,205)
	var art:=TextureRect.new()
	frame.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	art.texture=Art.battle_texture(entry.species,entry.form,entry.shiny,false)
	var exit_button:=Button.new()
	exit_button.text="%s　·　%s　　返回" % [caption,entry.name]
	exit_button.position=Vector2(74,244)
	exit_button.size=Vector2(332,44)
	curtain.add_child(exit_button)
	var close:=func():
		g.panel_open-=1
		g._set_hud_visible(g.panel_open==0)
		curtain.queue_free()
	exit_button.pressed.connect(close,CONNECT_ONE_SHOT)
	curtain.set_meta("choice_back",close)
