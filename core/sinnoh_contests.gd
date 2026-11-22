extends RefCounted
const RANKS := ["普通","超级","高级","大师"]
const CATS := ["帅气","美丽","可爱","聪明","强壮"]
const THEMES := ["造型","锐利","人造","自然","缤纷","坚实","明亮","华丽","柔软","庆典","无形","悠闲"]
const JUDGES := ["毕克","蜜蜜","佐助"]
const TASTES := ["辣","涩","甜","苦","酸"]
const NATURES := ["勤奋","怕寂寞","勇敢","固执","顽皮","大胆","坦率","悠闲","淘气","乐天","胆小","急躁","认真","爽朗","天真","内敛","慢吞吞","冷静","害羞","马虎","温和","温顺","自大","慎重","浮躁"]
const FLAVOR_STAT := [0,4,2,1,3]
const PartyPick := preload("res://core/frlg_sidequests.gd")
static var tables: Dictionary

static func data() -> Dictionary:
	if tables.is_empty(): tables=JSON.parse_string(FileAccess.get_file_as_string("res://content/sinnoh_contests.json"))
	return tables

static func case(g) -> Dictionary:
	var kit: Dictionary=g.save_data.get_or_add("sinnoh_fashion",{})
	if g._flags().get("s_jubilife_grunts",false) and not kit.has("started"):
		kit.started=true
		var inventory: Dictionary=kit.get_or_add("accessories",{})
		for i in 5:
			var fluff := str(g.rng.randi_range(0,5))
			var feather := str(g.rng.randi_range(18,25))
			inventory[fluff]=int(inventory.get(fluff,0))+1
			inventory[feather]=int(inventory.get(feather,0))+1
		g._persist()
	if g._flags().get("s_contest",false) and not kit.has("powder"):
		kit.powder=true
		kit.get_or_add("accessories",{})["49"]=1
		g._persist()
	return kit

static func talk(g, npc: Dictionary) -> bool:
	if g.world.map_data.get("region","")!="sinnoh":return false
	match npc.get("source_script",""):
		"Contests_ReceptionistOfficialContest","Contests_ReceptionistPracticeContest":
			if not g._flags().get("s_contest",false):g._dialog(["先和会场里的妈妈、美棠见面吧。"],"接待员")
			else:
				var practice: bool=npc.source_script=="Contests_ReceptionistPracticeContest"
				g._pick("选择练习项目" if practice else "参加哪一组超级华丽大赛？",["装扮","舞蹈","演技"] if practice else CATS,func(i):
					if practice:g._pick("选择属性组别",CATS,func(c):choose_mon(g,c,i))
					else:choose_mon(g,i,-1))
		"HearthomeCityPokemonFanClub_Gentleman":
			if g._bag_count("宝芬盒")==0:
				g._give_item("宝芬盒",1,"key");g._persist()
				g._dialog(["这是宝芬盒。去隔壁的宝芬料理屋，把树果烘焙成点心，喂给你的宝可梦吧。"],"会长")
			else:g._dialog(["宝芬的味道各不相同。与你的宝可梦喜欢的口味搭配，成长会更好。"],"会长")
		"ContestHallLobby_RichBoy":
			if g._flags().get("s_mild_poffin",false):g._dialog(["带着适合组别的伙伴上场吧。"])
			elif g._bag_count("宝芬盒")==0:g._dialog(["先去宝可梦爱好俱乐部找会长领宝芬盒，我有东西想送你。"])
			elif g.save_data.get("sinnoh_poffins",[]).size()>=100:g._dialog(["宝芬盒已经装满了。"])
			else:
				g.save_data.get_or_add("sinnoh_poffins",[]).append({"flavors":[60,30,30,30,30],"smooth":40})
				g._flags().s_mild_poffin=true;g._persist();g._dialog(["这枚６０级的松软宝芬送给你。"])
		"AmitySquare_GiftMan":load("res://core/sinnoh_amity.gd").gift(g)
		"FlowerShop_Beauty":florist(g)
		"VeilstoneCitySouthwestHouse_Beauty":massage(g)
		"PoffinCommon_PokefanF":cook(g)
		"VeilstoneStoreB1F_PoffinVendor":buy_poffin(g)
		_:return false
	return true

static func capacity(id: int) -> int:
	return 9 if id<61 else 1

static func florist(g) -> void:
	var stock: Dictionary=case(g).get_or_add("accessories",{})
	var labels: Array=[]
	var goods: Array=[]
	for row in data().shop:
		var id:=int(row[0])
		if int(stock.get(str(id),0))>=capacity(id):continue
		var berry: String=g.get_node("/root/Data").berry_name(row[1])
		labels.append("%s · %s ×%d"%[data().accessories[id],berry,row[2]])
		goods.append([id,berry,int(row[2])])
	if goods.is_empty():g._dialog(["所有饰品都已收齐。"],"花店");return
	g._pick("用树果交换饰品",labels,func(i):
		var current: Array=goods[i]
		if g._bag_count(current[1])<current[2]:g._dialog(["需要 %d 颗%s。"%[current[2],current[1]]],"花店");return
		for n in current[2]:g._consume_item(current[1])
		var key:=str(current[0])
		stock[key]=int(stock.get(key,0))+1
		g._persist();g._dialog(["收到%s。"%data().accessories[int(current[0])]],"花店"))

