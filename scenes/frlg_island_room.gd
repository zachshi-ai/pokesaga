extends "res://scenes/berry_press.gd"
## Uses the same local ENet room transport as Berry Crush. The host advances the
## vine or shared fruit columns and sends the final scores and prize to each peer.
signal settled(points: int, streak: int, prize: String, quantity: int)
const Arcade:=preload("res://scenes/frlg_island_games.gd")
var game_kind: String
var species: int
var random: RandomNumberGenerator
var arena
var members: Array=[]
var state: Dictionary={}
var jump_at: Dictionary={}
var scores: Dictionary={}
var streaks: Dictionary={}
var bests: Dictionary={}
var queued_result: Dictionary={}
var update_in:=0.0
var turn:=0
var outstanding:=[]
var confirm_button: Button
var receipt_timeout:=0.0

func launch(kind: String,sid: int,rng: RandomNumberGenerator) -> void:
	game_kind=kind
	species=sid
	random=rng
	setup(str(sid))

func title() -> String:
	return "宝可梦跳绳" if game_kind=="jump" else "嘟嘟利摘树果"

func port_number() -> int:
	return 25744 if game_kind=="jump" else 25745

func menu() -> void:
	clear_panel()
	phase="menu"
	label_for(title(),18)
	hint=label_for("带着伙伴参加两岛游戏角",13)
	action("与工作人员练习",practice)
	action("同一 Wi-Fi · 创建房间",host_room)
	action("同一 Wi-Fi · 加入房间",join_menu)
	action("离开",func():leave(0))

func join_menu() -> void:
	clear_panel()
	phase="address"
	label_for("加入"+title(),18)
	hint=label_for("输入同伴屏幕上的房间地址",13)
	address=LineEdit.new()
	address.placeholder_text="192.168.1.100"
	layout.add_child(address)
	action("连接",func():join_room(address.text.strip_edges()))
	action("返回",menu)

