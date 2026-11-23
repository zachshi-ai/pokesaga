extends RefCounted

const Party := preload("res://core/party.gd")
const FR := preload("res://core/frlg_sidequests.gd")
const MEMORIES := {"fire":"火","water":"水","electric":"电","grass":"草","ice":"冰","fighting":"格斗","poison":"毒","ground":"地面","flying":"飞行","psychic":"超能力","bug":"虫","rock":"岩石","ghost":"幽灵","dragon":"龙","dark":"恶","steel":"钢","fairy":"妖精"}
const GIFTS := [[20,735,20,20],[40,105,752,25],[50,754,758,30],[70,738,777,35],[80,778,778,40],[100,743,784,50]]
const CORE_MOVES := [245,614,349,615,687]

static func side():
	return load("res://core/alola_side.gd")

static func gift(g,row: Dictionary) -> void:
	if row.get("egg",false):
		if Party.occupied(g.save_data.party)>=Party.MAX_SIZE:
			g._dialog(["先在队伍中留出一个空位，就可以领走这枚蛋。"],row.name)
			return
		g._flags().as_egg_steps=0
		g._give_item("阿罗拉的蛋",1,"key")
		side().complete(g,row)
		g._dialog(["交给你一枚伊布的蛋。带着它在阿罗拉走走吧。"],row.name)
		return
	side().give_mon(g,int(row.species),int(row.level))
	if row.get("memories",false):
		for k in MEMORIES:g._give_bag_item(MEMORIES[k]+"存储碟","held","MEMORY_"+k.to_upper())
	side().complete(g,row)
	g._dialog(["属性：空加入了。１７种存储碟也交给你。进化为银伴战兽后，让它携带一张存储碟就能改变属性。"],row.name)

static func egg_step(g) -> bool:
	if not g._flags().has("as_egg_steps"):return false
	var warm: bool=g.save_data.party.any(func(m):return int(m.get("ability",0)) in [40,49])
	g._flags().as_egg_steps=int(g._flags().as_egg_steps)+(2 if warm else 1)*int(side().factor(g,"hatch"))
	if int(g._flags().as_egg_steps)<35*256:return false
	g._flags().erase("as_egg_steps")
	g._consume_item("阿罗拉的蛋")
	g._record_hatch()
	side().give_mon(g,133,1)
	g._persist()
	g._dialog(["蛋壳发出轻响，一只伊布探出了脑袋！"])
	return true

static func play(g,row: Dictionary) -> void:
	var f: Dictionary=g._flags()
	match str(row.action):
		"collect":
			if row.kind=="sticker":f.as_stickers=int(f.get("as_stickers",0))+1
			else:
				f.as_stock=int(f.get("as_stock",0))+1
				f.as_cells=int(f.get("as_cells",0))+1
			side().complete(g,row)
			g._show_toast("收集了霸主贴纸（%d／100）"%f.as_stickers if row.kind=="sticker" else "基格尔德多面体收集量：%d／100"%f.as_cells)
		"stickers":stickers(g)
		"assemble":assembly(g)
		"shop":
			g._pick("究极球　每个 1,000 元　持有 %d 元"%g.save_data.money,["购买１个","购买１０个","离开"],func(i):
				if i==2:return
				var qty:=1 if i==0 else 10
				if int(g.save_data.money)<1000*qty:g._dialog(["身上的钱不够。"]);return
				g.save_data.money-=1000*qty
				g._give_item("究极球",qty,"ball")
				g._persist()
				g._show_toast("究极球 ×%d"%qty))
		"spare":
			if g._bag_count("究极球")==0:g._give_item("究极球",1,"ball");g._persist();g._dialog(["这颗备用的究极球请收好。"],row.name)
			else:g._dialog(["究极球是保护异兽的专用球。把它的体力削弱后再投球。"],row.name)
		"sell":
			var qty: int=g._bag_count("巨大金珠")
			if qty==0:g._dialog(["有巨大金珠可以带来给我，一颗两万元。"]);return
			g._pick("以 %d 元收购 %d 颗巨大金珠？"%[qty*20000,qty],["卖出","留着"],func(i):
				if i!=0:return
				for k in qty:g._consume_item("巨大金珠")
				g.save_data.money+=qty*20000
				g._persist())
		"unlock":
			if g._bag_count(row.item)>0:
				side().complete(g,row)
				g._dialog([row.text],row.name)
		"heal":
			g._heal_party();g._persist();g._dialog(["皮皮，帮伙伴恢复精神吧。"],row.name)
		"puzzle":puzzle(g,row)
		"reverse":
			if not f.get("a_reverse_world",false):
				var moon: bool=str(f.a_version).ends_with("moon")
				var hour: int=preload("res://core/alola_field.gd").hour(f)
				if not has_mascot(g) or ((hour>=6 and hour<18)!=moon):
					g._dialog(["只有带着露奈雅拉在白天来到这里，通道才会打开。" if moon else "只有带着索尔迦雷欧在夜晚来到这里，通道才会打开。"],row.name)
					return
			g._pick("祭坛另一侧的天空和这里相反。",["穿过裂隙","离开"],func(i):
				if i==0:
					f.a_reverse_world=not f.get("a_reverse_world",false)
					side().refresh(g)
					g._dialog(["你回到了自己的世界。" if not f.a_reverse_world else "天色倒转了。前往乌拉乌拉花园深处的湖，在祭坛寻找你的伙伴。"]))
		"cosmog":
			if not has_mascot(g):g._dialog(["祭坛上的光芒还在等着另一位伙伴。"]);return
			side().give_mon(g,789,5)
			if str(f.a_version).begins_with("ultra"):side().grant_crystal(g,"SOLGANIUM_Z" if str(f.a_version).ends_with("moon") else "LUNALIUM_Z")
			side().complete(g,row);g._dialog(["两只传说宝可梦在湖边相会。留下的科斯莫古轻轻飘进了你的怀中。"])
		"tree_intro":
			g._pick("想向哪位前辈挑战？",["赤红","青绿","稍后再来"],func(i):
				if i<2:
					var rival:=row.duplicate(true)
					rival.team=159+i
					rival.name=["赤红","青绿"][i]
					rival.text=["……！","好啊！就让我们在这里较量一次吧。"][i]
					side().trainer(g,rival))
		"tree":preload("res://core/alola_side_tree.gd").open(g)
		"bp_exchange":preload("res://core/alola_side_tree.gd").exchange(g)
		"surf":surf(g,row)
		"surf_pikachu":
			for n in 4:
				if not surf_record(f,n):
					g._dialog(["在四处海滩都刷新最高分后，再来找我。"],row.name);return
			var mon: Dictionary=side().give_mon(g,25,40,"",[609,435,21,57],3)
			mon.held="GOLD_BOTTLE_CAP"
			mon.berry=""
			side().complete(g,row)
			g._dialog(["这只皮卡丘会冲浪！它还带着金色王冠。"],row.name)
		"tutor":
			FR.pick_party(g,"让哪只皮卡丘学会伏特攻击？",func(m):return int(m.species_id)==25,func(i):g._tm_teach_one(344,i,"伏特攻击",true))
		"starter_crystals":
			for k in {722:"DECIDIUM_Z",725:"INCINIUM_Z",728:"PRIMARIUM_Z"}:
				if int(f.get("a_starter",0))!=k:side().grant_crystal(g,{722:"DECIDIUM_Z",725:"INCINIUM_Z",728:"PRIMARIUM_Z"}[k])
			side().complete(g,row);g._dialog(["这两枚是另两位初始伙伴最终进化时能使用的Ｚ纯晶。"],row.name)

