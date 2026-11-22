extends RefCounted

const TEXT := {"SMALL":"小型","POKEMON":"宝可梦","HEAVY":"厚重","RAGGED":"粗制","COMFORT":"舒适","BRICK":"砖制","CAMP":"露营","HARD":"硬质"}
const GIFT_MACHINES := {
	"Route114_FossilManiacsHouse_EventScript_FossilManiacsBrother":28,"SlateportCity_BattleTentLobby_EventScript_TormentGiver":41,
	"VerdanturfTown_BattleTentLobby_EventScript_AttractGiver":45,"Route104_EventScript_Boy2":9,"DewfordTown_Hall_EventScript_SludgeBombMan":36,
	"SSTidalRooms_EventScript_SnatchGiver":49,"Route114_EventScript_RoarGentleman":5,"SootopolisCity_House1_EventScript_BrickBreakBlackBelt":31,
	"LilycoveCity_House2_EventScript_FatMan":44,"FortreeCity_House2_EventScript_HiddenPowerGiver":10}
const TRADE := {
	"RustboroCity_House1_EventScript_Trader":[280,273,"DOTS","KOBE","CHESTO_BERRY"],
	"FortreeCity_House1_EventScript_Trader":[313,311,"PLUSES","ROMAN","WOOD_MAIL"],
	"PacifidlogTown_House3_EventScript_Trader":[371,116,"SEASOR","SKYLAR","WAVE_MAIL"],
	"BattleFrontier_Lounge6_EventScript_Trader":[300,52,"MEOWOW","ISIS","RETRO_MAIL"]}

const NAMES := {
	"RED_PLANT":"红色盆栽","TROPICAL_PLANT":"热带盆栽","PRETTY_FLOWERS":"漂亮的花","COLORFUL_PLANT":"彩色盆栽","BIG_PLANT":"大盆栽","GORGEOUS_PLANT":"华丽盆栽",
	"RED_BRICK":"红砖","YELLOW_BRICK":"黄砖","BLUE_BRICK":"蓝砖","RED_BALLOON":"红气球","BLUE_BALLOON":"蓝气球","YELLOW_BALLOON":"黄气球","RED_TENT":"红色帐篷","BLUE_TENT":"蓝色帐篷",
	"SOLID_BOARD":"结实的木板","SLIDE":"滑梯","FENCE_LENGTH":"竖栅栏","FENCE_WIDTH":"横栅栏","TIRE":"轮胎","STAND":"讲台","MUD_BALL":"泥土球","BREAKABLE_DOOR":"可破坏的门","SAND_ORNAMENT":"沙雕",
	"SILVER_SHIELD":"银色盾牌","GOLD_SHIELD":"金色盾牌","GLASS_ORNAMENT":"玻璃摆饰","TV":"电视","ROUND_TV":"圆形电视","CUTE_TV":"可爱电视"}
const ADJECTIVES := {"PRETTY":"漂亮","GLITTER":"闪亮","JUMP":"跳跃","SPIN":"旋转","C_LOW_NOTE":"低音哆","D_NOTE":"来音","E_NOTE":"咪音","F_NOTE":"发音","G_NOTE":"嗦音","A_NOTE":"拉音","B_NOTE":"西音","C_HIGH_NOTE":"高音哆","SURF":"冲浪","THUNDER":"打雷","FIRE_BLAST":"大字爆炎","POWDER_SNOW":"细雪","ATTRACT":"迷人","FISSURE":"地裂","SPIKES":"撒菱","BALL":"精灵球","GREEN":"绿色","RED":"红色","BLUE":"蓝色","CUTE":"可爱","PIKA":"皮卡丘","LONG":"长条","SEA":"海洋","SKY":"天空","KISS":"亲吻","ROUND":"圆形","ZIGZAG":"锯齿","DIAMOND":"菱形","GRASS":"青草","FIRE":"火焰","WATER":"水滴"}

static func title(item: String) -> String:
	if NAMES.has(item):return NAMES[item]
	var suffix:=item.get_slice("_",item.count("_"))
	var stem:=item.trim_suffix("_"+suffix)
	if suffix=="DOLL":
		var data=Engine.get_main_loop().root.get_node("Data")
		for row in data.species.values():
			if str(row.get("key",""))==stem:return str(row.name)+"玩偶"
	return str(TEXT.get(stem,ADJECTIVES.get(stem,stem)))+str({"DESK":"桌子","CHAIR":"椅子","MAT":"地垫","POSTER":"海报","CUSHION":"靠垫"}.get(suffix,suffix))

