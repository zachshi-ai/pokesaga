extends "res://scenes/berry_press.gd"
signal completed(block: Dictionary)
const Wheel := preload("res://scenes/contest_blender.gd")
var machine
var frames_sent:=0.0
var paid:={}
var last_laps:={}
var participant_index:=0

func port_number() -> int:return 25747
func service_name() -> String:return "无线树果混合"

func menu() -> void:
	clear_panel()
	phase="menu"
	label_for(service_name(),19)
	hint=label_for("两至四人各投入一颗树果，共用同一台混合机。",13)
	action("和大厅训练家练习",func():start_mix([berry,"cheri" if berry!="cheri" else "aspear"],0,true))
	action("同一 Wi-Fi · 创建房间",host_room)
	action("同一 Wi-Fi · 加入房间",join_menu)
	action("离开",func():leave(0))

func lobby() -> void:
	clear_panel()
	phase="lobby"
	label_for(service_name(),19)
	if role=="host":
		var ips:=Array(IP.get_local_addresses()).filter(func(ip):return ip.is_valid_ip_address() and not ":" in ip and not ip.begins_with("127."))
		label_for("房间地址　"+"　".join(ips),12)
	hint=label_for("等待伙伴加入",14)
	if role=="host":action("启动混合机",begin_mix)
	action("离开",func():leave(0))

func refresh_lobby() -> void:
	hint.text="已就位 %d / 4 人" % players.size()
	send(0,{"type":"lobby","count":players.size()})

func begin_mix() -> void:
	if players.size()<2:hint.text="至少需要两位训练家。";return
	var berries:=players.values()
	for i in range(1,players.size()):send(int(players.keys()[i]),{"type":"mix","berries":berries,"index":i})
	start_mix(berries,0)

func start_mix(berries: Array,index: int,practice_mode:=false) -> void:
	phase="mixing"
	participant_index=index
	machine=Wheel.new()
	add_child(machine)
	machine.setup(berry,1)
	machine.ingredients=berries.duplicate()
	machine.title.text="%d 人树果混合机"%berries.size()
	machine.queue_redraw()
	machine.set_process(practice_mode)
	machine.linked=not practice_mode
	machine.seat=index
	if practice_mode:role="practice"
	else:
		machine.action.pressed.disconnect(machine.press)
		machine.action.pressed.connect(func():
			if role=="host":receive_strike(1)
			else:send(1,{"type":"strike"}))
	machine.completed.connect(func(block):
		paid=block
		leave(0))

func receive_strike(id: int) -> void:
	if not players.has(id) or machine==null:return
	var seat:=players.keys().find(id)
	var target_angle: float=PI/2+TAU*seat/players.size()
	var lap:=roundi((machine.angle-target_angle)/TAU)
	if int(last_laps.get(id,-10))==lap:return
	last_laps[id]=lap
	machine.score(absf(wrapf(machine.angle-target_angle,-PI,PI)))

func _process(delta: float) -> void:
	super._process(delta)
	if phase!="mixing" or role=="practice":return
	if role=="host":
		machine._process(delta)
		frames_sent+=delta
		if frames_sent>=0.075 or machine.done:
			frames_sent=0.0
			send(0,{"type":"spin","angle":machine.angle,"rpm":machine.rpm,"peak":machine.peak})
		if machine.done:
			var block: Dictionary=machine.make_block()
			send(0,{"type":"block","data":block})
			result(block)
	elif wire and wire.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED:fail("房间已关闭。树果已收回。")

func result(block: Dictionary) -> void:
	phase="result"
	paid=block.duplicate(true)
	if is_instance_valid(machine):machine.hide()
	clear_panel()
	label_for("宝可方块制作完成",19)
	label_for("最高转速 %.1f RPM"%float(block.rpm),14)
	action("装进方块盒",func():leave(0))

func receive(id: int,packet: Dictionary) -> void:
	var message: String=packet.get("type","")
	if role=="host":
		if message=="join":
			if players.size()>=4:send(id,{"type":"abort"});return
			super.receive(id,packet)
		elif message=="strike" and phase=="mixing":receive_strike(id)
	elif id==1:
		if message=="lobby" and phase=="lobby":hint.text="已就位 %d / 4 人" % int(packet.get("count",1))
		elif message=="mix" and phase=="lobby":
			var berries=packet.get("berries",[])
			if berries is Array and berries.size() in [2,3,4] and berries.all(func(b):return Contest.data().berries.has(b)):start_mix(berries,clampi(int(packet.get("index",1)),1,berries.size()-1))
		elif message=="spin" and phase=="mixing":
			machine.angle=float(packet.angle);machine.rpm=float(packet.rpm);machine.peak=float(packet.peak)
			machine.wheel.rotation=fmod(machine.angle,TAU)
			machine.refresh()
		elif message=="block" and phase=="mixing" and packet.get("data",{}) is Dictionary:
			var block: Dictionary=packet.data
			if block.get("flavor",[]).size()==5 and block.has("smooth") and block.has("rpm"):result(block)
		elif message=="abort":fail("伙伴离开了房间，树果已收回。")
		else:super.receive(id,packet)

func peer_left(id: int) -> void:
	if phase=="mixing" or phase=="result":
		if phase=="mixing":fail("伙伴离开了房间，树果已收回。")
		return
	super.peer_left(id)

func fail(value: String) -> void:
	if is_instance_valid(machine):machine.hide()
	super.fail(value)

func leave(_reward: int) -> void:
	if phase=="closed":return
	completed.emit(paid)
	super.leave(0)