static func stickers(g) -> void:
	var f: Dictionary=g._flags()
	var count:=int(f.get("as_stickers",0))
	for r in GIFTS:
		var need:=int(r[0])
		if f.get("as_oak_"+str(need),false):continue
		if count<need:g._dialog(["你有 %d 张霸主贴纸。集齐 %d 张时，我会把一位特别高大的伙伴交给你。"%[count,need]],"成也・大木");return
		var sid:=int(r[1] if f.a_version=="ultra_sun" else r[2])
		var form: String=""
		for entry in g.get_node("/root/Data").species_of(sid).get("forms",[]):
			if "TOTEM" in str(entry.get("key","")):form=entry.key;break
		var gift_mon: Dictionary=side().give_mon(g,sid,int(r[3]),form)
		gift_mon.alola_totem_size=true
		f["as_oak_"+str(need)]=true
		side().refresh(g)
		g._dialog(["这只霸主大小的%s就拜托你照顾啦！"%gift_mon.name],"成也・大木")
		return
	g._dialog(["一百张贴纸都收集齐了。谢谢你一直留意各岛上的霸主宝可梦！"],"成也・大木")

static func set_zygarde(g,mon: Dictionary,ten: bool,power: bool) -> void:
	var key: String=("ZYGARDE_10_POWER_CONSTRUCT" if ten else "ZYGARDE_50_POWER_CONSTRUCT") if power or ten else ""
	Party.set_form(mon,key)
	mon.ability=211 if power else 188
	mon.ability_name=g.get_node("/root/Data").abilities.get(mon.ability,{}).get("name","")
	preload("res://core/dex_variants.gd").record(g.save_data,mon,true)

static func cube(g) -> void:
	var f: Dictionary=g._flags()
	var opts: Array=["切换群聚变形基格尔德的形态"]
	var moves: Array=[]
	for i in CORE_MOVES.size():
		if f.get("as_core"+str(i),false) or f.get("as_dexio_cell",false):
			moves.append(CORE_MOVES[i])
			opts.append("传授"+str(g.get_node("/root/Data").move_of(CORE_MOVES[i]).name))
	opts.append("收起")
	g._pick("基格尔德多面体 · 可用细胞 %d"%int(f.get("as_stock",0)),opts,func(i):
		if i==opts.size()-1:return
		FR.pick_party(g,"选择基格尔德",func(m):return int(m.species_id)==718 and (i!=0 or int(m.ability)==211),func(slot):
			var mon: Dictionary=g.save_data.party[slot]
			if i==0:
				set_zygarde(g,mon,not str(mon.form).begins_with("ZYGARDE_10"),true)
				g._persist()
				g._show_toast("基格尔德改变了形态。")
			else:g._tm_teach_one(moves[i-1],slot,g.get_node("/root/Data").move_of(moves[i-1]).name,true)))

