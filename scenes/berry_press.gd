extends ColorRect
## Local wireless uses a player-hosted ENet room. Only the host counts presses.
signal closed(powder: int)
const Contest := preload("res://core/emerald_contest.gd")
const PORT := 25743
const LIMIT := 4
var wire: ENetMultiplayerPeer
var role := ""
var phase := "menu"
var berry := ""
var players := {}
var taps := {}
var target := 0
var power := 0
var progress := 0
var remaining := 0.0
var last_press := {}
var last_group := -1.0
var synced := 0
var windows := {}
var cpu_timer := 0.0
var finished_reward := 0
var layout := VBoxContainer.new()
var hint: Label
var meter: ProgressBar
var address: LineEdit

func setup(key: String) -> void:
	berry=key
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color=Color("#263542")
	mouse_filter=Control.MOUSE_FILTER_STOP
	var center:=CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(layout)
	layout.custom_minimum_size.x=336
	layout.add_theme_constant_override("separation",5)
	menu()

func clear_panel() -> void:
	for child in layout.get_children():
		layout.remove_child(child)
		child.queue_free()
	hint=null
	meter=null

func label_for(value: String, size: int) -> Label:
	var line:=Label.new()
	line.text=value
	line.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size",size)
	layout.add_child(line)
	return line

func action(label: String, fn: Callable) -> Button:
	var button:=Button.new()
	button.text=label
	button.custom_minimum_size.y=36
	button.add_theme_font_size_override("font_size",14)
	layout.add_child(button)
	button.pressed.connect(fn)
	return button

func menu() -> void:
	clear_panel()
	phase="menu"
	label_for("树果压榨",20)
	hint=label_for("两至五人同时压榨可获得更多粉末",12)
	action("与工作人员练习",practice)
	action("同一 Wi-Fi · 创建房间",host_room)
	action("同一 Wi-Fi · 加入房间",join_menu)
	action("返回柜台",func():leave(0))

func practice() -> void:
	role="practice"
	players={1:berry,2:"oran"}
	start_round()

func join_payload() -> Dictionary:
	return {"type":"join","berry":berry}

func port_number() -> int:
	return PORT

func host_room() -> void:
	wire=ENetMultiplayerPeer.new()
	var error:=wire.create_server(port_number(),LIMIT)
	if error!=OK:
		wire=null
		hint.text="房间创建失败，请检查局域网或稍后重试。"
		return
	role="host"
	players={1:berry}
	wire.peer_disconnected.connect(peer_left)
	lobby()

func service_name() -> String:return "树果压榨"

func join_menu() -> void:
	clear_panel()
	phase="address"
	label_for("加入"+service_name(),18)
	hint=label_for("输入创建者屏幕上的局域网地址",13)
	address=LineEdit.new()
	address.placeholder_text="192.168.1.100"
	layout.add_child(address)
	action("连接",func():join_room(address.text.strip_edges()))
	action("返回",menu)

func join_room(ip: String) -> void:
	if not ip.is_valid_ip_address():
		hint.text="请输入有效的局域网地址。"
		return
	wire=ENetMultiplayerPeer.new()
	if wire.create_client(ip,port_number())!=OK:
		wire=null
		hint.text="连接失败，请确认两台设备连在同一 Wi-Fi。"
		return
	role="client"
	phase="connecting"
	clear_panel()
	label_for("正在连接房间",18)
	hint=label_for(ip,13)
	remaining=12.0
	action("取消",func():leave(0))

