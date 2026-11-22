extends RefCounted
## 原作水静中心的三种女士。训练家 ID 决定第一个来访者，本地交换分别保留三份记录。
const MAP := "em_lilycove_city_pokemon_center_1f"
const GFX := ["OBJ_EVENT_GFX_WOMAN_4","OBJ_EVENT_GFX_WOMAN_2","OBJ_EVENT_GFX_GIRL_2"]
const MON_GFX := ["OBJ_EVENT_GFX_ZIGZAGOON_1","OBJ_EVENT_GFX_SKITTY","OBJ_EVENT_GFX_POOCHYENA","OBJ_EVENT_GFX_KECLEON","OBJ_EVENT_GFX_PIKACHU"]
const MON_NAMES := ["蛇纹熊","向尾喵","土狼犬","变隐龙","皮卡丘"]
const CATEGORIES := ["帅气","美丽","可爱","聪明","强壮"]
const TASTES := ["辣","涩","甜","苦","酸"]
const SALES := {"NUGGET":5000,"BIG_PEARL":3750,"STAR_PIECE":4900,"PEARL":700,"STARDUST":1000}
const MAIL := ["GLITTER_MAIL","TROPIC_MAIL","BEAD_MAIL"]
static var catalog: Dictionary

static func data() -> Dictionary:
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string("res://content/hoenn_native/lilycove_lady.json"))
	return catalog

static func day() -> int:
	return floori(float(Time.get_unix_time_from_datetime_dict(Time.get_date_dict_from_system()))/86400.0)

static func record(g) -> Dictionary:
	if not g.save_data.has("js_trainer_id"):g.save_data.js_trainer_id=g.rng.randi_range(0,65535)
	var f: Dictionary=g._flags()
	if not f.has("h_lily_ladies"):
		f.h_lily_ladies={"current":(int(g.save_data.js_trainer_id)%6)>>1,"turn":0}
	var state: Dictionary=f.h_lily_ladies
	if not state.has("quiz"):state.quiz={"index":g.rng.randi_range(0,15)}
	if not state.has("favor"):state.favor=new_favor(g)
	if not state.has("contest"):state.contest=new_contest(g)
	return state

static func new_favor(g) -> Dictionary:
	var index:=int(g.rng.randi_range(0,5))
	var pool: Array=data().favor[index].items
	return {"index":index,"favorite":pool[g.rng.randi_range(0,pool.size()-1)],"liked":0}

static func new_contest(g) -> Dictionary:
	return {"index":g.rng.randi_range(0,4),"good":0,"other":0}

static func prepare(g,map: Dictionary) -> void:
	if map.get("id","")!=MAP:return
	var state:=record(g)
	for n in map.get("npcs",[]):
		var sc:=str(n.get("source_script",""))
		if sc.ends_with("_LilycoveLady"):n.native_gfx=GFX[int(state.current)]
		if sc.ends_with("_ContestLadyMon"):
			n.native_gfx=MON_GFX[int(state.contest.index)]
			n.name=MON_NAMES[int(state.contest.index)]

static func visible(n: Dictionary, f: Dictionary) -> int:
	var sc:=str(n.get("source_script",""))
	if sc.ends_with("_LilycoveLady"):return 1
	if sc.ends_with("_ContestLadyMon"):return int(f.get("h_lily_ladies",{}).get("current",-1)==2)
	return -1

static func period(state: Dictionary) -> String:
	return "%d/%d"%[day(),int(state.turn)]

static func mix(g) -> void:
	var state:=record(g)
	state.current=(int(state.current)+1)%3
	state.turn=int(state.turn)+1
	prepare(g,g.world.map_data)
	g.world.refresh_story_actors(g._flags())
	g._persist()
	g._dialog(["本地活动记录交换好了。中心来了另一位女士，之前的记录也保存着。"])

