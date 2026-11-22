extends RefCounted
const PREFIX := "johto_ruins_of_alph_"
const TYPES := {"kabuto":["化石盔","ABCDEFGHIJK","ESCAPE"],"omanyte":["菊石兽","LMNOPQR","WATER"],"aerodactyl":["化石翼龙","STUVW","LIGHT"],"ho_oh":["凤王","XYZ","HO-OH"]}
const HALL := PREFIX+"inner_chamber"

static func chamber(map: String) -> String:
	if map.begins_with(PREFIX) and map.ends_with("_chamber"):
		var key=map.trim_prefix(PREFIX).trim_suffix("_chamber")
		if TYPES.has(key): return key
	return ""

static func letters(flags: Dictionary) -> String:
	var alphabet:=""
	for k in TYPES:
		if flags.get("js_puzzle_"+k,false): alphabet+=TYPES[k][1]
	return alphabet

static func open_wall(g,key: String):
	g._flags()["js_wall_"+key]=true
	g._persist()
	g._dialog(["石墙发出轰鸣声，尽头的秘室可以进去了。"])

static func automatic_walls(g):
	var key:=chamber(g.world.map_data.id)
	if key.is_empty() or g._flags().get("js_wall_"+key,false):return
	var party: Array=g.save_data.get("party",[]).filter(func(n):return n is Dictionary and not n.is_empty())
	if key=="omanyte" and (g._bag_count("水之石")>0 or party.any(func(m):return m.get("held","")=="WATER_STONE")): open_wall(g,key)
	elif key=="ho_oh" and not party.is_empty() and int(party[0].species_id)==250: open_wall(g,key)

static func use_rope(g,item: String) -> bool:
	if item!="离洞绳" or chamber(g.world.map_data.id)!="kabuto" or g._flags().get("js_wall_kabuto",false):return false
	g._consume_item(item)
	g._flags().js_wall_kabuto=true
	var outside: Dictionary={}
	for w in g.world.map_data.warps:
		if w.to.map==PREFIX+"outside":outside=w.to;break
	if not outside.is_empty(): g._do_warp(outside)
	g._persist()
	g._dialog(["离洞绳把你带回了遗迹外。刚才的石室里传来一阵震动。"])
	return true

static func flash(g) -> bool:
	if chamber(g.world.map_data.id)!="aerodactyl" or g._flags().get("js_wall_aerodactyl",false):return false
	open_wall(g,"aerodactyl")
	return true

static func passage(g,to: Dictionary) -> String:
	var key:=chamber(g.world.map_data.id)
	if not key.is_empty() and to.get("map","")==PREFIX+key+"_item_room" and not g._flags().get("js_wall_"+key,false):
		return "石墙上的文字是「%s」。"%TYPES[key][2]
	return ""

static func interact(g) -> bool:
	var key:=chamber(g.world.map_data.id)
	if key.is_empty():return false
	var tile: Vector2i=g.world.player_pos+g.world._dir_vec()
	if tile!=Vector2i(6,6):return false
	if g._flags().get("js_puzzle_"+key,false):
		g._dialog(["石板上刻着%s的姿态。"%TYPES[key][0]])
		return true
	var ui=preload("res://scenes/crystal_puzzle.gd").new()
	g.menu_layer.add_child(ui)
	g.panel_open+=1
	g.held_dir=""
	g._set_hud_visible(false)
	ui.setup(key,TYPES[key][0],g.save_data.get("js_puzzles",{}).get(key,[]))
	ui.finished.connect(func(solved):
		g.panel_open=maxi(0,g.panel_open-1)
		var board: Dictionary=g.save_data.get_or_add("js_puzzles",{})
		if solved:
			board.erase(key)
			g._flags()["js_puzzle_"+key]=true
		else:board[key]=ui.order.duplicate()
		ui.queue_free()
		g._set_hud_visible(g.panel_open==0)
		if solved:
			var room: Dictionary=g.get_node("/root/Data").load_map("johto",HALL)
			g._do_warp({"region":"johto","map":HALL,"hgss":true,"at":room.spawn})
			g._dialog(["脚下的石板打开了。新的未知图腾出现在遗迹里！"])
		g._persist(),CONNECT_ONE_SHOT)
	return true

static func caught_letters(g) -> Array:
	var catalog: Dictionary=g.save_data.get("dex_variants",{})
	var found: Array=[]
	for k in catalog:
		var fields:=str(k).split("|")
		if fields.size()<4 or fields[0]!="201" or int(catalog[k])<2:continue
		var form:=str(fields[1]).trim_prefix("UNOWN_")
		if form=="":form="A"
		if form.length()==1 and form>="A" and form<="Z" and form not in found:found.append(form)
	return found

static func research(g):
	var found:=caught_letters(g)
	if found.size()>=3 and not g._flags().get("js_unown_dex",false):
		g._flags().js_unown_dex=true
		g._persist()
		g._dialog(["你已经收服了三种不同样子的未知图腾！我把字母记录功能装进了你的图鉴。"],"遗迹研究员")
	elif g._flags().get("js_unown_dex",false):
		found.sort()
		g._dialog(["已记录 %d / 26 个字母。\n%s"%[found.size()," ".join(found)]],"遗迹研究员")
	else:g._dialog(["先试试遗迹中的石板，再带着三种不同的未知图腾来找我。"],"遗迹研究员")
