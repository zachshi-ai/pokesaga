extends RefCounted
## Six independent facts about each of the sixteen people in the Fame Checker.
const NAMES := {"OAK":"大木博士","DAISY":"奈奈美","BROCK":"小刚","MISTY":"小霞","LTSURGE":"马志士","ERIKA":"莉佳","KOGA":"阿桔","SABRINA":"娜姿","BLAINE":"夏伯","LORELEI":"科拿","BRUNO":"希巴","AGATHA":"菊子","LANCE":"阿渡","BILL":"正辉","MRFUJI":"富士老人","GIOVANNI":"坂木"}
const TEXT := {
	"OAK":["真新镇的大木宝可梦研究所由他主持。","编写全世界宝可梦的完整图鉴，一直是他的梦想。","训练家们都很敬重这位宝可梦研究权威。","他与孙女奈奈美、孙子小茂住在真新镇。","菊子还记得年轻时英俊又能打的大木。","他要开设广播节目《大木博士的宝可梦讲座》。"],
	"DAISY":["奈奈美能看出伙伴有多喜欢训练家，也会替它们梳毛。","爱好者俱乐部的客人认为，奈奈美尤其讨宝可梦喜欢。","一位饲育家见过小小的奈奈美温柔地为宝可梦理毛。","奈奈美和弟弟小茂都是大木博士的孙辈。","她每天喝茶，常来玉虹百货买茶。","真新镇的奈奈美曾夺得春季宝可梦华丽大赛总冠军。"],
	"BROCK":["小刚是尼比道馆的馆主，擅长岩石属性。","他相信坚定的意志也表现在岩石伙伴身上。","当地人觉得他对训练格外认真。","山路上的男孩希望长大后也成为受敬重的馆主。","小刚有时会到月见山帮助挖掘化石。","听说他很少笑，可笑起来就停不下来。"],
	"MISTY":["华蓝道馆的馆主小霞被称为活泼的人鱼。","小霞偏好以水属性伙伴全力进攻。","道馆里的训练家看好她继续变强。","她也到海边和水属性宝可梦训练。","她对著名的约会胜地华蓝海角有些憧憬。","她很仰慕冰系四天王科拿。"],
	"LTSURGE":["枯叶道馆的马志士以电属性闻名。","电属性宝可梦曾在战场上救过他。","从前的部下记得他严厉的训练。","服役时，他就以行事谨慎闻名。","道馆里的双重机关是他亲自装的。","传言他当过飞行员，用伙伴发的电驱动飞机。"],
	"ERIKA":["玉虹馆主莉佳热爱自然。","她学习插花，也专精草属性。","莉佳很文静，却是当地的名人。","道馆的草属性伙伴也会帮忙插花。","美丽的宝可梦最能吸引她收藏。","有人瞥见她常常在道馆里打瞌睡。"],
	"KOGA":["浅红道馆的阿桔精通毒属性和忍术。","阿桔喜欢用毒属性变化逐步瓦解对手。","弟子即便落败也坚持遵照他的教导修行。","女儿正在练习运用毒属性，想赶上父亲。","他熟悉药理，还会亲自调药照顾伙伴。","他定期巡查沙湖乐园，保护入园游客。"],
	"SABRINA":["金黄馆主娜姿专精超能力属性。","三岛的居民也听说过这位超能力馆主。","她自幼就有超能力，曾无意间弄弯勺子。","她并不热爱战斗，但愿意向挑战者展现力量。","据说她在战斗中不用开口就能指挥伙伴。","她曾击败隔壁格斗道场的师父。"],
	"BLAINE":["红莲馆主夏伯喜欢用谜题考验来客。","他的火属性伙伴以猛烈的火焰迎战。","年轻时他在山中迷路，循着火鸟的光找到了归路。","研究所盖好之前，他就已住在红莲岛。","照片里，他和富士老人肩并肩地笑着。","据说他只在构思新问题时摘下墨镜。"],
	"LORELEI":["科拿是关都四天王之一。","她对冰属性宝可梦的实力深具信心。","她在七岛的四之岛长大。","擅长冷静计算战局的科拿，还有鲜为人知的爱好。","每次回四岛，她的玩偶收藏总会增加。","有人记得她小时候在冰冻瀑布洞窟遇到了拉普拉斯。"],
	"BRUNO":["希巴是关都四天王之一。","他和格斗伙伴一起生活、修行。","想与最强训练家交手的愿望让他加入四天王。","他到火照山道的温泉疗养自己和伙伴的伤。","他也喜欢愤怒馒头，曾因为卖光而失望离开。","他曾和丰缘的藤树一起修行。"],
	"AGATHA":["菊子是关都四天王之一。","她的幽灵伙伴强得令人胆寒。","据说她脾气很急，小事也能让她吼起来。","年轻时她和大木曾作为训练家争夺胜负。","她至今记得年轻的大木，也惋惜老对手转做研究。","菊子保持着四天王成员的年长纪录。"],
	"LANCE":["阿渡是擅长龙属性的关都四天王领队。","他认为龙难捕获、难培育，实力却值得付出。","崇拜他的人称赞他的正义感和热情。","百货店员发现阿渡常来买披风。","据说他的祖父是著名驯龙家族的长老。","他有一位远在他乡担任道馆馆主的表亲。"],
	"BILL":["正辉热爱宝可梦，也是电脑寄存系统的发明者。","他收藏了许多宝可梦，包括罕见的种类。","按他祖父的说法，正辉从小就喜欢收藏。","他第一次捕获的是凯西。","他的父母仍住在城都的满金市。","正辉的肠胃受不了牛奶。"],
	"MRFUJI":["富士老人照顾被遗弃或失去亲人的宝可梦。","他曾独自找到火箭队，抗议他们虐待宝可梦。","他收看的爱好者杂志上，抽奖申请表已经剪走了。","镇上的居民说富士老人并非紫苑镇本地人。","照片里，富士老人和夏伯笑得很开心。","他谢绝杂志采访，当地人仍十分爱戴他。"],
	"GIOVANNI":["坂木自称火箭队首领，为组织搜罗宝可梦。","西尔佛的研究员听说火箭队的首领在找强大的宝可梦。","另一位研究员说，他只把宝可梦当作工具。","常磐道馆曾是坂木筹划火箭队复兴的据点。","得知道馆馆主就是坂木，向导非常吃惊。","仓库的研究员记得，坂木的孩子有一头红发。"]
}
const LETTER := {
	"OAK":"你的伙伴肯为你全力以赴，是因为你把爱与信任给了它们。记住这一点。",
	"DAISY":"我喝茶的这些日子，你已经成长了许多。以后也做我弟弟的好对手吧。",
	"BROCK":"世界上一定还有很多高手。让我们各自训练，一起变强。",
	"MISTY":"我要在道馆继续练习。等本领更好一点，我也想出门旅行。",
	"LTSURGE":"那场战斗令我重新认识了你。你和你的伙伴都很有胆量！",
	"ERIKA":"想到还有你这样的训练家，我就想再努力一些。有空再来道馆做客。",
	"KOGA":"我们都该把目标定得更高。现在我要回去指点女儿了。",
	"SABRINA":"你珍爱伙伴的力量，连我的超能力也未能战胜。",
	"BLAINE":"我的火属性伙伴还会更强。再考你一道，火属性宝可梦有多少种？",
	"LORELEI":"谢谢你的帮助。下次在联盟相遇时，我还是会全力以赴。",
	"BRUNO":"我已经体验过你们的力量。下次我来教你亲自修行吧。",
	"AGATHA":"等你年纪大了，可别像大木一样放下战斗。和我一样继续打下去！",
	"LANCE":"我打算回故乡锻炼龙伙伴。希望有一天能邀请你同行。",
	"BILL":"锦辉说了你许多好话。抓到罕见宝可梦时，记得带来给我看看。",
	"MRFUJI":"除了自己的伙伴，我也希望你愿意关心所有宝可梦的幸福。",
	"GIOVANNI":"我没有什么要对你说。今后我会把心思放在磨练自己上面。"
}
const BADGES := {"BROCK":"灰色徽章","MISTY":"蓝色徽章","LTSURGE":"橙色徽章","ERIKA":"彩虹徽章","KOGA":"粉红徽章","SABRINA":"金色徽章","BLAINE":"深红徽章","GIOVANNI":"绿色徽章"}
const CAST := {"OBJ_EVENT_GFX_WOMAN_2":"woman","OBJ_EVENT_GFX_CAMPER":"camper","OBJ_EVENT_GFX_BOY":"youngster","OBJ_EVENT_GFX_LASS":"lass","OBJ_EVENT_GFX_BEAUTY":"beauty","OBJ_EVENT_GFX_CRUSH_GIRL":"lass","OBJ_EVENT_GFX_BALDING_MAN":"man"}
static func roster(m: Dictionary,flags: Dictionary,actors: Array,entries: Dictionary) -> Array:
	for coord: String in entries:
		var row: Dictionary=entries[coord]
		if row.field or not CAST.has(row.gfx):continue
		if row.flag=="FLAG_HIDE_POSTGAME_GOSSIPERS" and not flags.get("kanto_champion",false):continue
		var xy:=coord.split(",")
		var at:=[int(xy[0]),int(xy[1])]
		if actors.any(func(n):return n.at==at):continue
		var clue: String=row.clues[0]
		actors.append({"at":at,"name":"当地训练家","gfx":CAST[row.gfx],"lines":[TEXT[clue.left(-1)][int(clue.right(1))]]})
	return actors

