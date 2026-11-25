extends RefCounted
## A small selection from each local catalogue. Colours are applied to Brendan's existing field sheets.
const STOCK := {
	"wedgehurst":[["条纹上衣·深蓝",1500,"345678"],["宽松上衣·绿色",990,"598861"],["连帽衫·橙色",2100,"c18150"]],
	"motostoke":[["运动外套·挑战者",5000,"486c89"],["棒球外套·红色",17800,"ae5158"],["连帽衫·落日都市",2500,"b77867"]],
	"hammerlocke":[["褪色卫衣·蓝色",8800,"7596ad"],["运动外套·草属性",10180,"628d58"],["运动外套·火属性",10180,"bd6551"]],
	"circhester":[["图案T恤·伊布",15800,"ac8468"],["破洞上衣·黑色",21400,"62616a"],["缎面外套·苦涩摇滚",88000,"777488"]],
	"wyndon":[["机车夹克·焦糖",111300,"966f54"],["运动外套·电属性",10180,"c8ac60"],["运动外套·妖精属性",10180,"bb8096"]]}
const HAIR := {"自然黑":"473d45","深棕":"78554a","酒红":"974f5a","灰金":"beaa81","烟灰":"8d959c"}
const CUTS := ["清爽短发","侧分","短碎发"]
static var cache:Dictionary

static func wear(g,code:String)->void:
	var f:Dictionary=g._flags()
	f.g_fashion_worn=code
	f.g_gym_uniform="";f.g_grass_uniform_worn=false;f.a_guide_worn=false
	g.world._sync_player()
	g._persist()

static func fitting(g)->void:
	var wardrobe:Dictionary=g.save_data.get("galar_wardrobe",{})
	var names:Array=["小悠的绿宝石原装"];var codes:Array=[""]
	for code in wardrobe:
		names.append(str(wardrobe[code]));codes.append(code)
	g._pick("试衣间",names,func(i):
		wear(g,codes[i]);g._show_toast("换好了。"))

static func boutique(g,city:String)->void:
	var rows:Array=STOCK[city]
	var wardrobe:Dictionary=g.save_data.get_or_add("galar_wardrobe",{})
	var labels:Array=[]
	for row in rows:labels.append(str(row[0])+("　已购" if wardrobe.has(row[2]) else "　%d元"%int(row[1])))
	g._pick("挑选上装",labels,func(i):
		var row:Array=rows[i]
		if wardrobe.has(row[2]):
			wear(g,row[2]);g._show_toast("换上了"+str(row[0])+"。");return
		g._pick("买下并换上"+str(row[0])+"？",["买下　%d元"%int(row[1]),"再看看"],func(j):
			if j:return
			if int(g.save_data.money)<int(row[1]):g._dialog(["钱不够。"]);return
			g.save_data.money-=int(row[1]);wardrobe[row[2]]=row[0]
			wear(g,row[2]);g._show_toast("换上了"+str(row[0])+"。")))

static func salon(g)->void:
	g._pick("剪发和染发　3000元",CUTS+["离开"],func(i):
		if i==CUTS.size():return
		var names:Array=HAIR.keys();names.append("取消")
		g._pick("选择发色",names,func(j):
			if j==names.size()-1:return
			if int(g.save_data.money)<3000:g._dialog(["美发服务需要3000元。"]);return
			g.save_data.money-=3000
			g._flags().g_fashion_hair=HAIR[names[j]]
			g._flags().g_fashion_cut=i
			g.world._sync_player();g._persist()
			g._show_toast(names[j]+"色的"+CUTS[i]+"，完成了。")))

static func talk(g,role:String)->void:
	if role=="venue_fitting":fitting(g)
	elif role=="venue_style_guest":g._dialog(["我在等靠窗的那面镜台。"])
	elif role.begins_with("venue_boutique_"):boutique(g,role.trim_prefix("venue_boutique_"))
	elif role.begins_with("venue_salon_"):salon(g)

static func sheet(base:Texture2D,f:Dictionary,afloat:bool)->Texture2D:
	var clothing:String=f.get("g_fashion_worn","")
	if not str(f.get("g_gym_uniform","")).is_empty() or f.get("g_grass_uniform_worn",false) or f.get("a_guide_worn",false):clothing=""
	var hair:String=f.get("g_fashion_hair","")
	if clothing=="" and hair=="":return base
	var cut:=int(f.get("g_fashion_cut",0))
	var key:="%d:%s:%s:%s:%d"%[base.get_instance_id(),clothing,hair,afloat,cut]
	if cache.has(key):return cache[key]
	var im:=base.get_image()
	if im.is_compressed():im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	var shirt:=Color.from_string(clothing,Color.WHITE)
	var dye:=Color.from_string(hair,Color.BLACK)
	var pixels:=32 if afloat else 16
	var dy:=1 if afloat else 0
	for y in range(15+dy,29+dy):
		for x in im.get_width():
			var c:=im.get_pixel(x,y)
			if c.a==0:continue
			var px:=x%pixels
			if not clothing.is_empty() and y>=23+dy and y<=27+dy:
				if c==Color8(197,65,65):im.set_pixel(x,y,shirt.darkened(.18))
				elif c==Color8(255,98,90):im.set_pixel(x,y,shirt.lightened(.23))
				elif c==Color8(16,32,57) and (not afloat or px>=12 and px<=20):im.set_pixel(x,y,shirt.darkened(.55))
			if not hair.is_empty() and y>=17+dy and y<=20+dy and c==Color8(16,32,57):
				var stripe:bool=(px+(1 if cut==1 else 0))%3==0 if cut!=2 else (px+y)%3==0
				im.set_pixel(x,y,dye.lightened(.24) if stripe else dye)
	var output:=ImageTexture.create_from_image(im);cache[key]=output
	return output
