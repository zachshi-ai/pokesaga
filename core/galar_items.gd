extends RefCounted
## Story items operate on the existing bag, party and field actions.
const SWIFT := "伽勒尔招式学习器40·高速星星"
const CARDS := {
	"丹帝的联盟卡":"丹帝　｜　冠军　｜　背号 1\n他的搭档是喷火龙。道馆挑战者要拿齐八枚徽章，才能和他争夺冠军。",
	"赫普的联盟卡":"赫普　｜　道馆挑战者　｜　背号 189\n小时候的搭档毛辫羊和新伙伴一起，陪他踏上追赶哥哥的旅途。",
	"亚洛的联盟卡":"亚洛　｜　草系馆主　｜　背号 831\n庆典之后，他总会回到草路镇去照看毛辫羊。"
}
const FLIGHTS := [
	["化朗镇","galar_postwick","g_home"],["木杆镇","galar_wedgehurst","g_leon_arrives"],
	["旷野地带车站","galar_wild_south","g_train"],["机擎市","galar_motostoke","g_leon_card"],
	["草路镇","galar_turffield","g_yamper"],["水舟镇","galar_hulbury","g_hulbury_rose"],
	["拳关市","galar_hammerlocke","g_hammer_rose"],["溯传镇","galar_stow","g_gym_4_ready"],
	["舞姿镇","galar_ballonlea","g_gym_5_ready"],["战竞镇","galar_circhester","g_gym_6_ready"],
	["尖钉镇","galar_spikemuth","g_badge_7"],["宫门市","galar_wyndon","g_wyndon_arrival"]]
const CAMPS := ["galar_1","galar_2","galar_3","galar_4","galar_wild_south","galar_wild_lake","galar_wild_north",
	"galar_5","galar_6","galar_7","galar_8","galar_9","galar_10","galar_lake_out"]

static func use(g,item_name: String) -> bool:
	if CARDS.has(item_name):g._dialog([CARDS[item_name]],item_name)
	elif item_name=="伽勒尔宝可梦图鉴":g._open_dex()
	elif item_name==SWIFT:_swift(g)
	elif item_name=="露营组合":_camp(g)
	elif item_name=="宝可梦盒":
		var mid:=str(g.world.map_data.get("id",""))
		if mid in ["galar_turffield_pitch","galar_turffield_mission"]:
			g._dialog(["道馆挑战进行中，走回大厅再打开宝可梦盒。"],item_name)
		else:g._open_pc(false)
	elif item_name=="飞翔出租车":_taxi(g)
	elif item_name=="伽勒尔离洞绳":_rope(g)
	elif item_name=="许愿星":g._dialog(["从夜空坠落的星形石头。把它带回二号道路的湖边，木兰博士知道该怎么使用。"],item_name)
	elif item_name=="推荐函":
		var lines:=["冠军丹帝亲笔推荐小悠参加道馆挑战。把它带到机擎竞技场的登记柜台。"]
		if g._flags().has("g_uniform_number"):lines.append("报名已经受理。你的球衣背号是 "+str(g._flags().g_uniform_number)+"。")
		g._dialog(lines,item_name)
	elif item_name=="极巨腕带":g._dialog(["木兰博士把许愿星嵌在腕带里。在草路竞技场与亚洛对战时，选择招式页的极巨化，就能激发伙伴的力量。"],item_name)
	else:return preload("res://core/galar_later.gd").use(g,item_name)
	return true

static func _camp(g) -> void:
	if g.world.map_data.get("id","") not in CAMPS:
		g._dialog(["这里搭不开帐篷。可以在伽勒尔的道路和旷野地带扎营。"],"露营组合")
		return
	var berry: Dictionary=g._first_berry_in_bag()
	var choices:=["看看伙伴","收起帐篷"]
	if not berry.is_empty():choices.push_front("用"+str(berry.name)+"煮咖喱")
	g._pick("营地",choices,func(i):
		if choices[i]=="看看伙伴":g._open_party()
		elif choices[i]!="收起帐篷":
			g._consume_item(berry.name)
			g._heal_party()
			g._dialog(["大家分着吃完了热咖喱，体力和招式次数都恢复了！"],"露营组合"))

static func _taxi(g) -> void:
	var mid:=str(g.world.map_data.get("id",""))
	if g.world.map_data.get("region","")!="galar" or mid in ["galar_mine","galar_mine2","galar_turffield_pitch","galar_turffield_mission"] or mid.ends_with("_room") or mid in ["galar_motostoke_stadium","galar_motostoke_inn","galar_player_home","galar_hop_home","galar_hop_upstairs"]:
		g._dialog(["请到伽勒尔的户外呼叫飞翔出租车。"],"飞翔出租车")
		return
	var places:=FLIGHTS.filter(func(row):return bool(g._flags().get(row[2],false)))
	if places.is_empty():return
	g._pick("飞翔出租车 · 要到哪里？",places.map(func(row):return row[0]),func(i):
		var m: Dictionary=g.get_node("/root/Data").load_map("galar",places[i][1])
		g._do_warp({"region":"galar","map":m.id,"at":m.spawn,"facing":"down"}))

static func _rope(g) -> void:
	var mid:=str(g.world.map_data.get("id",""))
	if mid not in ["galar_mine","galar_mine2"]:
		g._dialog(["在伽勒尔矿山内使用，可以回到入口。绳子能反复使用。"],"伽勒尔离洞绳")
		return
	var previous:=str(g._flags().get("g_mine_exit","galar_3"))
	var warps: Array=g.world.map_data.warps
	var dest: Dictionary=warps[0].to
	for w in warps:
		if w.to.map==previous:
			dest=w.to
			break
	g._do_warp(dest.duplicate(true))

static func swift_compatible(mon: Dictionary) -> bool:
	var book: Dictionary=load("res://core/galar_campaign.gd").data()
	return int(mon.get("species_id",0)) in book.swift_species and mon.get("form","") not in book.swift_excluded_forms

static func _swift(g) -> void:
	var names: Array=[]
	var slots: Array=[]
	for i in g.save_data.party.size():
		var mon: Dictionary=g.save_data.party[i]
		if swift_compatible(mon):
			names.append(str(mon.name))
			slots.append(i)
	if slots.is_empty():
		g._dialog(["队伍里还没有能学习高速星星的伙伴。"],SWIFT)
	else:
		g._pick("让谁学习高速星星？",names,func(i):g._tm_teach_one(129,int(slots[i]),"高速星星",true))