static func talk(g,n: Dictionary) -> bool:
	var sc:=str(n.get("source_script",""))
	if sc=="LilycoveCity_DepartmentStore_1F_EventScript_Greeter":
		g._pick("水静百货一楼服务台",["出售贵重物品","查看伙伴的邮件","离开"],func(i):
			if i==0:desk(g)
			elif i==1:post(g))
		return true
	if sc.ends_with("_ContestLadyMon"):
		var idx:=int(record(g).contest.index)
		g._dialog(["%s！"%MON_NAMES[idx]],MON_NAMES[idx])
		return true
	if not sc.ends_with("_LilycoveLady"):return false
	var state:=record(g)
	var options:=["挑战问答","出一道题","交换本地活动记录","离开"] if state.current==0 else ["看看她想要什么","交换本地活动记录","离开"]
	g._pick(["问答女士","收藏女士","华丽大赛女士"][int(state.current)],options,func(i):
		if i==0:
			match int(state.current):
				0:quiz(g,state)
				1:favor(g,state)
				2:contest(g,state)
		elif state.current==0 and i==1:compose_quiz(g,state)
		elif i==options.size()-2:mix(g))
	return true

static func name_for(key: String) -> String:
	return str(data().items.get(key,key))

static func item_key(row: Dictionary) -> String:
	var key:=str(row.get("held",row.get("key",""))).trim_prefix("ITEM_")
	if data().items.has(key):return key
	if row.has("berry"):return str(row.berry).to_upper()+"_BERRY"
	var nm:=str(row.get("name",""))
	return str(data().aliases.get(nm,data().items.find_key(nm) if data().items.values().has(nm) else ""))

static func give(g,key: String) -> void:
	var name_text:=name_for(key)
	if key.ends_with("_BERRY"):
		g._give_bag_item(name_text,"berry","",key.trim_suffix("_BERRY").to_lower())
	elif key in ["LUXURY_BALL","PREMIER_BALL"]:g._give_item(name_text,1,"ball")
	elif key.begins_with("TM_"):g._give_item(name_text,1,"tm")
	elif key=="RARE_CANDY":g._give_item(name_text,1,"candy")
	elif key in ["MAX_ETHER","PROTEIN","PP_MAX"]:g._give_item(name_text,1,"heal")
	else:g._give_bag_item(name_text,"other",key)

static func select_item(g,heading: String,callback: Callable) -> void:
	var rows: Array=g.bag_items.filter(func(r):return r is Dictionary and int(r.get("count",0))>0 and not r.get("category","") in ["key","tm","hm"] and not r.name.begins_with("秘传学习器"))
	if rows.is_empty():g._dialog(["背包里没有可以交出的道具。"]);return
	var opts: Array=rows.map(func(r):return str(r.name)+" ×"+str(int(r.count)))
	opts.append("取消")
	g._pick(heading,opts,func(i):
		if i<rows.size() and g._bag_count(rows[i].name)>0:callback.call(rows[i]))

static func favor(g,state: Dictionary) -> void:
	var f: Dictionary=state.favor
	if f.get("last","")==period(state):g._dialog(["我已经收过你的礼物了。下次活动记录更新后再来吧。"]);return
	var spec: Dictionary=data().favor[int(f.index)]
	select_item(g,"送她一件%s东西"%spec.desire,func(row):
		var key:=item_key(row)
		g._consume_item(row.name)
		f.last=period(state)
		if key==f.favorite:f.liked=5
		elif key in spec.items:f.liked=int(f.liked)+1
		if int(f.liked)>=5:
			give(g,spec.prize)
			state.favor=new_favor(g)
			state.favor.last=period(state)
			g._dialog(["这就是我最心爱的收藏！谢谢你，收下%s。"%name_for(spec.prize)])
		elif key in spec.items:g._dialog(["对，就是这种感觉！我收下了。"])
		else:g._dialog(["我收下了，可它跟我想象的不太一样。"])
		g._persist())

static func quiz(g,state: Dictionary) -> void:
	var q: Dictionary=state.quiz
	if q.get("last","")==period(state):g._dialog(["这次答过了，下一次更新活动记录再挑战吧。"]);return
	var challenge: Dictionary=data().quiz[int(q.index)]
	var prize:=str(challenge.prize)
	g._pick(str(challenge.prompt),challenge.options,func(i):
		q.last=period(state)
		if i==int(challenge.correct):
			give(g,prize)
			q.passed=true
			g._dialog(["答对了！奖品是%s。你也可以出一道题。"%name_for(prize)])
		else:g._dialog(["正确答案是%s。下次再来挑战！"%challenge.options[int(challenge.correct)]])
		q.index=(int(q.index)+g.rng.randi_range(1,15))%16
		g._persist())

