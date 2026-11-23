extends RefCounted

const COLORS := ["","YELLOW","ORANGE","BLUE","WHITE"]
const TRIMS := ["","HEART","STAR","DIAMOND","DEBUTANTE","MATRON","DANDY","LA_REINE","KABUKI","PHARAOH"]
const SIZES := ["","SMALL","LARGE","SUPER"]
const FORMS := {
	412:["","BURMY_SANDY","BURMY_TRASH"],479:["","ROTOM_HEAT","ROTOM_WASH","ROTOM_FROST","ROTOM_FAN","ROTOM_MOW"],
	550:["","BASCULIN_BLUE_STRIPED"],678:["","MEOWSTIC_F"],
	666:["","SPEWPA_POLAR","SPEWPA_TUNDRA","SPEWPA_CONTINENTAL","SPEWPA_GARDEN","SPEWPA_ELEGANT","SPEWPA_MEADOW","SPEWPA_MODERN","SPEWPA_MARINE","SPEWPA_ARCHIPELAGO","SPEWPA_HIGH_PLAINS","SPEWPA_SANDSTORM","SPEWPA_RIVER","SPEWPA_MONSOON","SPEWPA_SAVANNA","SPEWPA_SUN","SPEWPA_OCEAN","SPEWPA_JUNGLE","SPEWPA_FANCY","SPEWPA_POKE_BALL"],
}

static func key(species: int,index: int) -> String:
	if index<=0:return ""
	var options: Array=FORMS.get(species,[])
	var prefix: String={669:"FLABEBE",670:"FLOETTE",671:"FLORGES",676:"FURFROU",710:"PUMPKABOO",711:"GOURGEIST"}.get(species,"")
	if not prefix.is_empty():
		options=TRIMS if species==676 else SIZES if species in [710,711] else COLORS
		return prefix+"_"+str(options[index]) if index<options.size() else ""
	return str(options[index]) if index<options.size() else ""

static func evolution(g,mon: Dictionary) -> Dictionary:
	if mon.get("held","")=="EVERSTONE":return {}
	var species:=int(mon.species_id)
	var level:=int(mon.level)
	var hour:=int(Time.get_time_dict_from_system().hour)
	var day:=hour>=4 and hour<20
	var target:=0
	var form:=""
	match species:
		664:target=665 if level>=9 else 0
		665:
			if level>=12:
				target=666
				form="SPEWPA_MEADOW"
		669:
			if level>=19:
				target=670
				form=str(mon.get("form","")).replace("FLABEBE_","FLOETTE_")
		674:
			if level>=32 and g.save_data.party.any(func(other):return not other.is_empty() and "dark" in other.get("types",[])):target=675
		677:
			if level>=25:
				target=678
				form="MEOWSTIC_F" if mon.get("sex","male")=="female" else ""
		686:
			if level>=30:
				mon.kalos_turn_ready=true
				g._show_toast("好啦鱿的身体闪起了光。打开 START → 工具 → 倒转掌机。")
		696:target=697 if level>=39 and day else 0
		698:target=699 if level>=39 and not day else 0
		704:target=705 if level>=40 else 0
		705:target=706 if level>=50 and g.world.weather in ["rain","thunderstorm"] else 0
		712:target=713 if level>=37 else 0
		133:
			if int(mon.get("affection",0))>=50 and mon.moves.any(func(id):return Data.move_of(int(id)).get("type","")=="fairy"):target=700
			else:return preload("res://core/growth.gd").evolution_of(mon)
		_:return preload("res://core/growth.gd").evolution_of(mon)
	return {"to":target,"form":form} if target>0 else {}

static func invert(g) -> void:
	var mons: Array=g.save_data.party.filter(func(mon):return mon.get("kalos_turn_ready",false) and int(mon.get("species_id",0))==686 and mon.get("held","")!="EVERSTONE")
	if mons.is_empty():return
	g._pick("倒转掌机",[mons[0].name+"正漂浮在眼前，翻转屏幕","保持方向"],func(i):
		if i!=0:return
		var mon: Dictionary=mons[0]
		if not preload("res://core/party.gd").evolve(mon,687):return
		mon.erase("kalos_turn_ready")
		preload("res://core/dex_variants.gd").record(g.save_data,mon,true)
		g._persist()
		g._dialog(["好啦鱿倒了过来，进化成了乌贼王！"]))

static func weather(mid: String) -> String:
	var day:=int(Time.get_date_dict_from_system().day)
	if mid in ["kalos_14","kalos_19"] and (day+int(mid.trim_prefix("kalos_")))%3!=0:return "rain"
	return ""

static func salon(g) -> void:
	var party: Array=g.save_data.party.filter(func(mon):return int(mon.get("species_id",0))==676)
	if party.is_empty():
		g._dialog(["把多丽米亚带在队伍里，再来挑选造型吧。"],"修剪师")
		return
	g._pick("给哪只多丽米亚修剪？",party.map(func(mon):return "%s　Lv.%d"%[mon.name,mon.level]),func(i):trim_menu(g,party[i]))

static func trim_menu(g,mon: Dictionary) -> void:
	var style:=int(g.save_data.get("kalos_style",0))
	var ids: Array=[1,2,3]
	if style>=10:ids.append_array([7,8,9])
	if style>=50:ids.append_array([4,5,6])
	ids.append(0)
	var choices:=ids.map(func(i):return "恢复自然造型" if i==0 else str(Data.form_of(676,key(676,i)).label))
	choices.append("离开")
	g._pick("多丽米亚美容院　修剪 ¥500",choices,func(i):
		if i>=ids.size():return
		var wanted:=key(676,int(ids[i]))
		if not wanted.is_empty() and int(g.save_data.money)<500:g._dialog(["修剪一次需要 500 元。"]);return
		if not wanted.is_empty():
			g.save_data.money-=500
			g.save_data.kalos_style=mini(255,style+2)
		preload("res://core/party.gd").set_form(mon,wanted)
		if wanted.is_empty():mon.erase("kalos_trim_until")
		else:mon.kalos_trim_until=int(Time.get_unix_time_from_system())+5*86400
		preload("res://core/dex_variants.gd").record(g.save_data,mon,true)
		g._persist()
		g._dialog(["修剪好了！%s摇了摇尾巴。"%mon.name],"修剪师"))