func lobby() -> void:
	clear_panel()
	phase="lobby"
	label_for("无线树果压榨",18)
	var routes:=Array(IP.get_local_addresses()).filter(func(ip):return ip.is_valid_ip_address() and not ":" in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."))
	if role=="host":label_for("房间地址　"+"　".join(routes),12)
	hint=label_for("等待其他玩家加入…",14)
	if role=="host":action("开始压榨",func():
		if players.size()<2:hint.text="至少需要两位玩家。";return
		send(0,{"type":"start","players":players.values()})
		start_round())
	action("退出房间",func():leave(0))

func start_round(berries: Array=[]) -> void:
	if berries.is_empty():berries=players.values()
	target=0
	power=0
	for key in berries:
		var b: Dictionary=Contest.data().berries[key]
		target+=int(b.presses)
		power+=int(b.powder)
	power*=berries.size()
	progress=0
	remaining=120.0
	synced=0
	last_group=-1.0
	windows.clear()
	last_press.clear()
	clear_panel()
	phase="play"
	label_for("树果压榨",22)
	hint=label_for("一起连点压榨",14)
	meter=ProgressBar.new()
	meter.max_value=target
	meter.custom_minimum_size.y=22
	layout.add_child(meter)
	var paddle:=action("按下压杆",press)
	paddle.custom_minimum_size.y=78
	action("放弃本局",func():leave(0))

func send(id: int, packet: Dictionary) -> void:
	if not wire:return
	wire.set_target_peer(id)
	wire.transfer_mode=MultiplayerPeer.TRANSFER_MODE_RELIABLE
	wire.put_packet(JSON.stringify(packet).to_utf8_buffer())

func press() -> void:
	if phase!="play":return
	if role=="client":send(1,{"type":"tap"})
	else:count_tap(1)

func count_tap(id: int) -> void:
	if not players.has(id) or phase!="play":return
	var elapsed:=120.0-remaining
	if elapsed-float(last_press.get(id,-1.0))<0.045:return
	last_press[id]=elapsed
	taps[id]=int(taps.get(id,0))+1
	progress+=1
	for other in last_press:
		if id!=other and elapsed-last_press[other]<0.13 and elapsed-last_group>0.13:
			synced+=1
			progress+=1
			last_group=elapsed
			windows[floori(elapsed*2.0)]=true
			break
	meter.value=mini(progress,target)
	hint.text="压榨 %d / %d　同步 %d 次" % [mini(progress,target),target,synced]
	if role=="host":send(0,{"type":"tick","progress":progress,"sync":synced})
	if progress>=target:
		var yield_ratio:=0.5+0.5*minf(1.0,windows.size()/maxf(1.0,ceilf(elapsed*2.0)))
		var reward:=maxi(1,floori(power*yield_ratio))
		if role=="host":send(0,{"type":"done","reward":reward})
		show_result(reward)

func show_result(reward: int) -> void:
	finished_reward=reward
	clear_panel()
	phase="result"
	label_for("树果压榨完成",21)
	label_for("获得 %d 份粉末" % reward,16)
	action("装入粉末瓶",func():leave(finished_reward))

func peer_left(id: int) -> void:
	if phase=="result":return
	players.erase(id)
	if phase=="play":fail("有成员离开，本局结束，树果退回。")
	elif phase=="lobby":refresh_lobby()

func refresh_lobby() -> void:
	hint.text="已就位 %d / 5 人" % players.size()
	send(0,{"type":"lobby","count":players.size()})

func fail(message: String) -> void:
	if phase=="error":return
	if role=="host" and wire:send(0,{"type":"abort"})
	phase="error"
	clear_panel()
	label_for(message,14)
	action("返回柜台",func():leave(0))

func _process(delta: float) -> void:
	if wire:
		wire.poll()
		var status:=wire.get_connection_status()
		if role=="client" and phase=="connecting":
			remaining-=delta
			if status==MultiplayerPeer.CONNECTION_CONNECTED:
				lobby()
				send(1,join_payload())
			elif status==MultiplayerPeer.CONNECTION_DISCONNECTED or remaining<=0:fail("连接失败，请核对地址及 Wi-Fi。")
		if role=="client" and phase in ["lobby","play"] and status==MultiplayerPeer.CONNECTION_DISCONNECTED:fail("房间已关闭。")
		while wire and status==MultiplayerPeer.CONNECTION_CONNECTED and wire.get_available_packet_count()>0:
			var sender:=wire.get_packet_peer()
			var bytes:=wire.get_packet()
			if bytes.size()>600:continue
			var packet=JSON.parse_string(bytes.get_string_from_utf8())
			if packet is Dictionary:receive(sender,packet)
	if phase=="play":
		remaining-=delta
		if remaining<=0:fail("时间到了。收好树果再试一次吧。");return
		if role=="practice":
			cpu_timer+=delta
			if cpu_timer>=0.34:
				cpu_timer=0.0
				count_tap(2)

func receive(id: int, packet: Dictionary) -> void:
	var type: String=packet.get("type","")
	if role=="host":
		if type=="join":
			if phase!="lobby" or not Contest.data().berries.has(str(packet.get("berry",""))):
				send(id,{"type":"abort"})
				return
			players[id]=str(packet.berry)
			refresh_lobby()
		elif type=="tap" and phase=="play":count_tap(id)
	elif role=="client" and id==1:
		match type:
			"lobby":if phase=="lobby":hint.text="已就位 %d / 5 人" % int(packet.get("count",0))
			"start":
				var keys=packet.get("players",[])
				if phase=="lobby" and keys is Array and keys.size() in range(2,6) and keys.all(func(k):return Contest.data().berries.has(k)):start_round(keys)
			"tick":
				if phase=="play":
					meter.value=int(packet.get("progress",0))
					hint.text="压榨 %d / %d　同步 %d 次" % [meter.value,target,int(packet.get("sync",0))]
			"done":if phase=="play":show_result(clampi(int(packet.get("reward",0)),1,power))
			"abort":if phase!="result":fail("本局已结束，树果退回。")

func leave(reward: int) -> void:
	if phase=="closed":return
	phase="closed"
	if wire:wire.close();wire=null
	hide()
	closed.emit(reward)
	queue_free()

func handle_back() -> void:
	leave(finished_reward if phase=="result" else 0)