static func known(g) -> Dictionary:
	if not g._flags().has("fr_fame_clues"):g._flags().fr_fame_clues={}
	var entries: Dictionary=g._flags().fr_fame_clues
	if g._flags().get("got_dex",false):entries.OAK1=true
	if g._flags().get("rival_bridge",false):entries.BILL0=true
	if g._flags().get("beat_tower_grunt_2",false):entries.MRFUJI1=true
	if g._flags().get("hideout_boss_win",false):entries.GIOVANNI0=true
	if g._flags().get("beat_giovanni",false):entries.GIOVANNI3=true
	return entries

static func lookup(g,at: Vector2i) -> Dictionary:
	var key: String="%s/%s"%[g.world.map_data.region,g.world.map_data.id]
	return preload("res://core/frlg_sidequests.gd").data().fame.get(key,{}).get("%d,%d"%[at.x,at.y],{})

static func available(g,row: Dictionary,id: String) -> bool:
	var f: Dictionary=g._flags()
	var badges: Array=preload("res://core/region_journey.gd").badges(g.save_data,"kanto")
	if row.flag=="FLAG_HIDE_POSTGAME_GOSSIPERS" or id in ["OAK5","DAISY0","DAISY1","DAISY4"]:
		return f.get("kanto_champion",false)
	if "JOURNAL" in str(row.flag) or id in ["BROCK1","MISTY1","LTSURGE1","ERIKA1","KOGA1","SABRINA2","SABRINA3","BLAINE1","GIOVANNI4"]:
		return BADGES.get(id.left(-1),"") in badges
	match id:
		"OAK1":return f.get("got_dex",false)
		"DAISY2":return g.save_data.party.any(func(mon):return int(mon.get("species_id",0)) in [175,176] and mon.get("original_trainer","")=="") and f.get("frs_FiveIsland_WaterLabyrinth_EventScript_EggGentleman",false)
		"GIOVANNI5","BILL3","BILL4","BILL5":return f.get("sevii_network_online",false)
		"LORELEI5":return f.get("sevii_network_online",false)
		"BRUNO4":return f.get("sevii_detour_finished",false)
	return true

