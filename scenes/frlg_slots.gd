extends Control
signal closed
signal paid(coins: int)
const LINES := [[0,1,2,3],[0,0,0,2],[1,1,1,1],[2,2,2,2],[2,1,0,3]]
const VALUES := [300,100,15,15,0,8,8]
var reels: Array
var tops: Array=[]
var bet:=0
var stop_count:=0
var wager: Button
var stop: Button
var balance:=0
var hint:=Label.new()
var pictures: Texture2D
var tick:=0.0

func setup(strips: Array,coins: int,rng: RandomNumberGenerator) -> void:
	reels=strips
	balance=coins
	pictures=load("res://assets/emerald/fr_reel_icons.png")
	for strip in strips:tops.append(rng.randi_range(0,strip.size()-1))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top=12
	hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var bar:=HBoxContainer.new()
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top=-54
	bar.offset_bottom=-8
	bar.alignment=BoxContainer.ALIGNMENT_CENTER
	wager=button(bar,"投入代币",add_bet)
	stop=button(bar,"启动",spin)
	button(bar,"离开",handle_back)
	refresh()

func button(bar: Control,label: String,callback: Callable) -> Button:
	var b:=Button.new()
	b.text=label
	b.custom_minimum_size=Vector2(94,38)
	bar.add_child(b)
	b.pressed.connect(callback)
	return b

var running:=false
func add_bet() -> void:
	if running or balance<=0 or bet>=3:return
	bet+=1
	balance-=1
	paid.emit(-1)
	refresh()

func refresh() -> void:
	hint.text="代币 %d　已投入 %d / 3　%s"%[balance,bet,"中央横线" if bet<=1 else ("三条横线" if bet==2 else "五条连线")]
	wager.disabled=running or balance<=0 or bet>=3
	stop.disabled=not running and bet==0
	stop.text="停止第%d轮"%(stop_count+1) if running else "启动"
	queue_redraw()

func spin() -> void:
	if not running:
		if bet==0:return
		running=true
		stop_count=0
	else:
		stop_count+=1
		if stop_count==3:
			running=false
			var coins:=payout()
			balance=mini(9999,balance+coins)
			if coins>0:paid.emit(coins)
			bet=0
			refresh()
			hint.text="这次得到 %d 枚，代币盒里有 %d 枚。"%[coins,balance]
			return
	refresh()

func symbol(col: int,row: int) -> int:
	return int(reels[col][(int(tops[col])+row)%reels[col].size()])

func payout() -> int:
	var result:=0
	for line in LINES:
		if bet<int(line[3]):continue
		var a:=symbol(0,line[0])
		var b:=symbol(1,line[1])
		if a==4:result+=6 if b==4 else 2
		elif a==b and a==symbol(2,line[2]):result+=VALUES[a]
	return result

func _process(dt: float) -> void:
	if not running:return
	tick+=dt
	while tick>=0.072:
		tick-=0.072
		for i in range(stop_count,3):tops[i]=(int(tops[i])+1)%reels[i].size()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("#3f394a"))
	if tops.size()!=3:return
	var tile:=minf(size.y*0.19,size.x*0.20)
	var origin:=(size-Vector2(tile*3,tile*3))*0.5
	for i in 3:
		for j in 3:
			var pos:=Rect2(origin+Vector2(i,j)*tile,Vector2.ONE*tile)
			draw_rect(pos.grow(-2),Color("#d9ddd7") if i<stop_count or not running else Color("#f1f3e3"))
			if pictures:draw_texture_rect_region(pictures,pos.grow(-6),Rect2(0,symbol(i,j)*32,32,32))

func handle_back() -> void:
	if is_queued_for_deletion():return
	closed.emit()
	queue_free()
