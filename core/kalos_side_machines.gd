extends RefCounted
const Field := preload("res://core/kalos_field.gd")
const QUIZ := [[62,"哪一招在没有携带道具时威力会翻倍？","杂技","燕返","飞翔"],[63,"哪一招会令对方暂时无法使用携带的道具？","查封","挑衅","小偷"],[92,"哪一招能让速度较慢的宝可梦先行动？","戏法空间","高速移动","顺风"],[100,"哪一招会向对手倾诉秘密、降低它的特攻？","密语","诡计","假哭"]]

static func interact(g,r: Dictionary) -> void:
	match str(r.action):
		"machine":
			Field.give_machine(g,int(r.tm),r.get("hidden",false))
			load("res://core/kalos_side.gd").save_event(g,r)
			g._dialog(["获得了%s。"%Field.machine_name(g,int(r.tm),r.get("hidden",false))])
		"tm_shop":
			var keys: Array=r.stock.keys();var choices: Array=[]
			var sale:=preload("res://core/kalos_opowers.gd").factor(g,"bargain")
			for n in keys:choices.append("%s　%d元"%[Field.machine_name(g,int(n),false),int(r.stock[n]*sale)])
			choices.append("返回")
			g._pick("招式学习器柜台",choices,func(i):
				if i>=keys.size():return
				var n:=int(keys[i]);var amount:=int(r.stock[keys[i]]*sale)
				if g._bag_count(Field.machine_name(g,n,false))>0:g._dialog(["你已经持有这枚可以重复使用的学习器。"]);return
				if int(g.save_data.money)<amount:g._dialog(["余额不足。"]);return
				g.save_data.money-=amount
				g.save_data.kalos_style=mini(255,int(g.save_data.get("kalos_style",0))+int(r.map=="kalos_lumiose"))
				Field.give_machine(g,n,false)
				g._dialog(["买到了%s。"%Field.machine_name(g,n,false)]))
		"tm_clock":
			var hour:=int(Time.get_time_dict_from_system().hour)
			var no:=32 if hour>=4 and hour<12 else 35 if hour>=12 and hour<18 else 77 if hour>=18 and hour<20 else 90
			if g._bag_count(Field.machine_name(g,no,false))>0:g._dialog(["在早晨、白天、黄昏和夜晚，我会想到不同的招式。"]);return
			Field.give_machine(g,no,false);g._dialog(["这个时刻，适合与你分享%s。"%Field.machine_name(g,no,false)],r.name)
		"tm_quiz":
			var stamp:=Time.get_date_string_from_system()
			if g.save_data.get("kalos_quiz_date","")==stamp:g._dialog(["今天就到这里，明天再来猜谜吧。"],r.name);return
			var todo:=QUIZ.filter(func(q):return g._bag_count(Field.machine_name(g,q[0],false))==0)
			if todo.is_empty():g._dialog(["四道招式谜语你都解出来了！"],r.name);return
			var q: Array=todo[0]
			var opts: Array=q.slice(2);opts.shuffle();opts.append("下次再来")
			g._pick(q[1],opts,func(i):
				if i==opts.size()-1:return
				if opts[i]!=q[2]:g._dialog(["再想想看。"],r.name);return
				g.save_data.kalos_quiz_date=stamp
				Field.give_machine(g,int(q[0]),false);g._dialog(["答对了！收下%s吧。"%Field.machine_name(g,int(q[0]),false)],r.name))
		"museum":
			g._pick("要参观这组卡洛斯艺术品吗？",["听导览","离开"],func(i):
				if i!=0:return
				g.save_data.kalos_style=mini(255,int(g.save_data.get("kalos_style",0))+2)
				g._persist();g._dialog(["这幅画记录了卡洛斯人与宝可梦的旅行。放慢脚步，密阿雷的故事就藏在这些细节里。"],r.name))

static func reminder(g,forget: bool) -> void:
	var scale:="心之鳞片"
	if not forget and g._bag_count(scale)==0:
		g._dialog(["带我一枚心之鳞片，我可以帮伙伴回忆招式。八号道路海边的爱心鱼有时会携带它。"])
		return
	var db=g.get_node("/root/Data")
	preload("res://core/hoenn_move_services.gd").choose_mon(g,"选哪只伙伴？",func(slot):
		var mon: Dictionary=g.save_data.party[slot]
		var available: Array=[]
		if forget:
			if mon.moves.size()<2:g._dialog(["伙伴至少要保留一个招式。"]);return
			available=mon.moves.duplicate()
		else:
			var learned: Array=mon.get("kalos_egg_memory",[]).duplicate()
			for row in Field.learnset(int(mon.species_id)):
				if int(row[0])<=int(mon.level):learned.append(int(row[1]))
			for entry in learned:
				var move:=int(entry)
				if not available.has(move) and not mon.moves.any(func(n):return int(n)==move):available.append(move)
		if available.is_empty():g._dialog(["目前没有可回忆的招式。"]);return
		var options: Array=available.map(func(m):return db.move_of(int(m)).name)
		g._pick("遗忘哪个招式？" if forget else "用一枚心之鳞片回忆哪个招式？",options,func(i):
			var move:=int(available[i])
			if not forget:
				g._tm_teach_one(move,slot,db.move_of(move).name,true,func():g._consume_item(scale))
				return
			g._pick("让%s忘掉%s？"%[mon.name,options[i]],["确认遗忘","保留"],func(j):
				if j!=0:return
				mon.moves.remove_at(i)
				if i<mon.get("pp",[]).size():mon.pp.remove_at(i)
				mon.get("pp_bonus",{}).erase(str(move))
				g._persist()
				g._dialog(["%s 忘掉了%s。"%[mon.name,options[i]]]))))