static func contest(g,state: Dictionary) -> void:
	var c: Dictionary=state.contest
	var idx:=int(c.index)
	if c.get("last","")==period(state):g._dialog(["%s今天吃饱了。"%MON_NAMES[idx]]);return
	var blocks: Array=g._flags().get("h_blocks",[])
	if blocks.is_empty():g._dialog(["想参加%s组的%s喜欢%s味。带一个宝可方块来吧。"%[CATEGORIES[idx],MON_NAMES[idx],TASTES[idx]]]);return
	var opts: Array=blocks.map(func(b):return str(b.get("name","宝可方块")) if b is Dictionary else str(b))
	opts.append("取消")
	g._pick("%s爱吃%s味。给它哪个？"%[MON_NAMES[idx],TASTES[idx]],opts,func(i):
		if i>=blocks.size():return
		var block=blocks.pop_at(i)
		var berry:=str(block.get("berry","")) if block is Dictionary else str(block)
		var db=g.get_node("/root/Data")
		if not db.berries.has(berry):
			for k in db.berries:
				if db.berry_name(k)==opts[i]:berry=k;break
		var profile: Dictionary=block if block is Dictionary and block.has("flavor") else preload("res://core/emerald_contest.gd").data().berries.get(berry,{"flavor":[0,0,0,0,0]})
		var good:=int(profile.flavor[idx])>0
		var counter: String="good" if good else "other"
		c[counter]=int(c[counter])+1
		c.last=period(state)
		if c.good>=5 or c.other>=5:
			state.broadcast={"category":idx,"success":int(c.good)>=5,"some":int(c.good)>0}
			state.contest=new_contest(g)
			state.contest.last=period(state)
			prepare(g,g.world.map_data)
			g.world.refresh_story_actors(g._flags())
		g._persist()
		g._dialog(["%s%s。"%[MON_NAMES[idx],"高兴地吃完了" if good else "勉强吃了下去"]]))

static func television(g) -> bool:
	var state: Dictionary=g._flags().get("h_lily_ladies",{})
	if not state.has("broadcast"):return false
	var show: Dictionary=state.broadcast
	var idx:=int(show.category)
	var result: String="表现出色！" if show.success else ("还有进步的空间。" if show.some else "希望下次更顺利。")
	state.erase("broadcast")
	g._persist()
	g._dialog(["丰缘华丽大赛快报！%s参加了%s组的比赛。%s"%[MON_NAMES[idx],CATEGORIES[idx],result]],"电视播报员")
	return true

static func form(g, title: String, placeholders: Array, complete: Callable) -> void:
	var ui=load("res://core/field_ui.gd")
	var screen:=Control.new()
	screen.name="LilycoveEntry"
	screen.set_meta("lily_entry",true)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.menu_layer.add_child(screen)
	g.panel_open+=1
	g._set_hud_visible(false)
	var sheet: Control=ui.sheet(screen)
	var close:=func():
		if screen.is_queued_for_deletion():return
		screen.hide()
		screen.queue_free()
		g.panel_open=maxi(0,int(g.panel_open)-1)
		g._set_hud_visible(g.panel_open==0)
	screen.set_meta("choice_back",close)
	ui.header(sheet,title,"",close)
	var scroll: ScrollContainer=ui.scroll(sheet,Vector2(14,58),sheet.size-Vector2(28,70))
	var list: VBoxContainer=ui.list_box(scroll,6)
	var inputs: Array=[]
	for placeholder in placeholders:
		var input:=LineEdit.new()
		input.placeholder_text=placeholder
		input.accessibility_name=placeholder
		input.max_length=64
		input.custom_minimum_size=Vector2(260,37)
		list.add_child(input)
		inputs.append(input)
	list.add_child(ui.button("确定",func():
		var words: Array=inputs.map(func(input):return str(input.text).strip_edges())
		if words.any(func(word):return word.is_empty()):
			g._show_toast("先填好每一栏。")
			return
		close.call()
		complete.call(words)))

static func give_back(g,row: Dictionary) -> void:
	g._give_bag_item(row.name,row.get("category","other"),row.get("held",""),row.get("berry",""),row.get("tera",""))

