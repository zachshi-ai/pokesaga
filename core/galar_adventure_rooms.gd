extends RefCounted
## Solo Max Lair route. The active rental and branch progress share the normal save.
const CAMP := "crown_max_lair"
const PREFIX := "crown_adventure_"
const PATHS := [[324,437],[350,460],[621,663]]

static func to(g,mid:String,at:Array)->void:
	g._do_warp({"region":"crown","map":mid,"at":at,"facing":"up"})

static func start(g,beast:bool,replay:bool,partner:Dictionary)->void:
	preload("res://core/hoenn_campaign.gd").abort_event(g)
	g._flags().dlc_field_adventure={"stage":1,"beast":beast,"replay":replay,"rental":partner,"found":[],"defeated":""}
	to(g,PREFIX+"fork_1",[12,15])

static func gate(mid:String,f:Dictionary)->String:
	if not mid.begins_with(PREFIX):return ""
	var run:Dictionary=f.get("dlc_field_adventure",{})
	if run.is_empty():return "先向营地调查员借一只宝可梦，再进入极巨大冒险。"
	var part:=mid.trim_prefix(PREFIX)
	var floor_no:=4 if part=="nest" else int(part.get_slice("_",1) if part.begins_with("fork_") else part.get_slice("_",0))
	if int(run.stage)!=floor_no:return "先完成当前支洞的调查，再往深处走。"
	return ""

static func leave(g)->void:
	g._flags().erase("dlc_field_adventure")
	g._persist()

static func give(g,sid:int,level:int)->void:
	var expansion=load("res://core/galar_expansion.gd")
	var mon:Dictionary=expansion.mon(sid,level)
	var dest:String=g._store_mon(mon)
	g._persist()
	g._dialog(["%s%s。"%[mon.name,"加入了队伍" if dest=="party" else "已送入电脑箱"]],"巢穴调查员")

static func finish(g)->void:
	var run:Dictionary=g._flags().dlc_field_adventure
	if not preload("res://core/hoenn_campaign.gd").has_room(g.save_data):
		g._dialog(["队伍和电脑箱已满。腾出位置后，再与调查目标交谈领取伙伴。"]);return
	var saved:=run.duplicate(true)
	var end_id:=800 if saved.beast else 245
	if not saved.replay:
		g._flags()["dlc_beast" if saved.beast else "dlc_lair"]=true
	leave(g)
	to(g,CAMP,[14,5])
	if not saved.replay:
		give(g,end_id,70)
		return
	var labels:Array=saved.found.map(func(s):return str(g.get_node("/root/Data").species_of(s).name))
	labels.append("全部放归")
	g._pick("从本次调查带回一只",labels,func(i):
		if i<saved.found.size():give(g,int(saved.found[i]),65)
		else:g._dialog(["调查记录已交回营地。"]))

static func advance(g,sid:int,swap:bool)->void:
	var run:Dictionary=g._flags().dlc_field_adventure
	if swap:run.rental=load("res://core/galar_expansion.gd").mon(sid,65)
	run.stage=int(run.stage)+1
	run.defeated=""
	to(g,PREFIX+"nest" if int(run.stage)==4 else PREFIX+"fork_"+str(run.stage),[13,16] if int(run.stage)==4 else [12,15])

static func offer_swap(g,sid:int)->void:
	g._pick("前往下一层",["保留租借伙伴","换用刚才的宝可梦"],func(i):advance(g,sid,i==1))

static func fight(g)->bool:
	var mid:String=g.world.map_data.id
	var f:Dictionary=g._flags()
	if not gate(mid,f).is_empty():return false
	var run:Dictionary=f.dlc_field_adventure
	var stage:int=run.stage
	var boss:=stage==4
	var sid:int=(800 if run.beast else 245) if boss else PATHS[stage-1][1 if mid.ends_with("_right") else 0]
	if run.defeated==mid:
		if boss:finish(g)
		else:offer_swap(g,sid)
		return true
	var cfg={"galar_raid":"adventure","galar_power_spot":true,"team":[{"species":sid,"level":70 if boss else 65}],"exp_rental":run.rental,"prize":0,"raid_helpers":[[699,65,573],[49,65,405],[80,65,94]]}
	g._start_battle({"name":"极巨巢穴","battle":cfg},func(result):
		if result!="a":
			leave(g);to(g,CAMP,[14,5]);g._dialog(["调查队撤回营地，已返还租借宝可梦。"])
			return
		run.defeated=mid
		if not boss:run.found.append(sid)
		g._persist()
		if boss:finish(g)
		else:offer_swap(g,sid))
	return true
