extends Control

signal closed
signal settled(delta: int, best: int)
const UI := preload("res://core/field_ui.gd")
const STRIPS := [[1,4,2,0,3,5,1,4,2,6,0,5],[2,1,5,0,4,2,6,1,3,0,4,5],[4,2,1,0,6,4,3,2,5,1,0,3]]
const PAY := [0,15,10,6,2,2,2]
const LANES := ["左轮","中轮","右轮"]
var rng: RandomNumberGenerator
var rank: int
var balance: int
var best: int
var rounds:=0
var spins:=0
var in_bonus:=false
var playing:=false
var chance:=false
var right_order:=true
var round_misses:=0
var tops:=[0,0,0]
var stops: Array=[]
var order: Array=[]
var tick:=0.0
var hint: Label
var wallet: Label
var action: Button
var lane_buttons: Array=[]
var clefairy: TextureRect
var icons: Texture2D=preload("res://assets/emerald/fr_reel_icons.png")
var screen: Control

func setup(coins: int,record: int,machine: int,grade: int,random: RandomNumberGenerator) -> void:
	rng=random
	rank=grade
	balance=coins
	best=record
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	screen=UI.sheet(self)
	UI.header(screen,"帷幕游戏厅　%02d 号机"%(machine+1),"",handle_back)
	var canvas:=Control.new()
	UI.place(screen,canvas,0,45,size.x,size.y-145)
	canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(func():draw_reels(canvas))
	canvas.name="ReelDisplay"
	clefairy=UI.portrait(35)
	UI.place(screen,clefairy,4,49,55,55)
	wallet=UI.label("",13)
	UI.place(screen,wallet,10,size.y-103,size.x-20,24)
	hint=UI.label("按开始，每局投入 3 枚。依次停下左、中、右轮。",14)
	UI.place(screen,hint,10,size.y-80,size.x-20,28)
	var w:=(size.x-32)/4
	action=UI.button("开始",start_spin,true)
	UI.place(screen,action,8,size.y-48,w,40)
	for i in 3:
		var b:=UI.button(LANES[i],stop_lane.bind(i))
		UI.place(screen,b,12+(w+4)*(i+1),size.y-48,w,40)
		lane_buttons.append(b)
	refresh()

func refresh() -> void:
	wallet.text="代币 %d / 50000　　连续奖励 %d 轮　　最高 %d 轮"%[balance,rounds,best]
	action.disabled=playing or balance<(1 if in_bonus else 3)
	action.text="奖励局 · 1" if in_bonus else "开始 · 3"
	clefairy.visible=chance or in_bonus
	for i in 3:lane_buttons[i].disabled=not playing or stops.has(i) or (not in_bonus and i!=stops.size())
	screen.get_node("ReelDisplay").queue_redraw()

func start_spin() -> void:
	if playing:return
	var cost:=1 if in_bonus else 3
	if balance<cost:return
	balance-=cost
	settled.emit(-cost,best)
	playing=true
	chance=in_bonus or rng.randi_range(0,15-rank)==0
	stops=[]
	order=[0,1,2]
	for i in 3:tops[i]=rng.randi_range(0,STRIPS[i].size()-1)
	if in_bonus:
		for i in [2,1]:
			var j:=rng.randi_range(0,i)
			var tmp=order[i]
			order[i]=order[j]
			order[j]=tmp
		hint.text="奖励 %d / 15　皮皮指向%s。"%[spins+1,LANES[order[0]]]
	else:hint.text="皮皮出现了！瞄准红七。" if chance else "先按左轮，在亮线处对齐图案。"
	right_order=true
	refresh()

func stop_lane(i: int) -> void:
	if not playing or i in stops or (not in_bonus and i!=stops.size()):return
	if in_bonus:
		if i!=order[stops.size()]:right_order=false
		# Clefairy's directions line up the Replay symbols throughout the bonus.
		if right_order:tops[i]=STRIPS[i].find(1)
	elif chance:
		for jump in 4:
			var n: int=(tops[i]+jump)%STRIPS[i].size()
			if STRIPS[i][n]==0:
				tops[i]=n
				break
	stops.append(i)
	if stops.size()==3:resolve_spin()
	elif in_bonus:hint.text="皮皮指向%s。"%LANES[order[stops.size()]]
	refresh()

func resolve_spin() -> void:
	playing=false
	var coins:=0
	if in_bonus:
		spins+=1
		coins=15 if right_order else 0
		if not right_order:round_misses+=1
		hint.text="跟对了，获得 15 枚！" if right_order else "停轮顺序错了。"
		if spins==15:
			rounds+=1
			best=maxi(best,rounds)
			spins=0
			in_bonus=round_misses==0 or rng.randi_range(0,14)>=round_misses
			round_misses=0
			hint.text="皮皮还想再玩一轮！" if in_bonus else "皮皮离开了。连续完成 %d 轮。"%rounds
			if not in_bonus:rounds=0
	else:
		var a: int=STRIPS[0][tops[0]]
		if a==STRIPS[1][tops[1]] and a==STRIPS[2][tops[2]]:
			if a==0:
				in_bonus=true
				spins=0
				rounds=0
				round_misses=0
			else:coins=PAY[a]
		hint.text="红七对齐了！跟随皮皮的指示开始奖励局。" if in_bonus else ("获得 %d 枚。"%coins if coins else "这一局没有对齐。")
	balance=mini(50000,balance+coins)
	settled.emit(coins,best)
	chance=false

func _process(dt: float) -> void:
	if not playing:return
	tick+=dt
	while tick>=0.095:
		tick-=0.095
		for i in 3:
			if not i in stops:tops[i]=(int(tops[i])+1)%STRIPS[i].size()
	screen.get_node("ReelDisplay").queue_redraw()

func draw_reels(canvas: Control) -> void:
	var tile:=minf(canvas.size.y/3.1,canvas.size.x/5.0)
	if tile<1:return
	var origin:=(canvas.size-Vector2(3,3)*tile)*0.5
	for i in 3:
		for row in 3:
			var pos:=Rect2(origin+Vector2(i,row)*tile,Vector2.ONE*tile)
			var icon: int=STRIPS[i][posmod(int(tops[i])+row-1,STRIPS[i].size())]
			canvas.draw_rect(pos.grow(-1),Color("#f2e7c0") if row==1 else Color("#cfddd1"))
			canvas.draw_texture_rect_region(icons,pos.grow(-4),Rect2(0,icon*32,32,32))
	canvas.draw_rect(Rect2(origin+Vector2(0,tile),Vector2(3,1)*tile),Color("#ac5947"),false,2)

func handle_back() -> bool:
	if not is_queued_for_deletion():
		closed.emit()
		queue_free()
	return true
