extends ColorRect
## Single-player Super Contest. The live touch stage owns only the current competition.
signal finished(completed: bool, won: bool)
const Rules := preload("res://core/sinnoh_contests.gd")
const Art := preload("res://core/dex_art.gd")
const ARROWS := ["↑","→","↓","←"]
const INK := Color("#fff2d2")
var g
var mon: Dictionary
var stock: Dictionary
var category: int
var rank: int
var practice: int
var motif: int
var mode: String
var participants := []
const CONDITIONS := [[10,20,30,40,50,60,70,80],[90,110,130,150,170,190,210,230],[170,200,230,260,290,320,350,380],[320,360,400,440,480,520,560,600]]
const ORNAMENTS := [[3,5,8],[5,10,15],[7,15,23],[10,20,30]]
const SCARVES := ["RED_SCARF","BLUE_SCARF","PINK_SCARF","GREEN_SCARF","YELLOW_SCARF"]
var ties := []
var scores := [[0,0,0],[0,0,0],[0,0,0],[0,0,0]]
var order := [0,1,2,3]
var previous := [0,0,0,0]
var doubled := [false,false,false,false]
var previous_round := [0,0,0,0]
var voltage := [0,0,0]
var dress := []
var selected := -1
var page := 0
var timed := 0.0
var dance_round := 0
var beats := []
var taps := {}
var last_flash := -1
var acting_round := 0
var move_id := 0
var notes := ""
var time_label: Label
var dance_label: Label
var portrait: Control
var board := Control.new()

func start(game, entrant: Dictionary, cat: int, difficulty: int, inventory: Dictionary, practice_stage: int) -> void:
	g=game;mon=entrant;stock=inventory;category=cat;rank=difficulty;practice=practice_stage
	color=Color("#193341")
	mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(board);board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var categories: Array=[[2,3,4],[2,3,4,0,1,5],[0,1,2,3,4,5,6,7,8],range(12)][rank]
	motif=categories[g.rng.randi_range(0,categories.size()-1)]
	participants=[{"name":mon.name,"species":mon.species_id,"condition":mon.get("contest_condition",[0,0,0,0,0])+[mon.get("sheen",0)],"moves":mon.moves.filter(func(id):return Rules.data().moves.has(str(int(id))))}]
	var post: bool=g._flags().get("s_champion",false) and g._flags().get("s_national_dex",false)
	var pool: Array=Rules.data().opponents.filter(func(r):return int(r.rank)==rank and int(r.categories)&(1<<category) and not r.display and not r.practice and int(r.special) in ([0,2,3] if post else [0,1]))
	for i in 3:
		var rival: Dictionary=pool.pop_at(g.rng.randi_range(0,pool.size()-1))
		participants.append(rival)
	for i in 4:ties.append(g.rng.randi())
	mode=["dress","dance","moves"][maxi(0,practice)]
	timed=60.0
	if mode=="dance":begin_phrase()
	else:render()
	set_meta("choice_back",func():finish(false))

func label(value: String, x: int, y: int, w: int, h: int, font:=15) -> Label:
	var l:=Label.new();l.text=value;l.position=Vector2(x,y);l.size=Vector2(w,h)
	l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;l.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size",font);l.add_theme_color_override("font_color",INK)
	l.add_theme_constant_override("outline_size",3);l.add_theme_color_override("font_outline_color",Color("#182a38"))
	l.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	board.add_child(l);return l

func button(value: String, at: Rect2, cb: Callable) -> Button:
	var b:=Button.new();b.position=at.position;b.size=at.size;b.text=value
	b.add_theme_font_size_override("font_size",14)
	for key in ["normal","hover","pressed","focus"]:
		var skin:=StyleBoxFlat.new()
		skin.bg_color=Color("#27615f") if key=="pressed" else Color("#264853")
		skin.border_color=Color("#ffd077") if key in ["hover","focus"] else Color("#679795")
		skin.set_border_width_all(1)
		skin.set_corner_radius_all(5)
		b.add_theme_stylebox_override(key,skin)
	b.pressed.connect(cb);board.add_child(b);return b

func image_at(tex: Texture2D, at: Rect2, parent: Control) -> TextureRect:
	var pic:=TextureRect.new();pic.texture=tex;pic.mouse_filter=Control.MOUSE_FILTER_IGNORE
	pic.position=at.position;pic.size=at.size;pic.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;pic.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(pic);return pic

func accessory(id: int) -> AtlasTexture:
	var tex:=AtlasTexture.new();tex.atlas=load("res://assets/platinum/accessories.png")
	tex.region=Rect2((id%10)*40,(id/10)*40,40,40);return tex

