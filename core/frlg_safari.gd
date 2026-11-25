extends RefCounted
const UI:=preload("res://scenes/frlg_safari_ui.gd")
const Party:=preload("res://core/party.gd")
const Encounter:=preload("res://core/encounter.gd")
const Dex:=preload("res://core/dex_variants.gd")
const GATE:="safarizone_entrance"

static func site(mid: String) -> bool:
	return (mid.begins_with("safarizone_") and mid!=GATE) or mid.begins_with("safari_zone_")

static func johto_area(mid: String) -> bool:
	return mid.begins_with("hgss_safari_zone_") and mid.trim_prefix("hgss_safari_zone_").is_valid_int()

static func passage(g,dst: Dictionary) -> bool:
	var from: String=g.world.map_data.id
	var to: String=dst.get("map","")
	if from=="hgss_safari_zone_entrance_interior" and to=="hgss_safari_zone_entrance_exterior" and not g.save_data.has("j_safari"):
		if not preload("res://core/johto_safari.gd").open(g._flags()):
			g._dialog(["狩猎地带仍在筹备。先去看看浅葱灯塔里的电龙吧。"],"接待员");return true
		g._pick("狩猎地带门票500元，含30枚原野球。",["入园","取消"],func(index):
			if index!=0:return
			if int(g.save_data.money)<500:
				g._dialog(["门票需要500元。"],"接待员");return
			g.save_data.money-=500
			g.save_data.j_safari={"balls":30}
			g._do_warp(dst)
			g._persist())
		return true
	if from=="hgss_safari_zone_entrance_exterior" and to=="hgss_safari_zone_entrance_interior":
		g.save_data.erase("j_safari")
	if from==GATE and site(to) and not g.save_data.has("fr_safari"):
		var ask=g._dialog(["门票500元。领取30枚原野球，在园内走600步。要入园吗？"],"沙湖乐园")
		ask.ask("入园","离开")
		ask.answered.connect(func(yes):
			if not yes:return
			if int(g.save_data.money)<500:
				g._dialog(["门票需要500元。"],"沙湖乐园")
				return
			g.save_data.money-=500
			g.save_data.fr_safari={"balls":30,"steps":600}
			g._do_warp(dst)
			g._persist())
		return true
	if site(from) and not site(to):g.save_data.erase("fr_safari")
	return false

static func step(g) -> bool:
	if not g.save_data.has("fr_safari") or not site(g.world.map_data.id):return false
	g.save_data.fr_safari.steps-=1
	if int(g.save_data.fr_safari.steps)>0:return false
	finish(g,"六百步到了。请到门口归还剩余的原野球。")
	return true

static func finish(g,msg: String) -> void:
	if johto_area(g.world.map_data.id):
		g.save_data.erase("j_safari")
		g._do_warp({"region":"johto","map":"hgss_safari_zone_entrance_interior","hgss":true,"at":[5,6],"facing":"down"})
	else:
		g.save_data.erase("fr_safari")
		g._do_warp({"region":"kanto","map":GATE,"at":[4,4],"facing":"down"})
	g._persist()
	g._dialog([msg],"沙湖乐园")

static func encounter(g,sid: int,level: int,form: String) -> bool:
	var johto := johto_area(g.world.map_data.id)
	if not johto and not site(g.world.map_data.id):return false
	# A pre-4.57 save already inside the park receives the tools to finish its visit.
	var visit: Dictionary=g.save_data.get_or_add("j_safari",{"balls":30}) if johto else g.save_data.get_or_add("fr_safari",{"balls":30,"steps":600})
	var mon:=Party.make(sid,level,Encounter.moves_for(sid,level),form)
	Party.set_shiny_kind(mon,Party.roll_shiny(g.appearance_rng))
	Dex.record(g.save_data,mon,false)
	var species: Dictionary=Data.species_of(sid)
	var base:=maxi(1,int(species.get("catch_rate",45))*100/1275)
	var flee:=maxi(2,int(preload("res://core/frlg_sidequests.gd").data().safari.get(str(sid),90))*100/1275)
	var state:={"catch":base,"bait":0,"rock":0}
	var ui:=UI.new()
	ui.name="SafariEncounter"
	g.panel_open+=1
	g.menu_layer.add_child(ui)
	g.held_dir=""
	g._set_hud_visible(false)
	ui.setup(mon,"还剩%d枚原野球"%visit.balls if johto else "还剩%d枚原野球　可走%d步"%[visit.balls,visit.steps])
	ui.action_chosen.connect(func(action):
		if ui.is_queued_for_deletion():return
		var done=false
		var message=""
		match action:
			"run":
				done=true
				message="静静离开了。"
			"ball":
				visit.balls-=1
				var odds:=maxi(1,int(state.catch)*1275/100*15/10/3)
				if g.rng.randf()<float(odds)/255.0:
					if johto:mon.johto_safari_caught=true
					var destination=g._store_mon(mon)
					done=true
					message="抓到了%s！%s。"%[mon.name,"加入队伍" if destination=="party" else "已送入电脑"]
				else:message="它挣脱了原野球。"
			"bait":
				state.bait=mini(6,int(state.bait)+g.rng.randi_range(2,6))
				state.rock=0
				state.catch=maxi(3,int(state.catch)/2)
				message="它停下来吃东西。"
			"rock":
				state.rock=mini(6,int(state.rock)+g.rng.randi_range(2,6))
				state.bait=0
				state.catch=mini(20,int(state.catch)*2)
				message="它生气了！"
		if not done:
			var escape:=flee*5
			if int(state.bait)>0:escape=maxi(1,escape/4)
			if int(state.rock)>0:escape=mini(100,escape*2)
			if g.rng.randi_range(0,99)<escape:
				done=true
				message="%s逃走了。"%mon.name
			if int(state.bait)>0:state.bait-=1
			elif int(state.rock)>0:
				state.rock-=1
				if state.rock==0:state.catch=base
		if done or int(visit.balls)==0:
			ui.queue_free()
			g.panel_open=maxi(0,g.panel_open-1)
			g._set_hud_visible(g.panel_open==0)
			if int(visit.balls)==0:finish(g,message+" 原野球已用完。")
			else:g._show_toast(message)
		else:ui.info.text="%s　原野球 %d"%[message,visit.balls]
		g._persist())
	return true