static func add_decoration(g, source_id: String) -> bool:
	var key:=source_id.trim_prefix("DECOR_")
	var catalog: Dictionary=g.get_node("/root/Data").load_map("hoenn","em_secret_base_red_cave1").mechanisms.base.furniture
	if not catalog.has(key):return false
	var owned: Dictionary=g._flags().get_or_add("h_decorations",{})
	owned[key]=int(owned.get(key,0))+1
	g._persist()
	return true

static var _data: Dictionary
static func data() -> Dictionary:
	if _data.is_empty():_data=JSON.parse_string(FileAccess.get_file_as_string("res://content/hoenn_native/side.json"))
	return _data

static func sale_today() -> bool:
	var date:=Time.get_date_dict_from_system()
	return int(date.weekday) in [0,6]

static func talk(g, actor: Dictionary) -> bool:
	var script:=str(actor.get("source_script",""))
	if GIFT_MACHINES.has(script):
		var flag: String="h_gift_"+script
		if g._flags().get(flag,false):g._dialog(["之前给你的招式学习器已经送出。"]);return true
		if int(GIFT_MACHINES[script])==10:guess(g,flag,0)
		else:give_machine(g,flag,GIFT_MACHINES[script])
		return true
	if script=="Route111_EventScript_SecretPowerMan":
		if not g._flags().get("h_secret_power",false):
			g._flags().h_secret_power=true
			g._give_item("招式学习器 43",1,"tm")
			g._persist()
			g._dialog(["这是秘密之力的招式学习器。让伙伴学会后，调查岩壁的凹洞、大树或灌木丛，就能建自己的秘密基地。"],"训练家")
		else:g._dialog(["在有凹痕的地方用秘密之力，就能发现秘密基地。"])
		return true
	if TRADE.has(script):
		var trade: Array=TRADE[script]
		load("res://core/frlg_sidequests.gd").trade(g,["trade","交换训练家",trade[0],trade[1],trade[2],trade[3],trade[4]],"h_trade_"+script)
		return true
	if script=="MauvilleCity_GameCorner_EventScript_PrizeCornerDolls":
		if g._bag_count("代币盒")==0:g._dialog(["请先准备代币盒。"]);return true
		var goods:=["TREECKO_DOLL","TORCHIC_DOLL","MUDKIP_DOLL"]
		var options: Array=goods.map(func(id):return title(id)+"　1000 枚")
		options.append("返回")
		g._pick("用代币交换玩偶",options,func(i):
			if i>=goods.size():return
			var n:=int(g._flags().get("h_coins",0))
			if n<1000:g._dialog(["需要1000枚代币。"]);return
			g._flags().h_coins=n-1000
			add_decoration(g,goods[i])
			g._dialog(["玩偶已送入秘密基地电脑。"]))
		return true
	if script=="FallarborTown_PokemonCenter_1F_EventScript_Lanette":
		g._flags().h_lanette_met=true
		g.world.refresh_story_actors(g._flags())
		g._persist()
		g._dialog(["我是负责宝可梦寄放系统的真由美。想聊天的话，来114号道路我家吧。"],"真由美")
		return true
	if script in ["Route114_LanettesHouse_EventScript_Lanette","SootopolisCity_House6_EventScript_Woman"]:
		var flag: String="h_decoration_"+script
		var gift: String="LOTAD_DOLL" if script.contains("Lanette") else "WAILMER_DOLL"
		if g._flags().get(flag,false):g._dialog(["那个玩偶摆在你的基地里了吗？"])
		else:g._pick("收下"+title(gift)+"？",["收下","以后再来"],func(i):
			if i==0:
				g._flags()[flag]=true
				add_decoration(g,gift)
				g._dialog(["已存入秘密基地电脑。"]))
		return true
	if data().decor_shops.has(script):
		if script=="SlateportCity_EventScript_DecorClerk" and not g._flags().get("h_secret_power",false):g._dialog(["等你学习了秘密之力再来。"]);return true
		var room: Dictionary=g.get_node("/root/Data").load_map("hoenn","em_secret_base_red_cave1")
		var stock: Dictionary=room.mechanisms.base.furniture
		var keys: Array=data().decor_shops[script]
		var labels: Array=keys.map(func(id):return "%s　₽%d"%[title(id),stock[id].price])
		labels.append("离开")
		g._pick("装饰品",labels,func(i):
			if i>=keys.size():return
			var id: String=keys[i]
			var price:=int(stock[id].price)
			if int(g.save_data.get("money",0))<price:g._dialog(["钱不够。"]);return
			g.save_data.money-=price
			add_decoration(g,id)
			g._persist()
			g._dialog(["收好了！在秘密基地的电脑选择摆放家具。"]))
		return true
	return false

