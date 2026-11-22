extends RefCounted

const FR:=preload("res://core/frlg_sidequests.gd")
const Party:=preload("res://core/party.gd")
const Dex:=preload("res://core/dex_variants.gd")
const ZONES:=["","西北草地","东北草地","西南草地","东南草地","西北水域","东北水域","西南水域","东南水域"]
const PRIZES:=[["CHERI","CHESTO","PECHA","RAWST","ASPEAR","LEPPA","ORAN","PERSIM"],["FIGY","WIKI","MAGO","AGUAV","IAPAPA"],["RAZZ","BLUK","NANAB","WEPEAR","PINAP","LUM","SITRUS"],["POMEG","KELPSY","QUALOT","HONDEW","GREPA","TAMATO"]]
const GBA_FIELD_MOVES:=[15,19,57,70,148,249,127,291]

static func eligible(mon) -> bool:
	return mon is Dictionary and int(mon.get("species_id",0))>=1 and int(mon.get("species_id",0))<=386 and not mon.get("is_egg",false) and not mon.get("moves",[]).any(func(id):return int(id) in GBA_FIELD_MOVES)

static func talk(g,side,script: String) -> bool:
	match script:
		"PalParkLobby_RecordGuy":FR.say(g,"你的捕捉秀最高纪录是 %d 分。"%int(g.save_data.get("s_park_record",0)),"纪录员")
		"PalPark_Worker":retire(g,side)
		"PalParkLobby_Worker":
			if not g._flags().get("s_national_dex",false):FR.say(g,"持有全国图鉴以后再来报名吧。","伙伴公园")
			elif g.save_data.has("s_park_show"):
				var run: Dictionary=g.save_data.s_park_show
				if run.order.size()==6:finish_menu(g,side)
				else:
					g._pick("已有六只宝可梦在园内",["继续捕捉","取回六只并结束","返回"],func(i):
						if i==0:side.go(g,"PAL_PARK",[24,47])
						elif i==1:restore(g,side,false))
			else:
				g._pick("伙伴公园 · 捕捉秀",["从电脑选择六只","查看规则","返回"],func(i):
					if i==0:select(g,side,[])
					elif i==1:FR.say(g,"从共享电脑选六只关都、城都或丰缘的宝可梦。学会第三世代秘传招式的宝可梦和蛋不能参加。请在对应栖息地找回它们。公园球一定能捕获，完成后六只都回到电脑。","伙伴公园"))
		_:return false
	return true

static func select(g,side,chosen: Array,box_index: int=-1) -> void:
	var boxes: Array=g.save_data.get("boxes",[])
	var labels: Array=[]
	var slots: Array=[]
	var eligible_boxes: Array=[]
	var total:=0
	for b in boxes.size():
		if not boxes[b] is Dictionary:continue
		var mons: Array=boxes[b].get("mons",[])
		for s in mons.size():
			var mon=mons[s]
			if eligible(mon) and not [b,s] in chosen:
				total+=1
				if not eligible_boxes.has(b):eligible_boxes.append(b)
				if box_index>=0 and b!=box_index:continue
				slots.append([b,s])
				labels.append("箱 %d · %s　Lv.%d"%[b+1,mon.name,mon.level])
	if chosen.size()+total<6:
		FR.say(g,"电脑中只有 %d 只符合条件，请先存入足够的宝可梦。"%(chosen.size()+total),"伙伴公园")
		return
	if box_index<0 and eligible_boxes.size()>1:
		var names:=eligible_boxes.map(func(b):return str(boxes[b].get("name","箱子 %d"%(int(b)+1))))
		g._pick("选择电脑箱　还需 %d 只"%(6-chosen.size()),names+["取消报名"],func(i):
			if i<eligible_boxes.size():select(g,side,chosen,int(eligible_boxes[i])))
		return
	g._pick("挑选第 %d / 6 只"%[chosen.size()+1],labels+["取消报名"],func(i):
		if i>=slots.size():return
		var now:=chosen+[slots[i]]
		if now.size()<6:select(g,side,now)
		else:g._pick("将选中的六只暂时移入公园？",["开始捕捉秀","取消"],func(j):
			if j==0:start(g,side,now)))

static func start(g,side,slots: Array) -> void:
	if slots.size()!=6 or g.save_data.has("s_park_show") or not g._flags().get("s_national_dex",false):return
	var mons: Array=[]
	var checked: Array=[]
	for v in slots:
		if v in checked:return
		checked.append(v)
		var boxed=g.save_data.boxes[v[0]].mons[v[1]]
		if not eligible(boxed):return
		mons.append(boxed)
	for v in slots:g.save_data.boxes[v[0]].mons[v[1]]={}
	g.save_data.s_park_show={"mons":mons,"slots":slots,"order":[],"steps":g.rng.randi_range(5,14),"start":int(Time.get_unix_time_from_system())}
	g._persist()
	side.go(g,"PAL_PARK",[24,47])
	g._show_toast("收到六颗公园球。捕捉秀开始！")

static func area(g) -> int:
	var at: Vector2i=g.world.player_pos
	var quadrant:=int(at.x>=32)+2*int(at.y>=32)
	if g.world.is_water(at):return 5+quadrant
	if g.world.tile_at(at)==11:return 1+quadrant
	return 0

