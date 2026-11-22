extends RefCounted
const BERRIES := preload("res://core/emerald_contest.gd")
const Press := preload("res://scenes/berry_press.gd")
const JAR := "粉末瓶"
const GOODS := {"元气粉":50,"元气根":80,"万能粉":50,"复活草":300,"攻击增强剂":1000,"防御增强剂":1000,"速度增强剂":1000,"特攻增强剂":1000,"特防增强剂":1000,"HP 增强剂":1000,"PP 提升剂":3000}

static func vendor(g) -> void:
	if g._bag_count(JAR)==0:
		g._give_item(JAR,1,"key")
		g._persist()
		g._dialog(["给你一个粉末瓶。在宝可梦中心楼上的无线柜台一起压榨树果，再带粉末来换药。"],"树果粉末商人")
		return
	var products:=GOODS.keys()
	var labels: Array=[]
	for item in products:labels.append("%s　%d 粉末" % [item,GOODS[item]])
	g._pick("可用粉末　%d" % int(g.save_data.get("berry_powder",0)),labels+["离开"],func(i):
		if i>=products.size():return
		var item: String=products[i]
		var balance: int=g.save_data.get("berry_powder",0)
		if balance<GOODS[item]:
			g._dialog(["粉末还差 %d 份。" % (GOODS[item]-balance)])
			return
		g.save_data.berry_powder=balance-int(GOODS[item])
		g._give_item(item,1,"heal")
		g._persist()
		g._dialog(["换到了%s。" % item]))

static func club(g) -> void:
	if g._bag_count(JAR)==0:
		g._dialog(["树果压榨需要粉末瓶。可以到凯那市集市或华蓝市的树果粉末老爷爷家领取。"])
		return
	var choices: Array=[]
	for item in g.bag_items:
		var key:=str(item.get("berry","")).to_lower()
		if int(item.get("count",0))>0 and BERRIES.data().berries.has(key):
			choices.append({"key":key,"name":str(item.name)})
	if choices.is_empty():
		g._dialog(["带上一颗丰缘时代的树果，就能操作压榨机。"])
		return
	var labels:=choices.map(func(v):return v.name)
	g._pick("放入哪一种树果？",labels+["离开"],func(i):
		if i>=choices.size():return
		var chosen: Dictionary=choices[i]
		var screen:=Press.new()
		g.menu_layer.add_child(screen)
		g.panel_open+=1
		g._set_hud_visible(false)
		screen.closed.connect(func(reward: int):
			if reward>0 and g._bag_count(chosen.name)>0:
				g._consume_item(chosen.name)
				g.save_data.berry_powder=mini(99999,int(g.save_data.get("berry_powder",0))+reward)
				g.save_data.powder_record=maxi(reward,int(g.save_data.get("powder_record",0)))
				g._persist()
			g.panel_open=maxi(0,g.panel_open-1)
			g._set_hud_visible(g.panel_open==0)
			if reward>0:g._dialog(["压出了 %d 份树果粉末，已经倒进粉末瓶。" % reward]))
		screen.setup(chosen.key))
