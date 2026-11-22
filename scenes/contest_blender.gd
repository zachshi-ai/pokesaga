extends ColorRect
signal completed(block: Dictionary)
const Contest := preload("res://core/emerald_contest.gd")
var ingredients := []
var linked:=false
var seat:=0
var angle:=0.0
var rpm:=30.0
var peak:=30.0
var cycles:=0
var last_tap:=-1
var precise:=0
var good:=0
var misses:=0
var done:=false
var wheel:=TextureRect.new()
var title:=Label.new()
var status:=Label.new()
var message:=Label.new()
var action:=Button.new()
var last_goal:=0

func setup(berry: String,partners: int=1,master:=false) -> void:
	var names=["cheri","chesto","pecha","rawst","aspear"]
	var sets=[["aspear","rawst","pecha"],["cheri","aspear","rawst"],["chesto","cheri","aspear"],["pecha","chesto","cheri"],["rawst","pecha","chesto"],["cheri","pecha","rawst"],["chesto","rawst","aspear"],["pecha","aspear","cheri"],["rawst","cheri","chesto"],["aspear","chesto","pecha"]]
	var key_index: int=Contest.data().berries.keys().find(berry)
	var row: int=names.find(berry) if berry in names else 5+posmod(key_index,5)
	ingredients=[berry]+sets[row].slice(0,clampi(partners,1,3))
	if master:
		var rare:=["spelon","pamtre","watmel","durin","belue"]
		var substitute:=["tamato","cornn","magost","rabuta","nomel"]
		ingredients[1]=(substitute if berry in rare else rare)[row%5]
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color=Color("#183844")
	title.text="%d 人树果混合机" % ingredients.size()
	title.position=Vector2(22,19)
	add_child(title)
	wheel.texture=load("res://assets/contest_blender.png")
	wheel.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	wheel.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	wheel.position=Vector2(30,68)
	wheel.size=Vector2(168,168)
	wheel.pivot_offset=wheel.size/2
	add_child(wheel)
	for label in [status,message]:
		label.add_theme_font_size_override("font_size",16)
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		add_child(label)
	status.position=Vector2(224,69);status.size=Vector2(234,72)
	message.position=Vector2(224,143);message.size=Vector2(234,70)
	message.text="指针经过金色标记时，点击搅拌。"
	action.position=Vector2(224,226);action.size=Vector2(227,56)
	action.text="搅拌"
	action.pressed.connect(press)
	add_child(action)
	refresh()

func _draw() -> void:
	var phase:=TAU*seat/maxi(ingredients.size(),1)
	var center:=Vector2(114,152)
	var marker:=PackedVector2Array()
	for p in [Vector2(89,0),Vector2(102,-9),Vector2(102,9)]:marker.append(center+p.rotated(phase))
	draw_colored_polygon(marker,Color("#ffd582"))

func _process(dt: float) -> void:
	if done:return
	angle+=TAU*rpm/60.0*dt
	var goal:=floori(angle/TAU*ingredients.size())
	if not linked and goal>last_goal and goal%ingredients.size()!=0:rpm=minf(118,rpm+0.9)
	last_goal=goal
	wheel.rotation=fmod(angle,TAU)
	cycles=floori(angle/TAU)
	peak=maxf(peak,rpm)
	if cycles>=9:
		done=true
		message.text="完成！精准 %d 次，命中 %d 次，失误 %d 次。"%[precise,good,misses]
		action.text="装进方块盒"
	refresh()

func refresh() -> void:
	status.text="转速 %.1f RPM\n混合进度 %d%%"%[rpm,mini(100,roundi(angle/(TAU*9)*100.0))]

func press() -> void:
	if done:
		action.disabled=true
		completed.emit(make_block())
		queue_free()
		return
	var attempt:=roundi((angle-PI/2)/TAU)
	if attempt==last_tap:return
	last_tap=attempt
	score(absf(wrapf(angle-PI/2,-PI,PI)))

func score(offset: float) -> void:
	if offset<0.22:precise+=1;rpm+=5.0;message.text="精准！"
	elif offset<0.63:good+=1;rpm+=2.0;message.text="命中！"
	else:misses+=1;rpm=maxf(24,rpm-2);message.text="太早或太晚了。"
	peak=maxf(peak,rpm)
	refresh()

func make_block() -> Dictionary:
	var flavor: Array=[0,0,0,0,0]
	var feel:=0
	for key in ingredients:
		var b: Dictionary=Contest.data().berries[key]
		feel+=int(b.smooth)
		for i in 5:flavor[i]=int(flavor[i])+int(b.flavor[i])
	var total:=flavor.duplicate()
	var negative:=0
	for i in 5:
		flavor[i]=int(total[i])-int(total[(i+1)%5])
		if flavor[i]<0:negative+=1
	for i in 5:flavor[i]=mini(255,roundi(maxi(0,int(flavor[i])-negative)*(100+floori(peak*100/333))/100.0))
	if negative>3 or ingredients.any(func(k):return ingredients.count(k)>1) or not flavor.any(func(v):return v>0):
		flavor.fill(0)
		var indices: Array=[0,1,2,3,4]
		indices.shuffle()
		for i in 3:flavor[indices[i]]=2
	return {"people":ingredients.size(),"berry":ingredients[0],"flavor":flavor,"smooth":maxi(0,floori(float(feel)/ingredients.size())-ingredients.size()),"rpm":peak}

func handle_back() -> void:
	completed.emit({})
	queue_free()