func show_photo(saved: Dictionary, cat: int) -> void:
	color=Color("#193341")
	mode="photo"
	mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(board);board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label("%s组　%s级优胜纪念照"%[Rules.CATS[cat],Rules.RANKS[int(saved.rank)]],8,5,464,30,18)
	var audience:=image_at(load("res://assets/contest_audience.png"),Rect2(12,40,456,149),board)
	audience.stretch_mode=TextureRect.STRETCH_SCALE
	var photo_board:=Control.new()
	photo_board.position=Vector2(154,54);board.add_child(photo_board)
	image_at(Art.battle_texture(int(saved.species),saved.form,saved.shiny,false),Rect2(19,10,130,130),photo_board)
	for a in saved.dress:
		var at:=Vector2(float(a.xy[0]),float(a.xy[1]))
		image_at(accessory(int(a.id)),Rect2(at-Vector2(15,15),Vector2(30,30)),photo_board)
	label(saved.name,8,204,464,33,21)
	button("回到会场",Rect2(122,253,236,52),func():finish(false))
	set_meta("choice_back",func():finish(false))

func render() -> void:
	for child in board.get_children():board.remove_child(child);child.queue_free()
	time_label=null;dance_label=null
	var audience := image_at(load("res://assets/contest_audience.png"),Rect2(0,31,480,101),board)
	audience.stretch_mode=TextureRect.STRETCH_SCALE
	var header:=ColorRect.new()
	header.mouse_filter=Control.MOUSE_FILTER_IGNORE
	header.color=Color("#c79b57")
	header.position=Vector2(0,29);header.size=Vector2(480,2);board.add_child(header)
	label("超级华丽大赛　%s组 · %s级"%[Rules.CATS[category],Rules.RANKS[rank]],8,2,356,23,17)
	button("离场",Rect2(407,3,63,29),func():finish(false))
	match mode:
		"dress":draw_dress()
		"dance":draw_dance()
		"moves","judges","round":draw_acting()
		"results":
			var positions:=standings()
			var winner: Dictionary=participants[positions[0]]
			image_at(Art.battle_texture(winner.species,mon.get("form","") if positions[0]==0 else "",mon.get("shiny",false) if positions[0]==0 else false,false),Rect2(193,57,94,69),board)
			for i in 4:
				var p: int=positions[i]
				label("%d　%s　　装扮 %d　舞蹈 %d　演技 %d"%[i+1,participants[p].name,scores[p][0],scores[p][1],scores[p][2]],10,134+i*27,458,26)
			button("回到会场",Rect2(130,263,220,44),func():finish(true))

func draw_dress() -> void:
	time_label=label("",7,32,462,24)
	portrait=Control.new();portrait.position=Vector2(14,69);portrait.size=Vector2(170,148)
	board.add_child(portrait)
	image_at(Art.battle_texture(mon.species_id,mon.get("form",""),mon.get("shiny",false),false),Rect2(19,10,130,130),portrait)
	portrait.gui_input.connect(func(ev):
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and ev.pressed and selected>=0 and dress.size()<5*(rank+1):
			var used:=dress.filter(func(a):return a.id==selected).size()
			if used<int(stock.get(str(selected),0)):
				dress.append({"id":selected,"at":ev.position});accept_event();render())
	for a in dress:image_at(accessory(a.id),Rect2(a.at-Vector2(15,15),Vector2(30,30)),portrait)
	var ids:=stock.keys()
	var offset: int=page*6
	for j in mini(6,maxi(0,ids.size()-offset)):
		var id:=int(ids[offset+j])
		var b:=button(str(Rules.data().accessories[id]),Rect2(187+(j%2)*141,60+(j/2)*48,138,43),func():selected=id;render())
		b.icon=accessory(id);b.expand_icon=true;b.modulate=Color("#ffdb8b") if selected==id else Color.WHITE
	label("点选饰品，再点宝可梦摆放",180,211,286,22,13)
	button("撤回",Rect2(12,254,85,49),func():if not dress.is_empty():dress.pop_back();render())
	button("换页",Rect2(104,254,87,49),func():page=(page+1)%maxi(1,ceili(ids.size()/6.0));render())
	button("完成装扮",Rect2(210,254,254,49),finish_dress)

