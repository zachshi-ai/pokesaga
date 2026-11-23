extends RefCounted
const Roller=preload("res://scenes/alola_roller.gd")
const Studio=preload("res://scenes/alola_photo_studio.gd")
static func attach(g,panel) -> void:
	g.menu_layer.add_child(panel);g.panel_open+=1;g._set_hud_visible(false)
	panel.closed.connect(func():
		g.panel_open=maxi(0,g.panel_open-1)
		if g.panel_open==0:g._set_hud_visible(true))

static func office(g,kind:String) -> void:
	if not str(g._flags().get("a_version","")).begins_with("ultra"):
		g._dialog(["本设施属于《究极之日／究极之月》的岛屿巡礼。"]);return
	if kind=="roller":
		if not g._flags().get("a_guzma_garden",false):
			g._dialog(["马利埃庭园的事告一段落后，再来帮我测试这台充电盘吧。"],"研究员");return
		var n:=mini(4,int(g._flags().get("a_roller_rank",0))+1)
		g._pick("四次以内接通电路",Roller.LEVELS.slice(0,n),func(i):
			var ui:=Roller.new();attach(g,ui);ui.start(g,i))
		return
	if g._bag_count("阿罗拉相册")==0:g._give_item("阿罗拉相册",1,"key");g._persist()
	var choices:=["和伙伴合照","翻看相册"]
	if g._flags().get("a_trial_guide_outfit",false):choices.append("更衣")
	g._pick("阿罗拉摄影俱乐部",choices,func(i):
		if i==1:album(g);return
		if i==2:
			g._pick("小悠的服装",["绿宝石原色","考验向导服"],func(j):
				g._flags().a_guide_worn=j==1;g.world._sync_player();g._persist();g._show_toast("换好了。"))
			return
		var mons:Array=g.save_data.party.filter(func(m):return m is Dictionary and not m.is_empty() and not m.get("is_egg",false))
		if mons.is_empty():g._dialog(["请带上一只伙伴来拍照。"]);return
		g._pick("选择合照的伙伴",mons.map(func(m):return "%s Lv.%d"%[m.name,m.level]),func(j):
			var ui:=Studio.new();attach(g,ui);ui.start(g,mons[j])))

static func album(g) -> void:
	var photos:Array=g.save_data.get("alola_photos",[])
	if photos.is_empty():g._dialog(["相册中还没有照片。来好奥乐市或可霓可市的摄影俱乐部拍一张吧。"]);return
	var ui:=Studio.new();attach(g,ui);ui.gallery(g,photos.size()-1)
