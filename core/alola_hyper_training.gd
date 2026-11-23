extends RefCounted

const Party := preload("res://core/party.gd")
const FR := preload("res://core/frlg_sidequests.gd")
const SILVER := "银色王冠"
const GOLD := "金色王冠"
const WHO := "极限特训爷爷"

static func missing(mon: Dictionary) -> Array:
	var result: Array=[]
	if int(mon.get("level",0))!=100 or mon.get("is_egg",false):return result
	for stat in Party.STAT_LABELS:
		if Party.effective_iv(mon,stat)<31:result.append(stat)
	return result

static func open(g) -> void:
	if not g._flags().get("a_credits",false):
		g._dialog(["成为冠军以后，带等级 100 的伙伴来找我吧。"],WHO);return
	FR.pick_party(g,"让哪位伙伴参加极限特训？",func(mon):return not mon.get("is_egg",false),func(slot):
		var mon: Dictionary=g.save_data.party[slot]
		if int(mon.level)!=100:
			g._dialog(["%s目前是 Lv.%d。升到 Lv.100 时，就能参加极限特训了。"%[mon.name,mon.level]],WHO);return
		var stats:=missing(mon)
		if stats.is_empty():
			g._dialog(["%s的六项能力都已经达到个体极限了。"%mon.name],WHO);return
		g._pick("%s的极限特训"%mon.name,["银色王冠　×%d"%g._bag_count(SILVER),"金色王冠　×%d"%g._bag_count(GOLD),"离开"],func(i):
			if i>1:return
			var cap:=SILVER if i==0 else GOLD
			if g._bag_count(cap)<1:
				g._dialog(["背包里还没有%s。伙伴携带的王冠可在队伍页取下。"%cap],WHO);return
			if cap==GOLD:confirm(g,slot,mon,cap,"");return
			var labels: Array=[]
			for stat in stats:
				labels.append("%s　%d → 31"%[Party.STAT_LABELS[stat],Party.effective_iv(mon,stat)])
			g._pick("想特训哪项能力？",labels,func(j):confirm(g,slot,mon,cap,stats[j]))))

static func confirm(g,slot: int,mon: Dictionary,cap: String,stat: String) -> void:
	var scope: String=Party.STAT_LABELS.get(stat,"所有尚有潜力的能力")
	g._pick("给%s使用一枚%s，特训%s？"%[mon.name,cap,scope],["开始特训","暂时不用"],func(i):
		if i!=0:return
		if slot>=g.save_data.party.size() or not is_same(g.save_data.party[slot],mon) or not train(g,mon,cap,stat):
			g._dialog(["训练条件已改变，请重新选择。"],WHO);return
		g._dialog(["特训完成！%s的%s在对战中已发挥出最高潜力。"%[mon.name,scope]],WHO))

static func train(g,mon: Dictionary,cap: String,stat: String) -> bool:
	if not g._flags().get("a_credits",false) or cap not in [SILVER,GOLD] or g._bag_count(cap)<1:return false
	var stats:=missing(mon)
	if stats.is_empty() or (cap==SILVER and stat not in stats) or (cap==GOLD and stat!=""):return false
	g._consume_item(cap)
	for key in (stats if cap==GOLD else [stat]):
		mon.hyper_trained[key]=true
	Party.recalc(mon,true)
	g._persist()
	return true
