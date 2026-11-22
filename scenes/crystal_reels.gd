extends ColorRect
signal finished(coins:int)
const REELS:=["025340253412534","032451324513245","032453245312453"]
const SYMBOLS:=["７","精灵球","樱桃","皮卡丘","杰尼龟","海星星"]
const PAY:=[300,50,6,8,10,15]
var stops: Array=[]
var bands: Array[Label]=[]
var locked:=0
var bet:=1
var elapsed:=0.0
var stop_button:Button

func setup(size_bet:int,rng:RandomNumberGenerator):
	bet=size_bet
	color=Color("#203039")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title:=Label.new();title.position=Vector2(32,22);title.text="转轮　%d 枚"%bet;add_child(title)
	var grid:=HBoxContainer.new();grid.position=Vector2(32,71);add_child(grid)
	for i in 3:
		stops.append(rng.randi_range(0,14))
		var l:=Label.new();l.custom_minimum_size=Vector2(125,126);l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(l);bands.append(l)
	stop_button=Button.new();stop_button.position=Vector2(32,238);stop_button.size=Vector2(400,64)
	stop_button.pressed.connect(stop);add_child(stop_button);redraw()

func symbol(reel:int,delta:int)->int:
	return int(REELS[reel][posmod(int(stops[reel])+delta,15)])

func redraw():
	for i in 3:
		bands[i].text="%s\n【%s】\n%s"%[SYMBOLS[symbol(i,-1)],SYMBOLS[symbol(i,0)],SYMBOLS[symbol(i,1)]]
		bands[i].modulate=Color("#f6cf7c") if i<locked else Color.WHITE
	stop_button.text="停下第%d轮"%mini(3,locked+1)

func _process(delta:float):
	if locked>=3:return
	elapsed+=delta
	if elapsed<0.10:return
	var ticks:=int(elapsed/0.10)
	elapsed=fmod(elapsed,0.10)
	for i in range(locked,3):stops[i]=posmod(int(stops[i])+ticks,15)
	redraw()

func stop():
	if locked>=3:return
	locked+=1
	redraw()
	if locked<3:return
	var lines:=[[0,0,0]]
	if bet>=2:lines.append_array([[-1,-1,-1],[1,1,1]])
	if bet==3:lines.append_array([[-1,0,1],[1,0,-1]])
	var reward:=0
	for line in lines:
		var first:=symbol(0,line[0])
		if first==symbol(1,line[1]) and first==symbol(2,line[2]):reward=maxi(reward,PAY[first])
	finished.emit(reward)