static func go(g, map: String, at: Array) -> void:
	preload("res://core/emerald_legends.gd").warp(g,map,at)

static func action(g, o: Dictionary) -> bool:
	var sc:=str(o.get("source_script",""))
	var flags: Dictionary=g._flags()
	if sc=="EmeraldBaseSite":
		var room: Dictionary=g.get_node("/root/Data").load_map("hoenn",o.room)
		var base: Dictionary=room.mechanisms.base
		if flags.get("h_base_site","")==o.secret_site:
			go(g,o.room,[base.exit[0],base.exit[1]-1])
		elif not g._party_has_move("SECRET_POWER"):g._dialog(["这个位置可以开辟秘密基地。队伍中需要有学会秘密之力的伙伴。"])
		else:
			g._pick("搬到这里？原基地的摆设会收回。" if flags.has("h_base_site") else "在这里用秘密之力，开辟自己的基地？",["使用秘密之力","离开"],func(i):
				if i!=0:return
				flags.h_base_site=o.secret_site
				flags.h_base_back={"map":g.world.map_data.id,"at":[g.world.player_pos.x,g.world.player_pos.y]}
				flags.h_base_furniture=[]
				go(g,o.room,base.pc_at))
		return true
	if sc=="EmeraldBaseExit":return leave(g)
	if sc=="EmeraldBasePC":
		g._pick("秘密基地电脑",["摆放家具","收起家具","离开电脑"],func(i):
			if i==0:decorate(g)
			elif i==1:put_away(g))
		return true
	return false

static func leave(g) -> bool:
	var back: Dictionary=g._flags().get("h_base_back",{})
	if back.is_empty():return false
	go(g,back.map,back.at)
	return true

static func decorate(g) -> void:
	var catalog: Dictionary=g.world.map_data.mechanisms.base.furniture
	var placed: Array=g._flags().get("h_base_furniture",[])
	if placed.size()>=16:g._dialog(["基地最多可摆放16件家具。"]);return
	var keys: Array=[]
	for id in catalog:
		var copies:=0
		for ent in placed:
			if ent.id==id:copies+=1
		if int(g._flags().get("h_decorations",{}).get(id,0))+g._bag_count(title(id))>copies:keys.append(id)
	if keys.is_empty():g._dialog(["没有闲置的家具。茵郁市装饰店出售桌椅。"]);return
	var labels: Array=keys.map(func(id):return title(id))
	labels.append("返回")
	g._pick("选择家具",labels,func(i):
		if i<keys.size():
			g.world.hoenn_local.base_place=keys[i]
			g._dialog(["面向想摆放的位置按 A。返回电脑可取消。"]))

static func put_away(g) -> void:
	var placed: Array=g._flags().get("h_base_furniture",[])
	if placed.is_empty():g._dialog(["基地里还没有摆放家具。"]);return
	var labels: Array=placed.map(func(e):return "%s (%d,%d)"%[title(e.id),e.at[0],e.at[1]])
	labels.append("返回")
	g._pick("收起家具",labels,func(i):
		if i>=placed.size():return
		var selected: Dictionary=placed[i]
		var d: Dictionary=g.world.map_data.mechanisms.base.furniture[selected.id]
		if not d.has("gfx"):
			var rect:=Rect2i(selected.at[0],selected.at[1],d.size[0],d.size[1])
			for ent in placed:
				var above: Dictionary=g.world.map_data.mechanisms.base.furniture[ent.id]
				if above.has("gfx") and rect.intersects(Rect2i(ent.at[0],ent.at[1],above.size[0],above.size[1])):
					g._dialog(["请先取下上面的玩偶或靠垫。"])
					return
		g.world.hoenn_local.get("decor_frames",{}).erase("%s/%d/%d"%[selected.id,selected.at[0],selected.at[1]])
		placed.remove_at(i)
		g.world._rebuild()
		g._persist())