static func compose_quiz(g,state: Dictionary) -> void:
	var q: Dictionary=state.quiz
	if q.has("custom"):
		var custom: Dictionary=q.custom
		g._pick("你留下的题目",["请身边的同伴作答","撤回题目和奖品","离开"],func(i):
			if i==1:
				give_back(g,custom.gift)
				q.erase("custom")
				g._persist()
				g._dialog(["已取回%s。"%custom.gift.name])
			elif i==0:
				form(g,custom.prompt,["输入答案"],func(answer):
					if str(answer[0]).nocasecmp_to(custom.answer)!=0:
						g._dialog(["没有答中。奖品仍保管在这里。"])
						return
					give_back(g,custom.gift)
					q.erase("custom")
					g._persist()
					g._dialog(["答对了！把约定的%s放进了本机背包。"%custom.gift.name])))
		return
	if not q.get("passed",false):g._dialog(["先答对我出的一道题，再来当出题人吧。"]);return
	form(g,"出一道问答题",["题目","正确答案"],func(words):
		select_item(g,"为这道题选一份奖品",func(row):
			var gift: Dictionary=row.duplicate(true)
			g._consume_item(row.name)
			q.custom={"prompt":words[0],"answer":words[1],"gift":gift}
			g._persist()
			g._dialog(["题目和奖品都保存好了。下次选“出一道题”，可邀请身边的同伴来答，也可取回奖品。"])))

static func desk(g) -> void:
	var rows: Array=g.bag_items.filter(func(r):return r is Dictionary and int(r.get("count",0))>0 and SALES.has(item_key(r)))
	if rows.is_empty():g._dialog(["欢迎光临水静百货！服务台收购珍珠、星星沙子、星之碎片和金珠。"]);return
	var opts: Array=rows.map(func(r):return "%s　%d元"%[r.name,SALES[item_key(r)]])
	opts.append("离开")
	g._pick("卖一件贵重物品",opts,func(i):
		if i>=rows.size():return
		var row: Dictionary=rows[i]
		var price: int=SALES[item_key(row)]
		g._pick("把%s卖%d元？"%[row.name,price],["出售","留着"],func(j):
			if j!=0 or g._bag_count(row.name)<1:return
			g._consume_item(row.name)
			g.save_data.money=int(g.save_data.money)+price
			g._persist()
			g._dialog(["收好了，这是%d元。"%price])))

static func use(g,nm: String) -> bool:
	var key:=item_key({"name":nm})
	if key not in MAIL:return false
	var slots: Array=[]
	for i in g.save_data.party.size():
		var m: Dictionary=g.save_data.party[i]
		if not m.is_empty() and not m.has("h_letter"):slots.append(i)
	if slots.is_empty():g._dialog(["队伍中没有能随身带信的伙伴。"]);return true
	var names: Array=slots.map(func(i):return g.save_data.party[i].name)
	names.append("取消")
	g._pick("把%s交给哪位伙伴？"%name_for(key),names,func(i):
		if i>=slots.size():return
		var mon: Dictionary=g.save_data.party[slots[i]]
		form(g,"写一封信",["信中想写的话"],func(words):
			if g._bag_count(nm)<1 or mon.has("h_letter"):return
			g._consume_item(nm)
			mon.h_letter={"key":key,"text":words[0]}
			g._persist()
			g._dialog(["%s收好了你的信。水静百货一楼的服务台可以读信或收回。"%mon.name])))
	return true

static func post(g) -> void:
	var party: Array=g.save_data.party.filter(func(m):return m is Dictionary and m.has("h_letter"))
	if party.is_empty():g._dialog(["先在背包里选一张邮件，写好后交给队伍里的伙伴。"]);return
	var opts: Array=party.map(func(m):return m.name)
	opts.append("离开")
	g._pick("读哪位伙伴带的信？",opts,func(i):
		if i>=party.size():return
		var mon: Dictionary=party[i]
		var letter: Dictionary=mon.h_letter
		g._pick(str(letter.text),["读完了","取回信纸"],func(j):
			if j!=1 or not mon.has("h_letter"):return
			give(g,letter.key)
			mon.erase("h_letter")
			g._persist()
			g._dialog(["收回了%s。"%name_for(letter.key)])))