static func massage(g) -> void:
	var today:=Time.get_date_string_from_system()
	if g._flags().get("s_accessory_massage","")==today:g._dialog(["今天的按摩做过了，明天再来吧。"]);return
	PartyPick.pick_party(g,"给哪只宝可梦按摩？",func(mon):return not mon.get("egg",false),func(slot):
		var mon: Dictionary=g.save_data.party[slot]
		mon.friendship=mini(255,int(mon.get("friendship",70))+3)
		var stock: Dictionary=case(g).get_or_add("accessories",{})
		var available: Array=data().massage.filter(func(id):return int(stock.get(str(int(id)),0))<capacity(int(id)))
		var lines: Array=["%s看起来很舒服。"%mon.name]
		if not available.is_empty():
			var id:=int(available[g.rng.randi_range(0,available.size()-1)])
			stock[str(id)]=int(stock.get(str(id),0))+1
			lines.append("在毛发里找到了%s。"%data().accessories[id])
		g._flags().s_accessory_massage=today
		g._persist();g._dialog(lines,"按摩师"))

static func choose_mon(g, cat: int, practice: int) -> void:
	var slots := []
	var choices := []
	for i in g.save_data.party.size():
		var mon: Dictionary=g.save_data.party[i]
		if mon.is_empty() or not mon.moves.any(func(id):return data().moves.has(str(int(id)))):continue
		slots.append(i)
		choices.append(mon.name)
	if slots.is_empty():g._dialog(["请带上会使用神奥大赛招式的伙伴。"]);return
	g._pick("让谁登台？",choices,func(i):
		var mon: Dictionary=g.save_data.party[slots[i]]
		var earned := int(mon.get("sinnoh_ribbons",{}).get(str(cat),0))
		g._pick("选择级别",RANKS.slice(0,4 if practice>=0 else mini(4,earned+1)),func(rank):
			var stage=load("res://scenes/sinnoh_contest_stage.gd").new()
			var kit:=case(g)
			open_panel(g,stage)
			stage.finished.connect(func(done,won):
				close_panel(g,stage)
				if not done or practice>=0:return
				if won:
					var photo_dress: Array=[]
					for decoration in stage.dress:
						photo_dress.append({"id":decoration.id,"xy":[decoration.at.x,decoration.at.y]})
					kit.get_or_add("photos",{})[str(cat)]={"name":mon.name,"species":mon.species_id,"form":mon.get("form",""),"shiny":mon.get("shiny",false),"rank":rank,"dress":photo_dress}
					var friendship:=int(mon.get("friendship",70))
					mon.friendship=mini(255,friendship+[3,2,1][mini(2,friendship/100)])
					var ribbons: Dictionary=mon.get_or_add("sinnoh_ribbons",{})
					ribbons[str(cat)]=maxi(int(ribbons.get(str(cat),0)),rank+1)
					var prize:=int(data().prizes[cat*4+rank])
					var stock: Dictionary=kit.get_or_add("accessories",{})
					stock[str(prize)]=mini(capacity(prize),int(stock.get(str(prize),0))+1)
					g._dialog(["%s赢得了%s组%s级奖章！饰品盒里收好了%s。"%[mon.name,CATS[cat],RANKS[rank],data().accessories[prize]]],"结果公布")
				g._persist())
			stage.start(g,mon,cat,rank,kit.get("accessories",{}),practice)))

static func open_panel(g, panel: Control) -> void:
	g.menu_layer.add_child(panel)
	g.panel_open+=1
	g._set_hud_visible(false)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func close_panel(g, panel: Control) -> void:
	panel.queue_free()
	g.panel_open=maxi(0,g.panel_open-1)
	g._set_hud_visible(g.panel_open==0)

static func photo(g, obj: Dictionary) -> bool:
	var script:=str(obj.get("source_script",""))
	if not script.begins_with("ContestHallLobby_Frame"):return false
	var cat:=int(script.trim_prefix("ContestHallLobby_Frame"))
	var saved: Dictionary=case(g).get("photos",{}).get(str(cat),{})
	if saved.is_empty():
		g._dialog(["这是%s组优胜者的纪念相框。"%CATS[cat]])
	else:
		var gallery=load("res://scenes/sinnoh_contest_stage.gd").new()
		open_panel(g,gallery)
		gallery.finished.connect(func(_done,_won):close_panel(g,gallery))
		gallery.show_photo(saved,cat)
	return true

