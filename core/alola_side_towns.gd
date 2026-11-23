extends RefCounted
const Party:=preload("res://core/party.gd")
const FR:=preload("res://core/frlg_sidequests.gd")
const Field:=preload("res://core/alola_field.gd")
const Frontier:=preload("res://core/frontier_rules.gd")

static func side():
	return load("res://core/alola_side.gd")

static func matches(mon: Dictionary,row: Dictionary) -> bool:
	return int(mon.get("species_id",0))==int(row.species) and (str(row.get("form","")).is_empty() or mon.get("form","")==row.form)

static func dex(g,row: Dictionary) -> void:
	var name: String=g.get_node("/root/Data").stats_of(int(row.species),str(row.get("form",""))).get("name","宝可梦")
	var requires_party: bool=str(row.get("form",""))!=""
	var found: bool=g.save_data.party.any(func(m):return matches(m,row)) if requires_party else g.save_data.get("dex",{}).get("caught",[]).has(int(row.species))
	if not found:
		g._dialog(["请把%s带来让我看一看。"%name if requires_party else "如果图鉴中已经登记了%s的捕获资料，能让我看看吗？"%name],row.name)
		return
	if requires_party:g._give_item("甜蜜球",1,"ball")
	else:g.save_data.money+=int(row.amount)
	side().complete(g,row)
	g._dialog(["谢谢！收下这颗甜蜜球吧。" if requires_party else "是%s的资料！这是 %d 元的调查报酬。"%[name,row.amount]],row.name)

static func trade(g,row: Dictionary) -> void:
	var db=g.get_node("/root/Data")
	var give: String=db.species_of(int(row.initial)).name
	var want: String=db.species_of(int(row.want)).name
	g._pick("用%s交换我的%s？"%[want,give],["交换","暂时离开"],func(i):
		if i!=0:return
		FR.pick_party(g,"选择要交换的"+want,func(m):return int(m.species_id)==int(row.want) and not m.has("fused_part"),func(slot):
			var offered: Dictionary=g.save_data.party[slot]
			if offered.get("alola_partner",false) and not g._flags().get("a_credits",false):
				g._dialog(["这位伙伴还要和你一起完成诸岛巡礼。"]);return
			g._pick("将%s交给对方？"%offered.name,["确认交换","取消"],func(j):
				if j!=0:return
				var mon:=Party.make(int(row.species),int(row.level),row.moves,str(row.form))
				Party.init_alola_ivs(mon,g.appearance_rng,row.get("ivs",{}))
				mon.ot=row.ot;mon.ot_id=row.tid;mon.nickname=row.nickname;mon.sex=row.gender
				mon.ability=int(row.ability);mon.ability_name=db.abilities.get(mon.ability,{}).get("name","")
				var idx:=Frontier.NATURE_KEYS.find(str(row.nature).to_upper())
				if idx>=0:mon.nature=Frontier.NATURES[idx]
				if row.held.ends_with("_BERRY"):mon.berry=str(row.held).trim_suffix("_BERRY").to_lower()
				else:mon.held=row.held
				g.save_data.party[slot]=mon
				preload("res://core/dex_variants.gd").record(g.save_data,mon,true)
				side().complete(g,row)
				g._dialog(["交换完成，%s随你出发了。"%mon.name],row.name))))

static func quest(g,row: Dictionary) -> void:
	if int(row.get("need_mon",0))>0 and not g.save_data.party.any(func(m):return int(m.get("species_id",0))==int(row.need_mon)):
		g._dialog(["能把%s带来吗？"%g.get_node("/root/Data").species_of(int(row.need_mon)).name],row.name);return
	if row.has("take") and g._bag_count(row.take)==0:
		g._dialog(["请带来%s。"%row.take],row.name);return
	if row.has("ask"):
		g._pick(row.text,row.ask,func(i):
			if i==0:reward(g,row)
			elif row.id=="lost_meowth":g._dialog(["喵喵退回轮胎后面，警惕地望着你。"]))
		return
	if int(row.get("enemy",0))>0:
		var species:=int(row.enemy)
		var m:=Party.make(species,int(row.level),Field.moves_for(species,int(row.level),g._flags()))
		if row.has("ivs"):Party.init_alola_ivs(m,g.appearance_rng,row.ivs)
		m.alola_stationary=true
		if row.has("nature"):m.nature=row.nature
		g._dialog([row.text],row.name).closed.connect(func():
			g._start_wild_battle(species,int(row.level),"",func(outcome):
				if outcome in ["caught","a"]:side().complete(g,row)
				elif outcome=="b" and g._party_fainted():g._blackout(),"",0,m))
		return
	reward(g,row)

