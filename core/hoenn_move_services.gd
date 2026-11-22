extends RefCounted
const Rules := preload("res://core/frontier_rules.gd")
const TUTORS := {"MetronomeTutor":118,"RolloutTutor":205,"MimicTutor":102,"ExplosionTutor":153,"SleepTalkTutor":214,"FuryCutterTutor":210,"DoubleEdgeTutor":38,"DynamicPunchTutor":223,"SubstituteTutor":164,"SwaggerTutor":207}

static func choose_mon(g,title: String,callback: Callable) -> void:
	var slots: Array=[]
	for i in g.save_data.party.size():
		var mon: Dictionary=g.save_data.party[i]
		if not mon.is_empty() and not mon.get("is_egg",false):slots.append(i)
	if slots.is_empty():g._dialog(["队伍里没有可以选择的宝可梦。"]);return
	g._pick(title,slots.map(func(i):return g.save_data.party[i].name),func(i):callback.call(slots[i]))

static func talk(g,script: String) -> bool:
	var role:=script.get_slice("_EventScript_",1)
	var db=g.get_node("/root/Data")
	if TUTORS.has(role):
		var id: int=TUTORS[role]
		var key:="h_tutor_"+role
		var display:=str(db.move_of(id).name)
		if g._flags().get(key,false):
			g._dialog(["我已经把「%s」传授给你的伙伴了。"%display]);return true
		choose_mon(g,"免费传授一次「%s」 · 选择伙伴"%display,func(slot):
			var mon: Dictionary=g.save_data.party[slot]
			var allowed: Array=Rules.data().learn.get(str(id),[])
			if not allowed.any(func(s):return int(s)==int(mon.species_id)):
				g._dialog(["%s 学不会这个招式。"%mon.name]);return
			g._tm_teach_one(id,slot,display,true,func():g._flags()[key]=true))
		return true
	if role=="MoveRelearner":
		if g._bag_count("心之鳞片")==0:g._dialog(["带来一枚心之鳞片，我就能帮伙伴找回成长中学过的招式。"]);return true
		choose_mon(g,"帮哪只宝可梦回忆招式？",func(slot):
			var m: Dictionary=g.save_data.party[slot]
			var options: Array=[]
			var levels: Array=Rules.data().level_moves.get(str(int(m.species_id)),db.species_of(int(m.species_id)).get("learnset",[]))
			for row in levels:
				var id:=int(row[1])
				if int(row[0])<=int(m.level) and not options.has(id) and not m.moves.any(func(known):return int(known)==id):options.append(id)
			if options.is_empty():g._dialog(["没有可以回忆的招式。"]);return
			g._pick("用一枚心之鳞片回忆",options.map(func(id):return db.move_of(id).name),func(n):
				var mv: int=options[n]
				g._tm_teach_one(mv,slot,db.move_of(mv).name,true,func():g._consume_item("心之鳞片"))))
		return true
	if role=="MoveDeleter":
		choose_mon(g,"让哪只宝可梦忘掉招式？",func(slot):
			var m: Dictionary=g.save_data.party[slot]
			if m.moves.size()<2:g._dialog(["至少要留下一项招式。"]);return
			g._pick("选择要忘掉的招式",m.moves.map(func(id):return db.move_of(int(id)).name),func(i):
				var id:=int(m.moves[i])
				if id==57 and not g.save_data.party.any(func(other):return other!=m and not other.is_empty() and other.moves.any(func(v):return int(v)==57)):
					g._dialog(["队伍中只有它会冲浪，它舍不得忘掉。"]);return
				g._pick("让%s忘掉「%s」？"%[m.name,db.move_of(id).name],["确认遗忘","保留"],func(yes):
					if yes!=0:return
					m.moves.remove_at(i)
					if i<m.get("pp",[]).size():m.pp.remove_at(i)
					m.get("pp_bonus",{}).erase(str(id))
					g._persist()
					g._dialog(["%s 忘掉了「%s」。"%[m.name,db.move_of(id).name]]))))
		return true
	if role=="NameRater":
		choose_mon(g,"给哪一只评定名字？",func(slot):
			var m: Dictionary=g.save_data.party[slot]
			if m.has("ot_id") and int(m.ot_id)!=int(g.save_data.get("js_trainer_id",-1)):
				g._dialog(["这是原训练家给它的名字，我觉得很合适。"]);return
			var box:=ConfirmationDialog.new()
			box.title="姓名评定师"
			box.ok_button_text="采用这个名字"
			box.cancel_button_text="保留"
			var field:=LineEdit.new()
			field.text=m.name
			field.max_length=10
			field.custom_minimum_size=Vector2(245,39)
			box.add_child(field)
			g.add_child(box)
			box.confirmed.connect(func():
				var value:=field.text.strip_edges()
				if not value.is_empty():
					m.name=value
					g._persist())
			box.visibility_changed.connect(func():
				if not box.visible:box.queue_free())
			box.popup_centered(Vector2i(280,105))
			field.grab_focus())
		return true
	return false