func finish_dress() -> void:
	if mode!="dress":return
	for i in 4:
		var cond: Array=participants[i].condition
		var val := int(cond[category])+int((int(cond[(category+1)%5])+int(cond[(category+4)%5])+int(cond[5]))/2.0)
		var ornament: Array=dress.map(func(a):return a.id) if i==0 else Rules.data().outfits[int(participants[i].outfits[motif])]
		var bonus:=0
		for id in ornament:bonus+=int(Rules.data().themes[motif][int(id)])
		if i==0:
			var scarf:=SCARVES.find(mon.get("held",""))
			if scarf==category:val=val*110/100
			elif scarf in [(category+1)%5,(category+4)%5]:val=val*105/100
		var hearts: int=CONDITIONS[rank].filter(func(bound):return val>=bound).size()
		if bonus>0:hearts+=1+ORNAMENTS[rank].filter(func(bound):return bonus>bound).size()
		scores[i][0]=hearts
	if practice==0:mode="results";render();return
	mode="dance";begin_phrase()

func begin_phrase() -> void:
	if dance_round>=8:
		mode="results" if practice==1 else "moves";render();return
	beats=[];taps={};last_flash=-1
	for i in (4 if rank>=2 else 3):beats.append(g.rng.randi_range(0,3))
	timed=0;render()

func beat_time() -> float:return [0.74,0.65,0.58,0.51][rank]

func draw_dance() -> void:
	var leader: int=(dance_round/2+1)%4
	label("领舞　%s　·　第 %d / 8 段"%[participants[leader].name,dance_round+1],4,33,468,28)
	for i in 4:
		var entrant: Dictionary=participants[i]
		image_at(Art.battle_texture(entrant.species,mon.get("form","") if i==0 else "",mon.get("shiny",false) if i==0 else false,false),Rect2(19+i*115,60,91,68),board)
	dance_label=label("准备",4,138,468,50,26)
	label("跟随节拍按方向；轮到你领舞时，自由编排舞步。",4,190,468,24,14)
	for j in 4:button(ARROWS[j],Rect2(11+j*116,239,109,61),func():tap(j))

func tap(dir: int) -> void:
	var player_leads:=dance_round/2==3
	var beat:=roundi((timed-0.9)/beat_time())-(0 if player_leads else beats.size()+1)
	if beat<0 or beat>=beats.size() or taps.has(beat):return
	var offset:=absf((timed-0.9)/beat_time()-(beat if player_leads else beat+beats.size()+1))
	taps[beat]=dir
	if player_leads:beats[beat]=dir
	if beats[beat]==dir and offset<=0.45:scores[0][1]+=2 if offset<=0.24 else 1
	dance_label.text=ARROWS[dir]

func _process(dt: float) -> void:
	if mode=="dress":
		timed-=dt
		if time_label:time_label.text="主题　%s　　饰品 %d/%d　　%02d 秒"%[Rules.THEMES[motif],dress.size(),5*(rank+1),maxi(0,ceili(timed))]
		if timed<=0:finish_dress()
	if mode!="dance":return
	timed+=dt
	var t: int=roundi((timed-0.9)/beat_time())
	if t!=last_flash and is_instance_valid(dance_label):
		last_flash=t
		var n:=beats.size()
		if t>=0 and t<n:dance_label.text="你来领舞　♪" if dance_round/2==3 else "领舞　"+ARROWS[beats[t]]
		elif t>=n+1 and t<=2*n:dance_label.text="跟跳　♪" if dance_round/2!=3 else "伴舞　"+ARROWS[beats[t-n-1]]
		else:dance_label.text="准备　♪"
		if t>2*n:
			for i in range(1,4):
				for j in n:
					if g.rng.randf()<0.48+0.10*rank:scores[i][1]+=2
			dance_round+=1;begin_phrase()

func legal_moves(slot: int) -> Array:
	var moves: Array=participants[slot].moves.filter(func(id):return Rules.data().moves.has(str(int(id))))
	var available:=moves.filter(func(id):return int(id)!=int(previous[slot]) or Rules.data().moves[str(int(id))][1]=="CONSECUTIVE_USE")
	return moves if available.is_empty() else available

func draw_acting() -> void:
	label("演技　%d / 4　　评审热度　%d　%d　%d"%[mini(4,acting_round+1),voltage[0],voltage[1],voltage[2]],8,31,464,28)
	for i in 4:
		var a: Dictionary=participants[i]
		image_at(Art.battle_texture(a.species,mon.get("form","") if i==0 else "",mon.get("shiny",false) if i==0 else false,false),Rect2(21+i*116,60,84,56),board)
		label(a.name,3+i*116,117,112,21,13)
	if mode=="moves":
		var moves:=legal_moves(0)
		for j in moves.size():
			var mid:=int(moves[j]);var profile: Array=Rules.data().moves[str(mid)]
			button("%s　%s　♡%d"%[g.get_node("/root/Data").move_of(mid).name,Rules.CATS[int(profile[0])],profile[2]],Rect2(10+(j%2)*231,169+(j/2)*62,225,56),func():move_id=mid;mode="judges";render())
	elif mode=="judges":
		for j in 3:button("%s　%d/5"%[Rules.JUDGES[j],voltage[j]],Rect2(9+j*155,202,150,58),func():perform(j))
	elif mode=="round":
		label(notes,8,164,464,45,14)
		button("公布结果" if acting_round==4 else "下回合",Rect2(105,248,270,49),func():mode="results" if acting_round==4 else "moves";render())