static func step(g,side) -> bool:
	var run: Dictionary=g.save_data.get("s_park_show",{})
	if run.is_empty():
		side.go(g,"PAL_PARK_LOBBY",[7,7])
		return true
	if run.order.size()==6:
		finish_menu(g,side)
		return true
	if g.world.player_pos.y==48 and g.world.player_pos.x in range(22,28):
		retire(g,side)
		return true
	run.steps=int(run.steps)-1
	if int(run.steps)>0:return true
	run.steps=g.rng.randi_range(5,14)
	var habitat:=area(g)
	var total:=20
	var candidates: Array=[]
	for i in run.mons.size():
		if run.order.has(i) or run.order.has(float(i)):continue
		var row: Array=side.data().pal_park[str(int(run.mons[i].species_id))]
		if int(row[0])==habitat:
			total+=int(row[1])
			candidates.append([i,total])
	var draw: int=g.rng.randi_range(0,total-1)
	if draw>=20:
		for c in candidates:
			if draw<int(c[1]):
				encounter(g,side,int(c[0]))
				break
	return true

static func encounter(g,side,i: int) -> void:
	var run: Dictionary=g.save_data.s_park_show
	var mon: Dictionary=run.mons[i]
	var ui:=preload("res://scenes/frlg_safari_ui.gd").new()
	ui.name="PalParkEncounter"
	g.menu_layer.add_child(ui)
	g.panel_open+=1
	g._set_hud_visible(false)
	ui.setup(mon,"公园球 ×%d　已找回 %d / 6"%[6-run.order.size(),run.order.size()],[["ball","投公园球"],["run","离开"]])
	ui.action_chosen.connect(func(action):
		if ui.is_queued_for_deletion():return
		ui.queue_free()
		g.panel_open=maxi(0,g.panel_open-1)
		g._set_hud_visible(g.panel_open==0)
		if action=="ball":
			run.order.append(i)
			g._persist()
			if run.order.size()==6:
				run.finished=int(Time.get_unix_time_from_system())
				side.go(g,"PAL_PARK_LOBBY",[7,7])
				g._persist()
				finish_menu(g,side)
			else:g._show_toast("找回了%s！剩余 %d 只。"%[mon.name,6-run.order.size()]))

static func retire(g,side) -> void:
	var run: Dictionary=g.save_data.get("s_park_show",{})
	if run.is_empty():return
	var hints: Array=[]
	for i in run.mons.size():
		if not run.order.has(i) and not run.order.has(float(i)):
			var row: Array=side.data().pal_park[str(int(run.mons[i].species_id))]
			hints.append("%s · %s"%[run.mons[i].name,ZONES[int(row[0])]])
	g._pick("已找回 %d / 6 只"%run.order.size(),["查看剩余栖息地","返回大厅","继续寻找"],func(i):
		if i==0:g._dialog(hints,"园区向导")
		elif i==1:side.go(g,"PAL_PARK_LOBBY",[7,7]))

static func score(side,run: Dictionary) -> Array:
	var points:=0
	var type_bonus:=0
	var prev: Array=[]
	var present: Array=[]
	for i in run.order:
		var row: Array=side.data().pal_park[str(int(run.mons[int(i)].species_id))]
		points+=int(row[2])
		var types: Array=row[3]
		if not prev.is_empty() and not types.any(func(t):return prev.has(t)):type_bonus+=200
		for t in types:
			if not present.has(t):present.append(t)
		prev=types
	var time:=maxi(0,(1000-maxi(0,int(run.get("finished",Time.get_unix_time_from_system()))-int(run.start)))*2)
	return [points,time,type_bonus+present.size()*50]

static func finish_menu(g,side) -> void:
	var run: Dictionary=g.save_data.s_park_show
	var scores:=score(side,run)
	g._pick("捕捉 %d · 时间 %d · 属性 %d"%scores,["将六只送回电脑","重新挑战"],func(i):
		if i==0:restore(g,side,true)
		else:
			run.order=[]
			run.start=int(Time.get_unix_time_from_system())
			run.erase("finished")
			run.steps=g.rng.randi_range(5,14)
			g._persist()
			side.go(g,"PAL_PARK",[24,47]))

static func restore(g,side,won: bool) -> void:
	var run: Dictionary=g.save_data.get("s_park_show",{})
	if run.is_empty():return
	# Plan all six placements in a private copy. A full PC leaves the show untouched.
	var boxes: Array=g.save_data.get("boxes",[]).duplicate(true)
	var displaced: Array=[]
	for i in run.mons.size():
		var pos: Array=run.slots[i]
		var b:=int(pos[0])
		var s:=int(pos[1])
		if b<boxes.size() and boxes[b] is Dictionary and s<boxes[b].get("mons",[]).size() and (boxes[b].mons[s]==null or boxes[b].mons[s].is_empty()):
			boxes[b].mons[s]=run.mons[i]
		else:displaced.append(run.mons[i])
	for mon in displaced:
		if not Party.store_in_boxes(boxes,mon):
			FR.say(g,"电脑空间不足。六只仍在公园托管，请腾出位置后回来。","伙伴公园")
			return
	g.save_data.boxes=boxes
	g.save_data.erase("s_park_show")
	var msg:="六只宝可梦已回到电脑。"
	if won:
		var scores:=score(side,run)
		var total:=int(scores[0])+int(scores[1])+int(scores[2])
		var tier:=int(total>=3000)+int(total>=3300)+int(total>=3500)
		var gift:=str(PRIZES[tier][g.rng.randi_range(0,PRIZES[tier].size()-1)])+"_BERRY"
		g.save_data.s_park_record=maxi(int(g.save_data.get("s_park_record",0)),total)
		for mon in run.mons:Dex.record(g.save_data,mon,true)
		side.give(g,gift)
		msg+=" 捕捉秀得分 %d，获得%s。"%[total,side.item_name(gift)]
	g._persist()
	FR.say(g,msg,"伙伴公园")
