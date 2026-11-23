extends RefCounted
## Prism Tower's four original quizzes, including the trainer guarding each selected lift.
const FLOORS:=["kalos_zone_79","kalos_zone_80","kalos_zone_81","kalos_zone_82","kalos_gym_lumiose"]
const QUIZZES:=[
	{"images":[25],"choices":["电飞鼠","咚咚鼠","皮卡丘"],"answer":2,"trainers":[461,462,463]},
	{"images":[661],"choices":["小箭雀","波波","傲骨燕"],"answer":0,"trainers":[464,465,466]},
	{"images":[515],"choices":["花椰猴","爆香猴","冷水猴"],"answer":2,"trainers":[28,29,30]},
	{"images":[12,666,414],"choices":["一号剪影","二号剪影","三号剪影"],"answer":1,"trainers":[467,468,469]}
]
const SKATERS:=[83,84,146,147]

static func locked_leader(game,npc:Dictionary) -> bool:
	if str(npc.get("role",""))!="k_badge_3" or game._flags().get("k_badge_3",false):return false
	var remaining:int=SKATERS.filter(func(id):return not game._flags().get("k_trainer_"+str(id),false)).size()
	if not remaining:return false
	game._dialog(["还剩 %d 位轮滑手。沿场地找他们较量，每次胜利都会升起一段滑轨。" % remaining],"可尔妮")
	return true

static func image_panel(g, family:Array) -> void:
	var panel:Control=g.menu_layer.get_child(-1)
	var viewport:Vector2=g.get_viewport_rect().size
	var width:float=viewport.x*.41
	for child in panel.get_children():
		if child is ScrollContainer:
			child.position.x=width+16
			child.size.x=viewport.x-width-34
	var art:=ColorRect.new()
	art.position=Vector2(18,52)
	art.size=Vector2(width-16,minf(150,viewport.y-112))
	art.color=Color("#b6d8a8")
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(art)
	var slot:float=art.size.x/family.size()
	for i in family.size():
		var pic:=TextureRect.new()
		pic.texture=load(g.get_node("/root/Data").sprite_path(int(family[i])))
		pic.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		pic.modulate=Color("#192d3a")
		pic.position=Vector2(i*slot+2,4)
		pic.size=Vector2(slot-4,art.size.y-23)
		pic.mouse_filter=Control.MOUSE_FILTER_IGNORE
		art.add_child(pic)
		if family.size()>1:
			var number:=Label.new()
			number.text=str(i+1)
			number.position=Vector2(i*slot,art.size.y-23)
			number.size=Vector2(slot,23)
			number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			number.add_theme_color_override("font_color",Color("#1f3c47"))
			art.add_child(number)

static func warp(g,target:Dictionary)->bool:
	var floor:int=FLOORS.find(g.world.map_data.id)
	if floor<0 or floor>=QUIZZES.size() or target.map!=FLOORS[floor+1]:return false
	var flag:="k_prism_quiz_%d"%(floor+1)
	if g._flags().get(flag,false) or g._flags().get("k_badge_5",false):return false
	g.held_dir="";g.run_held=false
	var q:Dictionary=QUIZZES[floor]
	var title:="哪一只是彩粉蝶？" if floor==3 else "剪影里是哪只宝可梦？"
	g._pick("柚丽嘉　%dF　%s"%[floor+2,title],q.choices,func(choice):
		var id:int=q.trainers[choice]
		var trainer_key:="k_trainer_%d"%id
		var judge:=func():
			if choice!=q.answer:
				g._dialog(["猜错了！再看一次剪影，试试另一台电梯。"],"柚丽嘉")
				return
			g._flags()[flag]=true
			g._persist()
			g._dialog(["答对啦！这台电梯通往上一层。"],"柚丽嘉").closed.connect(func():g._do_warp(target),CONNECT_ONE_SHOT)
		if g._flags().get(trainer_key,false):
			judge.call()
			return
		var campaign=load("res://core/kalos_campaign.gd")
		var registry:Dictionary=campaign.trainer_data()
		var label:String=registry.people[str(id)][0]
		var cfg:Dictionary=campaign.team({"kalos_team":id,"name":label},g._flags())
		g._start_battle({"name":label,"kalos_trainer":trainer_key,"battle":cfg},func(result):
			if result=="a":judge.call()
			elif result=="b" and g._party_fainted():g._blackout()
		)
	)
	image_panel(g,q.images)
	return true

const ICE_SWITCHES:={
	"pink":[169,"粉红"],"blue":[32,"蓝"],"green":[168,"绿"],"yellow":[31,"黄"]
}

static func ice_gate(p:Vector2i,flags:Dictionary)->bool:
	if flags.get("k_badge_8",false):return true
	if p.x==24 and p.y>=35 and p.y<=37:return flags.get("k_ice_bridge_blue",false)
	if p.y==30 and p.x>=18 and p.x<=20:return flags.get("k_ice_bridge_mid",false)
	if p.y==13 and p.x>=18 and p.x<=20:return flags.get("k_ice_bridge_last",false)
	return true

static func ice_switch(g, obj:Dictionary)->bool:
	if obj.get("kind","")!="kalos_ice_switch":return false
	var c:=str(obj.color)
	var guardian:Array=ICE_SWITCHES[c]
	var f:Dictionary=g._flags()
	if not f.get("k_trainer_%s"%guardian[0],false):
		g._show_toast("先向守在%s色开关旁的训练家挑战。"%guardian[1])
		return true
	var key:="k_ice_turn_"+c
	f[key]=(int(f.get(key,0))+1)%4
	if int(f.get("k_ice_turn_pink",0))==2:f["k_ice_bridge_blue"]=true
	if f.get("k_ice_bridge_blue",false) and int(f.get("k_ice_turn_blue",0))==3 and int(f.get("k_ice_turn_pink",0))==1:f["k_ice_bridge_mid"]=true
	if f.get("k_ice_bridge_mid",false) and int(f.get("k_ice_turn_green",0))==3 and int(f.get("k_ice_turn_yellow",0))==1:f["k_ice_bridge_last"]=true
	g.world.taken=f
	g.snd.play_sfx("select")
	g._show_toast("%s色冰台向右转了一格。"%guardian[1])
	g.world._rebuild(f)
	g._persist()
	return true