static func learn(g,row: Dictionary) -> Array:
	var found: Array=[]
	var clues:=known(g)
	for id: String in row.clues:
		if clues.has(id) or not available(g,row,id):continue
		clues[id]=true
		found.append(TEXT[id.left(-1)][int(id.right(1))])
		if id in ["BILL3","BILL4","BILL5"]:break
	if not found.is_empty():g._persist()
	return found

static func speaker(g,npc: Dictionary) -> void:
	if g.world.map_data.get("region","") not in ["kanto","sevii"]:return
	var p: Array=npc.at
	var row:=lookup(g,Vector2i(int(p[0]),int(p[1])))
	if row.is_empty() or row.field:return
	var found:=learn(g,row)
	if not found.is_empty() and g._bag_count("名人传言器")>0:g._show_toast("名人传言器记下了新线索。")

static func field(g,pos: Vector2i) -> bool:
	var row:=lookup(g,pos)
	if row.is_empty() or not row.field:return false
	var facts:=learn(g,row)
	if facts.is_empty():
		for id: String in row.clues:
			if available(g,row,id):facts.append(TEXT[id.left(-1)][int(id.right(1))])
	if facts.is_empty():return false
	g._dialog(facts,"当地见闻")
	return true

static func open(g) -> void:
	var entries:=known(g)
	var people: Array=[]
	var counts: Array=[]
	for person: String in NAMES:
		var n:=0
		for i in 6:
			if entries.has(person+str(i)):n+=1
		if n>0:
			people.append(person)
			counts.append("%s　%d / 6"%[NAMES[person],n])
	if people.is_empty():
		g._dialog(["在各地拜访训练家、读路牌和杂志，可以收集当地名人的故事。"],"名人传言器")
		return
	g._pick("名人传言器",counts,func(i):
		var who: String=people[i]
		var facts: Array=[]
		for j in 6:
			if entries.has(who+str(j)):facts.append(TEXT[who][j])
		if facts.size()==6:facts.append("给训练家的留言 · "+LETTER[who])
		g._dialog(facts,NAMES[who]))