static func reward(g,row: Dictionary) -> void:
	var note: Array=[row.text] if not row.has("ask") else []
	if row.has("take"):g._consume_item(row.take)
	if row.has("held"):
		g._give_bag_item(row.held[0],"held",row.held[1])
		note.append("收到了"+str(row.held[0])+"。")
	if row.has("give"):
		g._give_item(row.give,int(row.get("count",1)),"key" if row.get("key",false) else "other")
		note.append("收到了%s ×%d。"%[row.give,int(row.get("count",1))])
	for gift in row.get("goods",[]):
		g._give_item(gift[0],int(gift[1]),"other")
		note.append("收到了"+str(gift[0])+"。")
	if row.has("crystal"):side().grant_crystal(g,row.crystal)
	if row.has("amount"):
		g.save_data.money+=int(row.amount)
		note.append("收到了 %d 元。"%int(row.amount))
	side().complete(g,row)
	if not note.is_empty():g._dialog(note,row.name)

static func visit(g,row: Dictionary) -> void:
	match str(row.action):
		"family_duel":
			var intro=g._dialog(["喵喵夫人带着阿罗拉喵喵来访。两只喵喵立起尾巴，妈妈让你来指挥家里的伙伴。"],"妈妈")
			intro.closed.connect(func():family_turn(g,row,false))
		"malasada":
			g._pick("今天也有刚炸好的大马拉萨达。",["买一份　350元","下次再来"],func(i):
				if i!=0:return
				if int(g.save_data.money)<350:
					g._dialog(["一份是350元。"],row.name);return
				g.save_data.money-=350
				g._give_item("大马拉萨达",1,"heal")
				g._persist()
				g._dialog(["给你，大马拉萨达要趁热吃。"],row.name))
		"vulpix":visit_vulpix(g,row)

static func family_turn(g,row: Dictionary,second: bool) -> void:
	var moves:=["聚宝功","报恩","小偷","铁尾"]
	g._pick("妈妈的喵喵要怎么做？",moves,func(i):
		if not second:
			var pause=g._dialog(["阿罗拉喵喵抢先使出了击掌奇袭！妈妈的喵喵畏缩了。"],"喵喵夫人")
			pause.closed.connect(func():family_turn(g,row,true))
			return
		g._give_item("PP 提升剂",1,"other")
		side().complete(g,row)
		g._dialog(["妈妈的喵喵听到你的声音，使出%s，击中了要害！"%moves[i],"我在关都训练喵喵的那些年，这孩子一直跟着我呢。","喵喵夫人带着伙伴告别了。妈妈的喵喵把一支 PP 提升剂拨到你手边。"],"妈妈"))

static func visit_vulpix(g,row: Dictionary) -> void:
	var flags: Dictionary=g._flags()
	var today:=Time.get_date_string_from_system()
	match str(row.id):
		"vulpix_cornered":g._dialog(["六尾紧紧叼着王冠，向后退了一步。旁边的骷髅队员挡住了去路。"])
		"vulpix_cap":
			if str(flags.get("as_vulpix_rescue_day",""))>=today:
				g._dialog(["六尾已经被以太基金会接走了。明天你再来一趟吧。"],row.name);return
			g._give_bag_item("银色王冠","held","BOTTLE_CAP")
			side().complete(g,row)
			g._dialog(["这是六尾当时衔着的银色王冠。谢谢你保护它。"],row.name)
		"vulpix_care":
			var stage:=int(flags.get("as_vulpix_visits",0))
			if str(flags.get("as_vulpix_last_day",""))>=today:
				g._dialog(["它今天已经休息了。明天再来看它吧。"],"以太研究员");return
			if stage==0:
				if g._bag_count("大马拉萨达")<1:
					g._dialog(["它还不肯吃东西。能带一份大马拉萨达来吗？好奥乐市和皇家大道都有卖。"],"以太研究员");return
				g._pick("把大马拉萨达放到六尾面前？",["喂给六尾","先收起来"],func(i):
					if i!=0 or g._bag_count("大马拉萨达")<1:return
					g._consume_item("大马拉萨达")
					flags.as_vulpix_visits=1;flags.as_vulpix_last_day=today
					g._persist()
					g._dialog(["六尾轻轻嗅了嗅，终于肯吃一口了。"],"以太研究员"))
			elif stage==1:
				flags.as_vulpix_visits=2;flags.as_vulpix_last_day=today
				g._persist()
				g._dialog(["六尾自己走到你身边，把额头贴在你的掌心。"],"以太研究员")
			else:
				side().complete(g,row)
				g._dialog(["它恢复得很好。我们要送它回拉纳基拉山的雪原，你可以去那里看它。"],"以太研究员")
		"vulpix_recovered":
			g._pick("雪地里的六尾跑来迎接你。",["摸摸它","跟它玩","告别"],func(i):
				if i<2:g._dialog(["六尾眯起眼睛，尾巴轻轻摇晃。" if i==0 else "六尾在雪地里绕着你追了一圈。"]))
