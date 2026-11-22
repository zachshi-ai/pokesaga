extends RefCounted
## Platinum's Jubilife TV lottery and Backlot's rotating Trophy Garden encounters.
const FR:=preload("res://core/frlg_sidequests.gd")
const Digits:=preload("res://core/crystal_phone.gd")
const PRIZES:=["","ULTRA_BALL","PP_UP","EXP_SHARE","MAX_REVIVE","MASTER_BALL"]
# Older FireRed and Emerald trade saves kept the OT name but omitted the numeric ID.
# Original IDs from pret/pokefirered src/data/ingame_trades.h and pokeemerald src/data/trade.h.
const LEGACY_TRADE_IDS:={"REYLEY":1985,"DONTAE":36728,"SAIGE":63184,"ELYSSA":8810,"TURNER":13637,"HADEN":1239,"CLIFTON":50298,"NORMA":60042,"GARETT":9853,"KOBE":38726,"ROMAN":73996,"SKYLAR":46285,"ISIS":91481}

static func talk(g,side,script: String) -> bool:
	match script:
		"JubilifeTV1F_AceTrainerSnowF":lottery(g,side)
		"PokemonMansionOffice_MrBacklot":backlot(g,side)
		"PokemonMansionOffice_OldMan":
			var visit: Dictionary=g.save_data.get("s_trophy_garden",{})
			if str(visit.get("date",""))==Time.get_date_string_from_system() and int(visit.get("current",0)):
				FR.say(g,"据老爷说，今天他在后院看到了%s。"%Data.species_of(int(visit.current)).name,"管家")
			else:FR.say(g,"老爷每天都喜欢去自豪的后院散步。","管家")
		_:return false
	return true

static func lottery(g,side) -> void:
	var today:=Time.get_date_string_from_system()
	var state: Dictionary=g.save_data.get_or_add("s_tv_lottery",{})
	if state.is_empty() or str(state.get("date",""))<today:
		state.assign({"date":today,"number":g.rng.randi_range(0,65535)})
		g._persist()
	if state.get("paid",false):
		FR.say(g,"本期号码 %05d，奖品已经领过。明天再来吧。"%int(state.number),"祝庆电视台")
		return
	g._pick("要核对今天的五位幸运号码吗？",["核对号码","下次再来"],func(i):
		if i!=0 or state.get("paid",false):return
		var owner_id:=preload("res://core/crystal_wild_events.gd").trainer(g)
		var winner:=best_match(g.save_data,int(state.number),owner_id)
		var digits:=int(winner.digits)
		var lines:=["今日幸运号码　%05d"%int(state.number)]
		if digits==0:lines.append("没有相符的末位。若又交换到宝可梦，今天还可以回来核对同一号码。")
		else:
			var gift: String=PRIZES[digits]
			side.give(g,gift)
			state.paid=true
			lines.append("%s的%s末 %d 位相符！获得%s。"%[winner.place,winner.mon,digits,side.item_name(gift)])
		g._persist()
		g._dialog(lines,"祝庆电视台"))

static func best_match(save: Dictionary,ticket: int,owner: int) -> Dictionary:
	var sources: Array=[save.get("party",[])]
	for box in save.get("boxes",[]):
		if box is Dictionary:sources.append(box.get("mons",[]))
	var best:={"digits":0,"mon":"","place":""}
	for b in sources.size():
		for mon in sources[b]:
			if not mon is Dictionary or int(mon.get("species_id",0))<=0 or mon.get("is_egg",false):continue
			var old_ot:=str(mon.get("original_trainer",mon.get("ot",""))).to_upper()
			var id:=int(mon.get("ot_id",LEGACY_TRADE_IDS.get(old_ot,owner)))&0xffff
			var n:=Digits.match_digits(id,ticket)
			if n>int(best.digits):
				best={"digits":n,"mon":str(mon.get("nickname",mon.get("name",""))),"place":"队伍" if b==0 else "电脑箱 %d"%b}
				if n==5:return best
	return best

static func backlot(g,side) -> void:
	var today:=Time.get_date_string_from_system()
	var visit: Dictionary=g.save_data.get_or_add("s_trophy_garden",{})
	if not g._flags().get("s_national_dex",false):FR.say(g,"欢迎来豪宅做客。一定要去我的自豪后院走走！","豪宅主人")
	elif str(visit.get("date",""))>=today and int(visit.get("current",0)):
		FR.say(g,"今天我在后院看到的%s，真是可爱啊！"%Data.species_of(int(visit.current)).name,"豪宅主人")
	else:
		g._pick("我的后院真让人羡慕，你也这么想吗？",["是","还好"],func(yes):
			if yes!=0:return
			g._pick("想听听今天我在后院遇见了谁吗？",["想听","下次再说"],func(i):
				if i!=0 or str(visit.get("date",""))>=today:return
				var choices: Array=side.data().garden_species.filter(func(s):return int(s)!=int(visit.get("current",0)) and int(s)!=int(visit.get("previous",0)))
				visit.previous=int(visit.get("current",0))
				visit.current=int(choices[g.rng.randi_range(0,choices.size()-1)])
				visit.date=today
				g._persist()
				# Original script removes the butler for this visit only.
				var local: Dictionary=g.world.map_data.duplicate()
				local.npcs=local.npcs.filter(func(row):return str(row.get("source_script",""))!="PokemonMansionOffice_OldMan")
				g.world.map_data=local
				g.world.refresh_story_actors(g._flags())
				g._dialog(["早上我去散步，一只%s跑过来亲了亲我的脸。"%Data.species_of(int(visit.current)).name,"管家小声说，园里原本没有这种宝可梦。他赶紧离开了办公室。"],"豪宅主人")))

static func garden_pool(save: Dictionary,slots: Array) -> Array:
	if slots.size()<8 or not save.get("flags",{}).get("s_national_dex",false):return slots
	var state: Dictionary=save.get("s_trophy_garden",{})
	if int(state.get("current",0))==0:return slots
	var new_slots:=slots.duplicate()
	for i in 2:
		var species:=int(state.get(["current","previous"][i],0))
		if species>0:
			new_slots[6+i]=new_slots[6+i].duplicate()
			new_slots[6+i].species=species
	return new_slots