static func use_item(g, name: String) -> bool:
	if name=="饰品盒":
		var inventory: Dictionary=case(g).get("accessories",{})
		var labels: Array=inventory.keys().map(func(id):return "%s ×%d"%[data().accessories[int(id)],inventory[id]])
		g._dialog(["还没有收集饰品。" if labels.is_empty() else "　".join(labels)],"饰品盒")
		return true
	if name=="宝芬盒":
		var tray: Array=g.save_data.get("sinnoh_poffins",[])
		if tray.is_empty(): g._dialog(["盒里还没有宝芬。料理屋可以用树果制作。"]);return true
		g._pick("选择喂食的宝芬",tray.map(func(p):return poffin_name(p)),func(i):
			PartyPick.pick_party(g,"喂给哪位伙伴？",func(mon):return int(mon.get("sheen",0))<255,func(slot):
				var mon: Dictionary=g.save_data.party[slot]
				feed(mon,tray[i])
				tray.remove_at(i)
				g._persist()
				g._dialog(["%s吃下了宝芬。帅气／美丽／可爱／聪明／强壮　%s"%[mon.name,str(mon.contest_condition)]],"宝芬盒")))
		return true
	return false

static func buy_poffin(g) -> void:
	if g._bag_count("宝芬盒")==0:g._dialog(["请先到家缘市领取宝芬盒。"]);return
	var shelf: Array=[]
	for a in 5:
		for b in range(a+1,5):
			var flavors: Array=[0,0,0,0,0]
			flavors[a]=32;flavors[b]=32
			shelf.append({"flavors":flavors,"smooth":20})
	g._pick("双味宝芬　每枚 ₽6400",shelf.map(func(p):return poffin_name(p)),func(i):
		if int(g.save_data.get("money",0))<6400:g._dialog(["这枚宝芬售价 ₽6400。"]);return
		var tray: Array=g.save_data.get_or_add("sinnoh_poffins",[])
		if tray.size()>=100:g._dialog(["宝芬盒已经装满了。"]);return
		g.save_data.money=int(g.save_data.money)-6400
		tray.append(shelf[i])
		g._persist();g._dialog(["宝芬已装进盒里。"]))

static func poffin_name(p: Dictionary) -> String:
	var peak := int(p.flavors.max())
	var flavors := []
	for i in 5:
		if int(p.flavors[i])>0:flavors.append(TASTES[i])
	return "%s宝芬　Lv.%d　润滑度 %d"%["·".join(flavors),peak,int(p.smooth)]

static func feed(mon: Dictionary, p: Dictionary) -> void:
	var nature := NATURES.find(mon.get("nature","坦率"))
	var cond: Array=mon.get_or_add("contest_condition",[0,0,0,0,0])
	for i in 5:
		var modifier := 1.0
		if nature>=0 and nature/5!=nature%5:
			if i==FLAVOR_STAT[nature/5]:modifier=1.1
			if i==FLAVOR_STAT[nature%5]:modifier=0.9
		cond[i]=mini(255,int(cond[i])+int(float(p.flavors[i])*modifier))
	mon.sheen=mini(255,int(mon.get("sheen",0))+int(p.smooth))
	mon.friendship=mini(255,int(mon.get("friendship",70))+1)

static func cook(g) -> void:
	if g._bag_count("宝芬盒")==0:g._dialog(["请先向家缘市爱好俱乐部的会长领取宝芬盒。"]);return
	if g.save_data.get("sinnoh_poffins",[]).size()>=100:g._dialog(["盒里已经装了１００枚宝芬。"]);return
	var berries: Array=g.bag_items.filter(func(r):return int(r.get("count",0))>0 and data().berries.has(r.get("berry","")))
	if berries.is_empty():g._dialog(["带一颗树果来，我们一起做宝芬。"]);return
	g._pick("放入哪颗树果？",berries.map(func(r):return "%s ×%d"%[r.name,r.count]),func(i):
		var berry: Dictionary=berries[i]
		var pan=load("res://scenes/sinnoh_poffin_pan.gd").new()
		g._consume_item(berry.name)
		g._persist()
		open_panel(g,pan)
		pan.finished.connect(func(seconds,mistakes):
			close_panel(g,pan)
			var p:=bake(data().berries[berry.berry],seconds,mistakes,g.rng)
			g.save_data.get_or_add("sinnoh_poffins",[]).append(p)
			g._persist();g._dialog(["你做好了"+poffin_name(p)+"！"],"宝芬料理屋"))
		pan.start())

static func bake(berry: Array, seconds: float, mistakes: int, rng) -> Dictionary:
	var tastes := []
	var negatives := 0
	for i in 5:
		var diff := int(berry[i])-int(berry[(i+1)%5])
		tastes.append(diff)
		if diff<0:negatives+=1
	for i in 5:tastes[i]=clampi(roundi((int(tastes[i])-negatives)*60.0/maxf(1.0,seconds))-mistakes,0,255)
	if negatives>=4 or tastes.max()==0:
		tastes=[0,0,0,0,0]
		while tastes.count(2)<3:tastes[rng.randi_range(0,4)]=2
	return {"flavors":tastes,"smooth":maxi(0,int(berry[5])-1)}
