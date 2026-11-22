extends RefCounted

# The Crystal event scripts run on the corresponding counters and doorway of the native map.
const ANCHORS := {
	"bargain":{"at":[10,17],"facing":"left","sprite":"SPRITE_GSOLDMAN1"},
	"herbal":{"at":[10,28],"facing":"left","sprite":"SPRITE_GSOLDWOMAN1"},
	"older":{"at":[10,21],"facing":"left","sprite":"SPRITE_GSMAN3"},
	"younger":{"at":[10,22],"facing":"left","sprite":"SPRITE_GSMAN2"},
	"cal_desk":{"at":[5,4],"facing":"right","sprite":"SPRITE_GSWOMAN6"},
	"cal":{"at":[8,11],"facing":"left"},
}
# Discount price and normal Poké Mart resale price, from bargain_shop.asm and attributes.asm.
const BARGAINS := {"金珠":[4500,5000],"珍珠":[650,700],"大珍珠":[3500,3750],"星星沙子":[900,1000],"星星碎片":[4600,4900]}
const HERBS := {"元气粉":500,"元气根":800,"万能粉":450,"复活草":2800}
# CAL3 uses the normal trainer loader and each species' four most recent Crystal level-up moves.
const CAL_TEAM := [
	{"level":50,"species":154,"moves":[77,235,34,113]},
	{"level":50,"species":157,"moves":[52,98,172,129]},
	{"level":50,"species":160,"moves":[44,184,163,103]},
]
const GATE:=Vector2i(7,4)
const EXIT:=Vector2i(8,4)
const ARENA:=Vector2i(7,11)

static func turn_back(g):
	if g.world.player_pos==GATE:
		g.world.warp_to(EXIT)
		g.world.facing="left"

static func walk(g,from:Vector2i,path:String):
	g.world.warp_to(from)
	g.panel_open+=1
	g._escort_active=true
	g.held_dir=""
	g.run_held=false
	await g.world.play_actor_paths("js_house_cal","",path)
	g.panel_open-=1
	g._escort_active=false

static func cal(g,day:Dictionary):
	var date:=preload("res://core/crystal_phone.gd").current_day(day)
	if g._flags().get("js_cal_day",-1)==date:
		turn_back(g)
		g._dialog(["你今天已经参加过练习赛了。明天再来吧。"],"训练大厅接待员")
		return
	var leave:=func(): turn_back(g)
	g._pick("今天的对手是卡尔。每天可以挑战一次。",["接受挑战","改天再来"],func(i):
		if i!=0:
			leave.call()
			return
		g._flags().js_cal_day=date
		g._persist()
		if g.world.player_pos==GATE:await walk(g,GATE,"DDDDDDD")
		else:g.world.warp_to(ARENA)
		g.world.facing="right"
		g._start_battle({"name":"卡尔","battle":{"team":CAL_TEAM,"prize":5000}},func(result):
			if result=="b" and g._party_fainted():
				g._blackout()
				return
			await walk(g,ARENA,"UUUUUUUR")
			g.world.facing="left"
			g._persist())
	,leave)

static func store(g,key:String,day:Dictionary):
	var date:=preload("res://core/crystal_phone.gd").current_day(day)
	if key=="bargain":
		if day.weekday!=1 or day.hour<4 or day.hour>=10 or g._flags().get("js_bargain_day",-1)==date:
			g._dialog(["今天打烊了。星期一早上再来看看。"],"廉价店老板")
			return
	elif day.weekday not in [0,6]:
		g._dialog(["星期六和星期日，我会来这里卖草药。"],"草药婆婆")
		return
	shelves(g,key,date,[])

static func shelves(g,key:String,date:int,bought:Array):
	var bargain:=key=="bargain"
	var names:Array=[]
	var choices:Array=[]
	for item in (BARGAINS if bargain else HERBS):
		if item in bought:continue
		names.append(item)
		var price:int=BARGAINS[item][0] if bargain else HERBS[item]
		choices.append("%s　¥%d"%[item,price])
	if choices.is_empty():
		g._dialog(["今天带来的东西卖光啦，下周再来！"],"廉价店老板")
		return
	g._pick("%s　持有 ¥%d"%["每样只有一件，离柜结束本次采购" if bargain else "草药味苦，会降低亲密度",g.save_data.money],choices,func(i):
		var item:String=names[i]
		var price:int=BARGAINS[item][0] if bargain else HERBS[item]
		if g.save_data.money<price:g._show_toast("钱不够")
		else:
			g.save_data.money-=price
			g._give_item(item,1,"other" if bargain else "heal")
			if bargain:
				bought.append(item)
				# Buying anything closes the business for the day when this shopping session ends.
				g._flags().js_bargain_day=date
			g._persist()
			g._show_toast("买到了%s。"%item)
		shelves(g,key,date,bought))

static func counter(g):
	g._pick("满金百货二楼",["购买补给","卖贵重物品"],func(i):
		if i==0:g._open_shop()
		else:resell(g))

static func resell(g):
	var names:Array=[]
	var choices:Array=[]
	for item in BARGAINS:
		var count:int=g._bag_count(item)
		if count<=0:continue
		names.append(item)
		choices.append("%s ×%d　每件 ¥%d"%[item,count,BARGAINS[item][1]])
	if names.is_empty():
		g._dialog(["我们收购金珠、珍珠、大珍珠、星星沙子和星星碎片。"],"百货店员")
		return
	g._pick("出售一件贵重物品",choices,func(i):
		var item:String=names[i]
		if g._bag_count(item)>0:
			g._consume_item(item)
			g.save_data.money+=int(BARGAINS[item][1])
			g._persist()
			g._show_toast("卖出了%s。"%item)
		resell(g))