func lobby() -> void:
	clear_panel()
	phase="lobby"
	label_for(title(),18)
	if role=="host":
		var ips:=Array(IP.get_local_addresses()).filter(func(ip):return ip.is_valid_ip_address() and not ":" in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."))
		label_for("房间地址　"+"　".join(ips),12)
	hint=label_for("等待同伴加入…",14)
	if role=="host":action("全员开始",begin)
	action("退出房间",func():leave(0))

func refresh_lobby() -> void:
	hint.text="已就位 %d / 5 人"%players.size()
	send(0,{"type":"lobby","count":players.size()})

func new_arena(online: bool) -> void:
	layout.hide()
	arena=Arcade.new()
	arena.name="Play"
	add_child(arena)
	var jumpers: Dictionary=preload("res://core/frlg_sidequests.gd").data().jumpers
	arena.setup(game_kind,species,jumpers.get(str(species),"NORMAL"),random)
	arena.online=online
	if online:
		arena.set_process(false)
		arena.running=true
		arena.hint.text="在藤蔓落下前共同起跳。" if game_kind=="jump" else "左、中、右各能啄一列树果。两侧邻列和队友共享。"
		arena.input_slot.connect(press_online)
		arena.completed.connect(func(_p,_n):
			if role=="host":end_game()
			else:send(1,{"type":"end"}))
	else:
		arena.completed.connect(func(p,n):result_for(p,n,prize_for(p),1))

func practice() -> void:
	role="practice"
	phase="arena"
	new_arena(false)

func begin() -> void:
	if role!="host" or phase!="lobby":return
	if players.size()<2:
		hint.text="至少需要两位玩家。"
		return
	members=players.keys()
	members.sort()
	# On a two-human berry run a third, local Dodrio covers the vacant station.
	if game_kind=="dodrio" and members.size()==2:
		members.append(0)
		players[0]="85"
	var mons: Array=[]
	for id in members:mons.append(int(players[id]))
	send(0,{"type":"start","ids":members,"mons":mons})
	enter_online(members,mons)

func enter_online(ids: Array,mons: Array) -> void:
	members=[]
	for i in ids.size():
		members.append(int(ids[i]))
		players[int(ids[i])]=str(mons[i])
	state={"t":0.0,"cycle":1.65,"misses":0,"score":0,"streak":0,"checked":false,"fruit":[]}
	for id in members:
		jump_at[id]=-2.0
		scores[id]=0
		streaks[id]=0
		bests[id]=0
	if game_kind=="dodrio":
		for i in members.size()*2:
			state.fruit.append([-0.13*(i%4),random.randi_range(0,2)])
	phase="arena"
	new_arena(true)
	var neighbor:int=members[(members.find(my_id())+1)%members.size()]
	arena.companion=load(Data.sprite_path(int(players[neighbor])))
	view_for(my_id())

func my_id() -> int:
	return wire.get_unique_id() if role=="client" and wire else 1

func press_online(slot: int) -> void:
	if role=="client":send(1,{"type":"button","slot":slot,"turn":turn})
	else:apply_press(1,slot)

func air_for(id: int) -> float:
	var key: String=preload("res://core/frlg_sidequests.gd").data().jumpers.get(str(players[id]),"NORMAL")
	return {"FAST":0.58,"SLOW":0.87}.get(key,0.72)

func apply_press(id: int,slot: int) -> void:
	if phase!="arena" or not members.has(id) or slot not in [0,1,2]:return
	if game_kind=="jump":
		if state.t-float(jump_at[id])>=air_for(id):jump_at[id]=state.t
	else:
		var col: int=(members.find(id)*2+slot)%state.fruit.size()
		var fruit: Array=state.fruit[col]
		if fruit[0]>=0.7 and fruit[0]<1.0:
			scores[id]+=[10,30,50][int(fruit[1])]
			streaks[id]+=1
			bests[id]=maxi(int(streaks[id]),int(bests[id]))
			fruit[0]=-random.randf_range(0.24,0.72)
			fruit[1]=random.randi_range(0,2)

func advance(delta: float) -> void:
	state.t+=delta
	if game_kind=="jump":
		if state.t>=float(state.cycle)*0.85 and not state.checked:
			state.checked=true
			var peaks:=0
			for id in members:
				var arc: float=(state.t-float(jump_at[id]))/air_for(id)
				if arc<=0 or arc>=1:
					end_game()
					return
				if absf(arc-0.5)<0.15:peaks+=1
			state.score+=10+[0,0,50,100,200,500][peaks]
			state.streak+=1
		if state.t>=state.cycle:
			state.t=0.0
			state.checked=false
			update_in=0.0
			state.cycle=maxf(0.72,float(state.cycle)-0.018)
			turn+=1
			for id in members:jump_at[id]=-2.0
	else:
		for i in state.fruit.size():
			var fruit: Array=state.fruit[i]
			fruit[0]+=delta/(1.65-minf(0.85,float(turn)/150))
			if fruit[0]>=1.0:
				fruit[0]=-random.randf_range(0.12,0.8)
				fruit[1]=random.randi_range(0,2)
				state.misses+=1
				var owner:int=members[i/2]
				scores[owner]=maxi(0,int(scores[owner])-50)
				streaks[owner]=0
				if state.misses>=10:
					end_game()
					return
		if members.has(0):
			for slot in 3:
				var col: int=(members.find(0)*2+slot)%state.fruit.size()
				if state.fruit[col][0]>=0.91:apply_press(0,slot)
		if state.t>=1.0:state.t-=1.0;turn+=1
	update_in-=delta
	if update_in<=0:
		update_in=0.035
		for id in members:
			if id==0:continue
			var v:=view_for(id)
			if id!=1:send(id,{"type":"view","v":v})

func view_for(id: int) -> Array:
	var index:=members.find(id)
	var friend:int=members[(index+1)%members.size()]
	var berries: Array=[]
	if game_kind=="dodrio":
		for i in 3:
			var fruit: Array=state.fruit[(index*2+i)%state.fruit.size()]
			berries.append([i,fruit[0],fruit[1]])
	var other_arc:=maxf(0,sin(clampf((float(state.t)-float(jump_at[friend]))/air_for(friend),0,1)*PI))
	var view:=[state.t,state.cycle,jump_at[id],other_arc, state.score if game_kind=="jump" else scores[id],state.streak if game_kind=="jump" else streaks[id],state.misses,berries,turn]
	if id==1:show_view(view)
	return view

func show_view(v: Array) -> void:
	arena.elapsed=v[0]
	arena.cycle=v[1]
	arena.takeoff=v[2]
	arena.friend_height=v[3]
	arena.score=int(v[4])
	arena.streak=int(v[5])
	arena.misses=int(v[6])
	arena.network_berries=v[7]
	turn=int(v[8])
	arena.update_hud()
	arena.queue_redraw()

func prize_for(points: int) -> Array:
	var amount:=0
	var pool:=["razz","bluk","nanab","wepear","pinap"]
	if game_kind=="jump":
		pool=["leppa","lum","sitrus","figy","wiki","mago","aguav","iapapa"]
		for threshold in [5000,8000,12000,16000,20000]:
			if points>=threshold:amount+=1
	elif points>=3000:
		amount=1
		if members.size()==4:pool=["pomeg","kelpsy","qualot","hondew","grepa","tamato","cornn","magost","rabuta","nomel"]
		if members.size()==5:pool=["spelon","pamtre","watmel","durin","belue"]
	return [pool[random.randi_range(0,pool.size()-1)] if amount else "",amount]

func end_game() -> void:
	if phase!="arena" or role!="host":return
	var best: int=state.score if game_kind=="jump" else scores.values().max()
	var prize:=prize_for(best)
	for id in members:
		if id in [0,1]:continue
		var p: int=state.score if game_kind=="jump" else scores[id]
		outstanding.append(id)
		send(id,{"type":"result","p":p,"streak":state.streak if game_kind=="jump" else bests[id],"prize":prize if p==best else ["",0],"top":best})
	var p: int=state.score if game_kind=="jump" else scores[1]
	result_for(p,state.streak if game_kind=="jump" else bests[1],prize if p==best else ["",0],best)

func result_for(points: int,combo: int,prize: Array,highest: int) -> void:
	if phase!="arena":return
	phase="result"
	if is_instance_valid(arena):arena.hide();arena.queue_free()
	queued_result={"points":points,"combo":combo,"prize":prize[0],"amount":prize[1]}
	layout.show()
	clear_panel()
	label_for(title(),18)
	label_for("得分 %d　最长连续 %d"%[points,combo],15)
	if role!="practice" and game_kind=="dodrio":label_for("全场最高 %d"%highest,14)
	if int(prize[1])>0:label_for("%s ×%d"%[Data.berry_name(prize[0]),prize[1]],14)
	confirm_button=action("登记成绩",func():leave(0))
	if role=="host" and not outstanding.is_empty():
		confirm_button.disabled=true
		receipt_timeout=4.0

func leave(_reward: int) -> void:
	if phase=="closed":return
	var result:=queued_result
	phase="closed"
	if wire:wire.close();wire=null
	settled.emit(int(result.get("points",0)),int(result.get("combo",0)),str(result.get("prize","")),int(result.get("amount",0)))
	hide()
	queue_free()

func fail(message: String) -> void:
	if phase in ["closed","error","result"]:return
	if is_instance_valid(arena):arena.hide();arena.queue_free()
	layout.show()
	if role=="host" and wire:send(0,{"type":"abort"})
	phase="error"
	clear_panel()
	label_for(message,14)
	action("离开",func():leave(0))

func peer_left(id: int) -> void:
	if phase=="arena":fail("有同伴离开，比赛中止。")
	elif phase=="lobby":
		players.erase(id)
		refresh_lobby()

func _process(delta: float) -> void:
	super._process(delta)
	if phase=="result" and role=="host" and is_instance_valid(confirm_button) and confirm_button.disabled:
		receipt_timeout-=delta
		confirm_button.disabled=not outstanding.is_empty() and receipt_timeout>0
	if phase!="arena":return
	if role=="host":advance(delta)
	elif role=="client" and wire.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED:fail("房间已关闭。")

func receive(id: int,packet: Dictionary) -> void:
	var kind: String=packet.get("type","")
	if role=="host":
		if kind=="receipt" and phase=="result":outstanding.erase(id)
		elif kind=="join":
			var sid:=str(packet.get("berry","")).to_int()
			var valid: bool=preload("res://core/frlg_sidequests.gd").data().jumpers.has(str(sid)) if game_kind=="jump" else sid==85
			if phase!="lobby" or not valid:
				send(id,{"type":"abort"})
				return
			players[id]=str(sid)
			refresh_lobby()
		elif phase=="arena" and members.has(id):
			if kind=="button" and (game_kind=="dodrio" or int(packet.get("turn",-1))==turn):apply_press(id,int(packet.get("slot",-1)))
			elif kind=="end":end_game()
	elif role=="client" and id==1:
		match kind:
			"lobby":if phase=="lobby":hint.text="已就位 %d / 5 人"%int(packet.get("count",0))
			"start":
				if phase=="lobby" and packet.get("ids",[]) is Array and packet.get("mons",[]) is Array and packet.ids.size()==packet.mons.size() and packet.ids.size() in range(2,6):enter_online(packet.ids,packet.mons)
			"view":
				if phase=="arena" and packet.get("v",[]) is Array and packet.v.size()==9:show_view(packet.v)
			"result":
				if phase=="arena" and packet.get("prize",[]) is Array and packet.prize.size()==2:
					send(1,{"type":"receipt"})
					result_for(int(packet.p),int(packet.streak),packet.prize,int(packet.top))
			"abort":fail("比赛中止，请回柜台重新组队。")