static func assembly(g) -> void:
	var f: Dictionary=g._flags()
	var stock:=int(f.get("as_stock",0))
	g._pick("基格尔德复原中心 · 可用细胞 %d"%stock,["合成１０％形态","合成５０％形态","与队伍里的基格尔德重组","分离队伍里的基格尔德","离开"],func(i):
		if i==4:return
		if i<2:
			var need:=10 if i==0 else 50
			if stock<need:g._dialog(["多面体里的细胞不足。"]);return
			f.as_stock=stock-need
			var level:=50 if f.get("a_credits",false) else 40 if f.get("a_nanu",false) else 30
			var mon: Dictionary=side().give_mon(g,718,level)
			set_zygarde(g,mon,i==0,false);g._persist()
			g._dialog(["基格尔德已经合成。"]);return
		FR.pick_party(g,"选择要放入复原机器的基格尔德",func(m):return int(m.species_id)==718 and int(m.get("ability",0))!=211,func(slot):
			var mon: Dictionary=g.save_data.party[slot]
			var number:=10 if str(mon.form).begins_with("ZYGARDE_10") else 50
			if i==2:
				if stock+number<100:g._dialog(["要完成群聚变形，细胞总数需要达到 100。"]);return
				f.as_stock=stock+number-100
				set_zygarde(g,mon,number==10,true);g._persist()
				g._dialog(["重组完成，特性变成了群聚变形。"]);return
			g._pick("分离后这只基格尔德会化为 %d 个细胞。"%number,["确认分离","取消"],func(j):
				if j==0:
					g.save_data.party.remove_at(slot)
					f.as_stock=stock+number
					g._persist())))

static func puzzle(g,row: Dictionary,stage:=0) -> void:
	var tracks: Dictionary={
		"warp":[["入口有三个传送点。墙上的标记是月牙。",["圆","月牙","三角"],1],["房间倒转了，下一间的入口是星形。",["星","三角","圆"],0]],
		"colors":[["记住灯的顺序：红、蓝、绿。",["红","绿","蓝"],0],["第二盏？",["蓝","红","绿"],0],["第三盏？",["红","绿","蓝"],1]],
		"arrows":[["北边的地板向左转，南边的箭头指向入口。",["北侧","南侧"],0],["尽头的两块地砖一个朝墙，一个朝楼梯。",["朝墙","朝楼梯"],1]],
		"statues":[["第一座喵喵正望向通道。",["让它看墙","从正面经过"],0],["第二座朝左侧，在它背后有条路。",["左侧","右侧"],1]],
		"button":[["镜门另一侧传来机关声。要按下哪个按钮？",["红色按钮","蓝色按钮"],-1]]}
	var list: Array=tracks[row.puzzle]
	var clue: Array=list[stage]
	g._pick(clue[0],clue[1],func(i):
		if int(clue[2])>=0 and i!=int(clue[2]):
			g._dialog(["机关重新归位。你可以从第一步再试一次。"]);return
		if stage+1<list.size():puzzle(g,row,stage+1)
		else:side().complete(g,row);g._dialog(["装置启动，通道打开了。"]))

static func surf_record(flags: Dictionary,course: int) -> bool:
	var key: String="as_surf_top_%d"%course
	return bool(flags.get(key,flags.get(key+".0",false)))

static func surf(g,row: Dictionary) -> void:
	var ui=load("res://core/alola_side_surf.gd").new()
	g.menu_layer.add_child(ui);g.panel_open+=1;g._set_hud_visible(false)
	var flags: Dictionary=g._flags()
	var unlocked:=0
	for i in 4:
		if surf_record(flags,i):unlocked+=1
	ui.setup(int(row.course),unlocked)
	ui.finished.connect(func(points):
		g.panel_open=maxi(0,g.panel_open-1)
		ui.queue_free();g._set_hud_visible(g.panel_open==0)
		if points<0:return
		var key: String="as_surf_best_%d"%int(row.course)
		flags[key]=maxi(points,int(flags.get(key,flags.get(key+".0",0))))
		var bp:=clampi(floori(float(points)/4000.0),1,50)
		g.save_data.bp=int(g.save_data.get("bp",0))+bp
		if points>=[12200,27200,43200,58300][int(row.course)]:flags["as_surf_top_%d"%int(row.course)]=true
		g._persist()
		g._dialog(["本次 %d 分，纪录 %d 分。获得 %d BP！"%[points,flags[key],bp]],row.name))


static func has_mascot(g) -> bool:
	var sid:=792 if str(g._flags().a_version).ends_with("moon") else 791
	var form: String="NECROZMA_DAWN_WINGS" if sid==792 else "NECROZMA_DUSK_MANE"
	return g.save_data.party.any(func(m):return int(m.get("species_id",0))==sid or str(m.get("form",""))==form)