func perform(judge: int) -> void:
	var choices := [move_id]
	var judges := [judge]
	for i in range(1,4):
		var possible:=legal_moves(i)
		choices.append(int(possible[g.rng.randi_range(0,possible.size()-1)]));judges.append(g.rng.randi_range(0,2))
	var gained := [0,0,0,0]
	var priority := [0,0,0,0]
	var no_up:=false
	var no_down:=false
	var last_up:=false
	var peak_bonus:=0
	for k in order.size():
		var i: int=order[k]
		var j: int=judges[i]
		var move: Array=Rules.data().moves[str(choices[i])]
		var effect: String=move[1]
		var relation: int=(int(move[0])-category+5)%5
		var delta:=1 if relation==0 else (-1 if relation in [2,3] else 0)
		var points:=int(move[2])
		match effect:
			"DOUBLED_JUDGE":points+=2*(judges.count(j)-1)
			"2_HEARTS_WHEN_VOLTAGE_UP":if delta==1:points+=2
			"UNIQUE_JUDGE":if judges.count(j)==1:points+=3
			"VOLTAGE":points+=int(voltage[j])
			"ALL_SAME_JUDGE":if judges.count(j)==4:points+=15
			"LOWERS_VOLTAGE":for h in 3:voltage[h]=maxi(0,int(voltage[h])-1)
			"STEAL_VOLTAGE":points+=peak_bonus
			"SUPPRESS_VOLTAGE":no_up=true
			"NO_VOLTAGE_DOWN":no_down=true
			"FIRST_NEXT_TURN":priority[i]=-1
			"LAST_NEXT_TURN":priority[i]=1
			"RANDOM_ORDER":priority[i]=g.rng.randi_range(-1,1)
			"DOUBLE_FINAL_ACT":if k==3:points*=2
			"LOW_VOLTAGE_ADVANTAGE":points+=maxi(0,4-int(voltage[j]))
			"FIRST_PERFORMANCE_ADVANTAGE":if k==0:points+=2
			"FINAL_PERFORMANCE_ADVANTAGE":if k==3:points+=2
			"TWO_VOLTAGE_IN_A_ROW_ADVANTAGE":if last_up and delta==1:points+=3
			"HIGH_SCORE_LATER_TURN":points+=k+1
			"MAX_VOLTAGE_ADVANTAGE":if peak_bonus>=5:points+=3
		if doubled[i]:points*=2
		doubled[i]=effect=="DOUBLE_NEXT_TURN"
		if (delta>0 and not no_up) or (delta<0 and not no_down):voltage[j]=maxi(0,int(voltage[j])+delta)
		peak_bonus=0
		if int(voltage[j])>=5:
			peak_bonus=8 if j==1 else 5
			points+=peak_bonus
			voltage[j]=0
		last_up=delta==1 and not no_up
		gained[i]=points
	for i in 4:
		gained[i]+=[0,3,2,1,0][judges.count(judges[i])]
	var lowest: int=gained.min()
	for i in 4:
		if gained[i]==lowest and Rules.data().moves[str(choices[i])][1]=="PITY_POINTS":gained[i]+=3
		scores[i][2]+=gained[i]
	previous_round=gained;previous=choices;acting_round+=1
	order.sort_custom(func(a,b):return [priority[a],gained[a],a]<[priority[b],gained[b],b])
	notes="%s 得到 %d 颗心。下一轮先后　%s"%[mon.name,gained[0],"、".join(order.map(func(i):return participants[i].name))]
	mode="round";render()

func standings() -> Array:
	var rows := [0,1,2,3]
	rows.sort_custom(func(a,b):return total(a)>total(b) if total(a)!=total(b) else ties[a]>ties[b])
	return rows

func total(i: int) -> int:
	var sum:=0
	for phase in 3:
		var peak:int=0
		for j in 4:peak=maxi(peak,int(scores[j][phase]))
		if peak==0:continue
		var weight:=3333 if practice<0 else 10000
		var pixels:=64 if practice<0 else 192
		var scale:=weight/peak
		var result: int=(int(scores[i][phase])*scale+50)/100
		var best: int=(peak*scale+50)/100
		if best>0:sum+=pixels*(100*result/best)/100
	return sum

func finish(completed: bool) -> void:
	mode="done";finished.emit(completed,completed and standings()[0]==0)
