extends RefCounted
## Kurt's seven Apricorns grow once per local date. A whole batch is ready the next day.
const BALLS := {"红球果":"等级球","蓝球果":"诱饵球","黄球果":"月亮球","绿球果":"友友球","白球果":"速度球","黑球果":"沉重球","粉球果":"甜蜜球"}
const TREES := {
	"johto_azalea_town":{"4,1":"白球果"},
	"johto_route_37":{"6,2":"红球果","8,2":"蓝球果","7,3":"黑球果"},
	"johto_route_42":{"13,8":"粉球果","14,8":"绿球果","13,7":"黄球果"}
}
const FLEE := [81,88,114,122,133,137,147,148,176,197,201,209,214,104,144,145,146,195,225,216,231,243,244]
static var weights := {}

static func roster(mid: String, rows: Array) -> Array:
	var trees: Dictionary = TREES.get(mid,{})
	if trees.is_empty(): return rows
	var updated := rows.duplicate(true)
	for loc: String in trees:
		var found := false
		for row in updated:
			if "%d,%d"%row.at==loc:
				row.merge({"name":"球果树","apricorn":trees[loc]},true)
				found=true
				break
		if not found:
			var xy := loc.split(",")
			updated.append({"at":[int(xy[0]),int(xy[1])],"name":"球果树","apricorn":trees[loc],"field_art":"cr_apricorn_tree"})
	return updated

static func talk(g, npc: Dictionary) -> bool:
	var today := Time.get_date_string_from_system()
	if npc.has("apricorn"):
		var fruit: String = npc.apricorn
		var harvest: Dictionary = g.save_data.get("j_apricorns",{})
		if harvest.get(fruit,"")==today:
			g._dialog(["今天的球果已经摘过了，明天再来看看。"],npc.name)
		else:
			harvest[fruit]=today
			g.save_data.j_apricorns=harvest
			g._give_item(fruit,1,"other")
			g._persist()
			g._dialog(["摘到了%s！桧皮镇的钢铁能用它做精灵球。" % fruit],npc.name)
		return true
	if npc.get("role","")!="j_kurt_back": return false
	var order: Dictionary = g.save_data.get("j_apricorn_order",{})
	if not order.is_empty():
		if today==order.date: g._dialog(["我正在加工球果，明天再来拿吧。"],"钢铁")
		else:
			g._give_item(BALLS[order.fruit],int(order.count),"ball")
			g.save_data.erase("j_apricorn_order")
			g._persist()
			g._dialog(["做好了！%s × %d，收好。" % [BALLS[order.fruit],order.count]],"钢铁")
		return true
	var choices: Array=BALLS.keys().filter(func(fruit):return g._bag_count(fruit)>0)
	if choices.is_empty():
		g._dialog(["带球果来吧！我家旁边的树上就结着白球果。"],"钢铁")
		return true
	g._pick("用哪种球果制球？",choices+["下次再来"],func(i):
		if i<0 or i>=choices.size(): return
		var fruit: String=choices[i]
		var count: int=g._bag_count(fruit)
		var amounts := ["交给他 1 个"]
		if count>1: amounts.append("全部交给他（%d 个）"%count)
		g._pick("%s → %s" % [fruit,BALLS[fruit]],amounts,func(j):
			var n := count if j==1 else 1
			for k in n: g._consume_item(fruit)
			g.save_data.j_apricorn_order={"fruit":fruit,"count":n,"date":today}
			g._persist()
			g._dialog(["我收下了。明天来拿做好的%s吧！" % BALLS[fruit]],"钢铁")))
	return true

static func adjusted_rate(ball: String, player: Dictionary, target: Dictionary, sp: Dictionary, base: float, fishing: bool) -> float:
	var sid := int(target.species_id)
	match ball:
		"等级球":
			var lead := int(player.level)
			var wild := int(target.level)
			if lead>4*wild: return base*8
			if lead>2*wild: return base*4
			if lead>wild: return base*2
		"诱饵球":
			if fishing: return base*3
		"速度球":
			if sid in FLEE: return base*4
		"月亮球":
			if sp.get("evolves",[]).any(func(e):return str(e.get("item","")).contains("MOON_STONE")): return base*4
		"甜蜜球":
			if int(player.species_id)==sid and player.get("sex","") in ["male","female"] and target.get("sex","") in ["male","female"] and player.sex!=target.sex: return base*8
		"沉重球":
			if weights.is_empty(): weights=JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/johto/weights.json"))
			if weights.has(str(sid)):
				var kg := float(weights[str(sid)])
				var extra := -20 if kg<102.4 else (0 if kg<204.8 else (20 if kg<307.2 else (30 if kg<409.6 else 40)))
				return clampf(base+extra,1,255)
	return base