static func place(g) -> bool:
	var w=g.world
	var item:=str(w.hoenn_local.get("base_place",""))
	if item=="":return false
	var base: Dictionary=w.map_data.mechanisms.base
	var at: Vector2i=w.player_pos+w._dir_vec()
	var obj: Dictionary=w.object_at(at)
	if obj.get("source_script","")=="EmeraldBasePC":
		w.hoenn_local.erase("base_place")
		return false
	var shape: Array=base.furniture[item].size
	var top:=Vector2i(at.x,at.y-shape[1]+1)
	var placed: Array=g._flags().get_or_add("h_base_furniture",[])
	var d: Dictionary=base.furniture[item]
	var rule: Dictionary=base.placement
	for i in int(shape[0]):
		for j in int(shape[1]):
			var p:=top+Vector2i(i,j)
			if p.x<0 or p.y<0 or p.x>=w.tile_size.x or p.y>=w.tile_size.y or p==w.player_pos or [p.x,p.y] in [base.pc_at,base.exit,[base.exit[0],base.exit[1]-1]]:
				g._show_toast("请给人物、电脑和门口留出空间。")
				return true
			var surface:=int(w.map_data.physics.behavior[p.y][p.x])
			var occupied:=false
			for entry in placed:
				var under: Dictionary=base.furniture[entry.id]
				var rect:=Rect2i(entry.at[0],entry.at[1],under.size[0],under.size[1])
				if rect.has_point(p):
					occupied=true
					if under.has("surface"):surface=int(under.surface[(p.y-rect.position.y)*int(under.size[0])+p.x-rect.position.x])
					else:surface=-1
			var valid: bool
			match d.permission:
				"NA_WALL":valid=not occupied and surface==int(rule.SECRET_BASE_NORTH_WALL)
				"SPRITE":valid=(j<shape[1]-1 or surface==int(rule.HOLDS_LARGE_DECORATION if int(shape[1])>1 else rule.HOLDS_SMALL_DECORATION))
				"BEHIND_FLOOR":valid=not occupied and (surface==0 or j==0 and surface==int(rule.SECRET_BASE_NORTH_WALL))
				_:valid=not occupied and (not w.blocked_by_terrain(p) and surface==0 or item=="SOLID_BOARD" and surface==int(rule.SECRET_BASE_HOLE))
			if not valid:
				g._show_toast("玩偶或靠垫需要大小合适的桌子或地垫。" if d.has("gfx") else ("请面向基地北侧的墙壁。" if d.permission=="NA_WALL" else "这个位置放不下这件家具。"))
				return true
	placed.append({"id":item,"at":[top.x,top.y]})
	w.hoenn_local.erase("base_place")
	w._rebuild()
	g._persist()
	return true

static func tiles(w, f: Dictionary) -> Array:
	var out: Array=[]
	var site:=str(f.get("h_base_site",""))
	if site=="" :return out
	for o in w.map_data.get("objects",[]):
		if o.get("secret_site","")==site:out.append(o.open_tile)
	var base: Dictionary=w.map_data.get("mechanisms",{}).get("base",{})
	if base.is_empty():return out
	for ent in f.get("h_base_furniture",[]):
		var d: Dictionary=base.furniture[ent.id]
		if not d.has("tiles"):continue
		var width:=int(d.size[0])
		var frames: Array=preload("res://core/hoenn_base_effects.gd").frame(w,ent,d.tiles)
		for i in frames.size():
			var t: Array=frames[i]
			out.append([ent.at[0]+i%width,ent.at[1]+floori(float(i)/width),t[0],t[1],int(d.permission!="PASS_FLOOR" and not (str(ent.id).ends_with("_TENT") and i==7))])
	return out

static func draw(layer: Node2D,w) -> void:
	var base: Dictionary=w.map_data.get("mechanisms",{}).get("base",{})
	if base.is_empty():return
	for ent in w.taken.get("h_base_furniture",[]):
		var d: Dictionary=base.furniture[ent.id]
		if not d.has("gfx"):continue
		var s:=Sprite2D.new()
		preload("res://core/hoenn_field.gd").draw(s,{"source_gfx":d.gfx},"down")
		if s.texture==null:
			s.free()
			continue
		s.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		s.position=Vector2(ent.at[0]*16+8,(ent.at[1]+d.size[1])*16-s.texture.get_height()*0.5)
		s.z_index=100+int(ent.at[1]+d.size[1]-1)*2
		layer.add_child(s)

static func give_machine(g,flag: String,number: int) -> void:
	var machine: String="招式学习器 %02d"%number
	g._give_item(machine,1,"tm")
	g._flags()[flag]=true
	g._persist()
	var move: int=g._tm_move_of(machine)
	g._dialog(["收下「%s」吧，它能教会伙伴%s。"%[machine,g.get_node("/root/Data").move_of(move).name]])

static func guess(g,flag: String,step: int) -> void:
	g._pick("硬币藏在哪只手里？（第%d次）"%(step+1),["右手","左手","离开"],func(i):
		if i>=2:return
		if i!=[0,0,1][step]:g._dialog(["猜错了。再来找我试试。"])
		elif step==2:give_machine(g,flag,10)
		else:guess(g,flag,step+1))
