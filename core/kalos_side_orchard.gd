extends RefCounted
## Six rows of six plots. Timestamps advance while the game is closed.
static var table: Dictionary

static func data() -> Dictionary:
	if table.is_empty():table=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_orchard.json"))
	return table

static func label(g,key: String) -> String:
	return g.get_node("/root/Data").berry_name(key)

static func give(g,key: String,amount: int) -> void:
	for i in amount:g._give_bag_item(label(g,key),"berry","",key)

static func interact(g,row: Dictionary) -> void:
	var bed: Dictionary=g.save_data.get_or_add("kalos_garden",{})
	match str(row.action):
		"wild_berry":
			for move in row.moves:
				if not g._party_can_move(move):
					g._dialog([g._field_move_hint(move,{"CUT":"居合斩","STRENGTH":"怪力","SURF":"冲浪","WATERFALL":"攀瀑"}[move])])
					return
			var dates: Dictionary=g.save_data.get_or_add("kalos_berry_trees",{})
			var now:=int(Time.get_unix_time_from_system())
			if dates.has(row.id) and now-int(dates[row.id])<7*24*3600:
				g._dialog(["树下还没有新掉下来的树果。过些天再来看看。"])
				return
			give(g,row.berry,1)
			dates[row.id]=now
			g._persist()
			g._dialog(["在树下捡到了一颗%s。"%label(g,row.berry)])
		"orchard":
			if not g._flags().get("ks_orchard",false):
				give(g,"oran",5);give(g,"pecha",5)
				g._give_item("莲叶童子喷壶",1,"key")
				load("res://core/kalos_side.gd").mark(g,"ks_orchard")
			g._dialog(["这六垄果圃交给你照料。一垄有六个位置。种下背包中的树果、浇水、给相邻的树配对，成熟后回来采收。"],row.name)
		"plot":
			row_menu(g,int(row.index),bed)
		"compost":
			mix(g,[],bed)

static func row_menu(g,idx: int,bed: Dictionary) -> void:
	var labels: Array=[]
	for n in 6:
		var crop: Dictionary=bed.get(str(idx*6+n),{})
		var name: String="空地" if not crop.has("berry") else label(g,crop.berry)+" · "+phase(crop)
		labels.append("%d　%s"%[n+1,name])
	labels.append("返回")
	g._pick("第 %d 垄果圃"%(idx+1),labels,func(n):
		if n<6:plot(g,idx*6+n,bed))

static func phase(crop: Dictionary,now: int=-1) -> String:
	if now<0:now=int(Time.get_unix_time_from_system())
	var p:=float(now-int(crop.at))/float(int(data().berries[crop.berry][1])*3600)
	if p>=1:return "成熟"
	if p>=.75:return "开花"
	if p>=.5:return "长高"
	if p>=.25:return "发芽"
	return "播种"

static func yield_count(spec: Array,crop: Dictionary) -> int:
	var fertilizer:=str(crop.get("mulch",""))
	var watering_bonus: int=crop.water.size() * (2 if fertilizer in ["速效肥","惊奇肥"] else 1)
	var soil_bonus:=2 if fertilizer in ["硕果肥","惊奇肥"] else 0
	return mini(int(spec[3]),int(spec[2])+watering_bonus+soil_bonus)

static func owned(g) -> Array:
	var keys: Array=[]
	for b in g.bag_items:
		if b.get("category","")=="berry" and int(b.get("count",0))>0 and data().berries.has(str(b.get("berry",""))):keys.append(str(b.berry))
	return keys

static func plot(g,i: int,bed: Dictionary) -> void:
	var key:=str(i)
	var crop: Dictionary=bed.get(key,{})
	if not crop.has("berry"):
		var choices:=owned(g)
		var options:=choices.map(func(k):return label(g,k))
		options.append("施肥");options.append("取消")
		g._pick("这块地种什么？",options,func(n):
			if n==choices.size():mulch(g,crop,key,bed);return
			if n>=choices.size():return
			var which: String=choices[n]
			if g._bag_count(label(g,which))<1:return
			g._consume_item(label(g,which));crop.berry=which;crop.at=int(Time.get_unix_time_from_system());crop.water=[]
			bed[key]=crop;g._persist();g._dialog(["种下了%s。"%label(g,which)]))
		return
	if phase(crop)=="成熟":
		g._pick("%s成熟了。"%label(g,crop.berry),["采收","暂时留下"],func(n):
			if n!=0:return
			var spec: Array=data().berries[crop.berry]
			var qty:=yield_count(spec,crop)
			give(g,crop.berry,qty)
			var mutation:=cross(g,i,bed,crop)
			if mutation!="":give(g,mutation,1)
			bed.erase(key);g._persist()
			g._dialog(["收获了%d颗%s。"%[qty,label(g,crop.berry)]]+(["枝头还长出了一颗%s！"%label(g,mutation)] if mutation!="" else [])))
		return
	var stage:=phase(crop)
	g._pick("%s正在%s。"%[label(g,crop.berry),stage],["用莲叶童子喷壶浇水","离开"],func(n):
		if n!=0:return
		if not crop.water.has(stage):crop.water.append(stage)
		g._persist();g._dialog(["土壤变得湿润了。"]))

static func cross(g,i: int,bed: Dictionary,crop: Dictionary) -> String:
	var neighbors: Array=[]
	if i%6>0:neighbors.append(i-1)
	if i%6<5:neighbors.append(i+1)
	if i>=6:neighbors.append(i-6)
	if i<30:neighbors.append(i+6)
	for j in neighbors:
		var other: Dictionary=bed.get(str(j),{})
		if not other.has("berry"):continue
		for key in data().mutations:
			var pair: Array=data().mutations[key]
			if pair.size()!=2 or not pair.has(crop.berry) or not pair.has(other.berry) or crop.berry==other.berry:continue
			if crop.get("mulch","") in ["变异肥","惊奇肥"] or g.rng.randi_range(0,99)<15:return key
	return ""

static func mulch(g,crop: Dictionary,key: String,bed: Dictionary) -> void:
	var stocks:=["硕果肥","变异肥","速效肥","惊奇肥"].filter(func(s):return g._bag_count(s)>0)
	if stocks.is_empty():g._dialog(["把三颗树果投入堆肥机，就可以制作肥料。"]);return
	g._pick("用哪种肥料？",stocks+["返回"],func(i):
		if i>=stocks.size():return
		if crop.has("mulch"):g._dialog(["这里已经施过肥了。"]);return
		g._consume_item(stocks[i]);crop.mulch=stocks[i];bed[key]=crop;g._persist();g._dialog(["土壤里混入了%s。"%stocks[i]]))

static func mix(g,selected: Array,bed: Dictionary) -> void:
	var choices:=owned(g).filter(func(k):return g._bag_count(label(g,k))>selected.count(k))
	var labels:=choices.map(func(k):return label(g,k));labels.append("取消")
	g._pick("堆肥机 · 选择第 %d / 3 颗树果"%(selected.size()+1),labels,func(i):
		if i>=choices.size():return
		var result:=selected.duplicate();result.append(choices[i])
		if result.size()<3:mix(g,result,bed);return
		for k in result:
			if g._bag_count(label(g,k))<result.count(k):return
		var colors: Array=[]
		for k in result:
			var col: String=data().berries[k][0]
			if not colors.has(col):colors.append(col)
			g._consume_item(label(g,k))
		var product: String="惊奇肥" if result.has("kee") or result.has("maranga") else ["","变异肥","速效肥","硕果肥"][colors.size()]
		g._give_item(product,3,"other");g._persist();g._dialog(["制成了三份%s。"%product]))
