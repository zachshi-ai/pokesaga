extends "res://scenes/berry_press.gd"
signal departed(won: bool, played: bool)
const Party:=preload("res://core/party.gd")
const Battle:=preload("res://core/battle.gd")
var entrant: Array=[]
var foe_id:=0
var foe: Array=[]
var engine
var choices: Dictionary={}
var round_id:=0
var winner:=""
var committed:=false
var received_end:=false
var seen_receipt:=false
var claim: Button

func launch(mon: Dictionary) -> void:
	entrant=[int(mon.species_id),int(mon.level),str(mon.form),mon.moves.duplicate(),str(mon.get("held","")),Party.shiny_kind(mon)]
	setup("")

func join_payload() -> Dictionary:return {"type":"join","mon":entrant}
func port_number() -> int:return 25746

func menu() -> void:
	clear_panel()
	phase="menu"
	label_for("通信单打 · 一对一",18)
	hint=label_for("双方各选一只伙伴，在同一 Wi-Fi 内对战。",13)
	action("创建房间",host_room)
	action("加入房间",join_menu)
	action("离开柜台",func():leave(0))

func join_menu() -> void:
	clear_panel()
	phase="address"
	label_for("加入通信对战",18)
	hint=label_for("输入对方屏幕上的局域网地址",13)
	address=LineEdit.new()
	layout.add_child(address)
	action("连接",func():join_room(address.text.strip_edges()))
	action("返回",menu)

func lobby() -> void:
	clear_panel()
	phase="lobby"
	label_for("通信单打",18)
	if role=="host":
		var ips:=Array(IP.get_local_addresses()).filter(func(ip):return ip.is_valid_ip_address() and not ":" in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."))
		label_for("房间地址　"+"　".join(ips),12)
	hint=label_for("等待另一位训练家",14)
	if role=="host":action("开始对战",begin)
	action("返回",func():leave(0))

func valid_mon(p) -> bool:
	return p is Array and p.size()==6 and not Data.species_of(int(p[0])).is_empty() and int(p[1]) in range(1,101) and p[3] is Array and p[3].size() in range(1,5) and p[3].all(func(id):return not Data.move_of(int(id)).is_empty())

func make_mon(p: Array) -> Dictionary:
	var mon:=Party.make(int(p[0]),int(p[1]),p[3],str(p[2]))
	mon.held=str(p[4])
	mon.berry=""
	Party.set_shiny_kind(mon,str(p[5]))
	return mon

func begin() -> void:
	if phase!="lobby" or role!="host" or foe_id==0:return
	engine=Battle.new(randi())
	engine.start([make_mon(entrant)],[make_mon(foe)])
	phase="match"
	publish()

func snapshot(mon: Dictionary) -> Array:
	return [mon.name,mon.hp,mon.max_hp,mon.level,mon.moves,mon.pp,mon.status]

func publish() -> void:
	choices.clear()
	round_id+=1
	var a:=snapshot(engine.cur_a())
	var b:=snapshot(engine.cur_b())
	var lines: Array=engine.log.slice(maxi(0,engine.log.size()-3))
	var p={"type":"board","mine":b,"foe":a,"n":round_id,"log":" ".join(lines).left(60)}
	send(foe_id,p)
	show_board(a,b,p.log)

func show_board(m: Array,other: Array,msg: String) -> void:
	clear_panel()
	phase="match"
	committed=false
	label_for("%s Lv.%d　%d / %d　对手 %s %d / %d"%[m[0],m[3],m[1],m[2],other[0],other[1],other[2]],14)
	hint=label_for(msg if msg!="" else "选择本回合的招式",12)
	var has_move=false
	for i in m[4].size():
		var b:=action("%s　PP %d"%[Data.move_of(int(m[4][i])).name,int(m[5][i])],select.bind(i))
		b.disabled=(int(m[5][i])<=0)
		has_move=has_move or not b.disabled
	if not has_move:action("挣扎",select.bind(0))
	action("认输",func():
		if role=="host":finish_match("b")
		else:send(1,{"type":"surrender"}))

func select(index: int) -> void:
	if phase!="match" or committed:return
	committed=true
	hint.text="已选定，等待对方行动。"
	if role=="client":send(1,{"type":"move","n":round_id,"i":index})
	else:accept_choice("a",index)

func accept_choice(side: String,index: int) -> void:
	if phase!="match" or choices.has(side):return
	var mon: Dictionary=engine.cur_a() if side=="a" else engine.cur_b()
	if index<0 or index>=mon.moves.size():return
	if int(mon.pp[index])<=0 and mon.pp.any(func(n):return int(n)>0):return
	choices[side]="move:"+str(index)
	if choices.size()==2:
		engine.run_turn(choices.a,choices.b)
		if engine.over:finish_match(engine.winner)
		else:publish()

func finish_match(w: String) -> void:
	if phase!="match":return
	winner=w
	send(foe_id,{"type":"done","winner":w})
	end_screen(w=="a")

func end_screen(win: bool) -> void:
	phase="result"
	received_end=win
	clear_panel()
	label_for("通信对战胜利！" if win else "通信对战结束。",18)
	claim=action("登记战绩",func():leave(0))
	if role=="host":
		claim.disabled=true
		remaining=4

func leave(_n: int) -> void:
	if phase=="closed":return
	var played:=phase=="result"
	var result:=played and received_end
	phase="closed"
	if wire:wire.close();wire=null
	departed.emit(result,played)
	hide()
	queue_free()

func peer_left(id: int) -> void:
	if id!=foe_id:return
	if phase=="lobby":
		foe_id=0
		foe=[]
		hint.text="等待另一位训练家"
	elif phase=="match":fail("同伴离开，对战中止。")

func receive(id: int,p: Dictionary) -> void:
	var type:String=p.get("type","")
	if role=="host":
		if type=="join":
			if phase!="lobby" or foe_id!=0 or not valid_mon(p.get("mon")):send(id,{"type":"abort"});return
			foe_id=id
			foe=p.mon
			hint.text="对手已就位："+str(Data.species_of(int(foe[0])).name)
		elif id==foe_id and type=="receipt":seen_receipt=true
		elif id==foe_id and phase=="match":
			if type=="move" and int(p.get("n",-1))==round_id:accept_choice("b",int(p.get("i",-1)))
			elif type=="surrender":finish_match("a")
	elif role=="client" and id==1:
		match type:
			"board":
				if phase in ["lobby","match"] and p.get("mine",[]) is Array and p.mine.size()==7 and p.get("foe",[]) is Array and p.foe.size()==7:
					round_id=int(p.n)
					show_board(p.mine,p.foe,str(p.get("log","")))
			"done":
				if phase=="match":
					send(1,{"type":"receipt"})
					end_screen(str(p.winner)=="b")
			"abort":fail("房间不可用或已经结束。")

func _process(delta: float) -> void:
	super._process(delta)
	if role=="client" and phase=="match" and wire.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED:fail("房间已关闭。")
	if phase=="result" and role=="host" and claim.disabled:
		remaining-=delta
		claim.disabled=not seen_receipt and remaining>0
