extends RefCounted
const Berry := preload("res://core/kalos_side_orchard.gd")
const Party := preload("res://core/party.gd")
const REDUCING_BERRIES := ["occa","passho","wacan","rindo","yache","chople","kebia","shuca","coba","payapa","tanga","charti","kasib","haban","colbur","babiri","chilan"]
const STONES := ["FIRE_STONE","WATER_STONE","LEAF_STONE","THUNDER_STONE","MOON_STONE","SUN_STONE","SHINY_STONE","DUSK_STONE","DAWN_STONE","EVERSTONE"]

static func inverse(g) -> void:
	var today:=Time.get_date_string_from_system()
	if g.save_data.get("kalos_inver_date","")==today:
		g._dialog(["今天已经比试过了。明天再来看看新的属性搭配吧。"],"反转先生")
		return
	g._pick("反转对战 · 克制关系颠倒，属性免疫也变为效果绝佳。",["开始对战","离开"],func(i):
		if i!=0:return
		var opponents: Array=[]
		var available: Array=load("res://core/kalos_side.gd").data().inverse.duplicate()
		var forms: Dictionary=preload("res://core/kalos_side_explore.gd").data().abilities
		var level:=65 if g._flags().get("k_champion",false) else 55
		for slot in 3:
			var row: Array=available.pop_at(g.rng.randi_range(0,available.size()-1))
			var choices: Array=forms[str(int(row[0]))].filter(func(n):return int(n)>0)
			var set_row:={"species":int(row[0]),"level":level,"moves":row[1],"ability":int(choices[g.rng.randi_range(0,choices.size()-1)])}
			if str(row[2]).ends_with("_BERRY"):set_row.berry=str(row[2]).trim_suffix("_BERRY").to_lower()
			else:set_row.held=row[2]
			opponents.append(set_row)
		var record:={"score":0,"fainted":false}
		g.save_data.kalos_inver_date=today
		g._persist()
		g._start_battle({"name":"反转先生","battle":{"team":opponents}},func(result):
			if result=="a":reward(g,int(record.score),1 if record.fainted else 3)
			elif g._party_fainted():g._blackout())
		if is_instance_valid(g.active_battle):g.active_battle.battle.inverse_record=record)

static func reward(g,score: int,quantity: int) -> void:
	var label: String
	if score>=10:
		label="神奇糖果"
		g._give_item(label,quantity,"heal")
	elif score>=7:
		var key: String=STONES[g.rng.randi_range(0,STONES.size()-1)]
		var data=g.get_node("/root/Data")
		label=data.item_name(key) if key=="EVERSTONE" else data.evo_item_name(key)
		if key=="EVERSTONE":
			for n in quantity:g._give_bag_item(label,"held",key)
		else:g._give_item(label,quantity,"evo")
	else:
		var berry: String=REDUCING_BERRIES[g.rng.randi_range(0,REDUCING_BERRIES.size()-1)] if score>=4 else "sitrus" if score>=1 else "oran"
		label=Berry.label(g,berry)
		Berry.give(g,berry,quantity)
	g._persist()
	g._dialog(["这场反转对战的得分是 %d！请收下%d份%s。"%[score,quantity,label]],"反转先生")

const TRICKS := {"parallel":"平行滑步","dash":"转身冲刺","backflip":"后空翻","spin":"空中旋转","cosmic":"宇宙翻转"}
const CAPS := preload("res://core/kalos_skate_appearance.gd").CAPS

static func learn(g,row: Dictionary) -> void:
	var trick: String=row.trick
	if trick=="cosmic" and not (g._flags().get("ks_trick_backflip",false) and g._flags().get("ks_trick_spin",false)):
		g._dialog(["先去密阿雷北大道和轮滑咖啡馆学会后空翻与空中旋转，再来和首领切磋。"],row.name)
		return
	g._flags()["ks_trick_"+trick]=true
	g._flags().ks_skate_mode=trick
	g._persist()
	g._dialog(["学会了%s！%s。从背包打开轮滑鞋可换回其他动作。"%[TRICKS[trick],"按住 B 通过台阶时，小悠会在空中完成动作" if trick in ["backflip","cosmic","spin"] else "按住 B 转向时使出动作"]],row.name)

static func skates(g) -> void:
	var keys: Array=["normal","parallel","dash"]
	for trick in ["backflip","spin","cosmic"]:
		if g._flags().get("ks_trick_"+trick,false):keys.append(trick)
	var options: Array=keys.map(func(k):return TRICKS.get(k,"普通轮滑"))
	options.append("收起")
	g._pick("轮滑鞋 · 按住 B 同时移动",options,func(i):
		if i>=keys.size():return
		g._flags().ks_skate_mode=keys[i]
		g._persist()
		g._show_toast("已选%s。"%options[i]))

static func galette(g,hour: int=-1) -> void:
	if hour<0:hour=int(Time.get_time_dict_from_system().hour)
	var since: int=posmod(hour-3,6)
	if since>=4:
		g._dialog(["下一炉会在 03:00、09:00、15:00 或 21:00 出炉。"],"格雷派饼师傅")
		return
	var price:=80 if int(g.save_data.get("kalos_style",0))>=50 else 100
	g._pick("密阿雷格雷派饼",["买一块　%d元"%price,"买一打　%d元"%(price*12),"离开"],func(i):
		if i>=2:return
		var amount:=1 if i==0 else 12
		if int(g.save_data.money)<price*amount:g._dialog(["钱不够。"]);return
		g.save_data.money-=price*amount
		g._give_item("密阿雷格雷派饼",amount,"heal")
		var today:=Time.get_date_string_from_system()
		if since==0 and g.save_data.get("kalos_galette_milk","")!=today:
			g.save_data.kalos_galette_milk=today
			g._give_item("哞哞鲜奶",1,"heal")
			g._show_toast("刚出炉，附赠了一瓶哞哞鲜奶。")
		g._persist())

static func boutique(g,couture: bool) -> void:
	if couture and int(g.save_data.get("kalos_style",0))<25:
		g._dialog(["目前还只接待熟客。在密阿雷逛逛美术馆、旅馆和餐厅，积累时髦度再来吧。"])
		return
	var keys: Array=CAPS.keys()
	var labels: Array=[]
	var closet: Dictionary=g.save_data.get_or_add("kalos_caps",{"green":true})
	var price:=100000 if couture else 1800
	for tint in keys:
		var owned: bool=closet.has(tint)
		labels.append("%s · %s%s"%["丰缘头饰",CAPS[tint],"　试戴" if owned else "　%d元"%price])
	labels.append("离开")
	g._pick("试衣间 · 小悠的头饰",labels,func(i):
		if i>=keys.size():return
		var tint: String=keys[i]
		if closet.has(tint):
			wear(g,tint)
			return
		var options:=["原价买下　%d元"%price]
		if g._bag_count("折价券")>0:options.append("使用折价券　%d元"%(price/2))
		options.append("放回去")
		g._pick("购买%s头饰？"%CAPS[tint],options,func(j):
			if j==options.size()-1:return
			var used: bool = j==1
			var cost:=price/2 if used else price
			if int(g.save_data.money)<cost:g._dialog(["钱不够。"]);return
			if used and g._bag_count("折价券")<1:return
			if used:g._consume_item("折价券")
			g.save_data.money-=cost
			closet[tint]=true
			if couture:g.save_data.kalos_style=mini(255,int(g.save_data.get("kalos_style",0))+10)
			wear(g,tint)))

static func wear(g,tint: String) -> void:
	g._flags().ks_cap=tint
	g.world._sync_player()
	g._persist()
	g._show_toast("换上了%s头饰。"%CAPS[tint])
