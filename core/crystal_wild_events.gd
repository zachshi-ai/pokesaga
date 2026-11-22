extends RefCounted
const LENGTHS:=[[110,1],[310,2],[710,4],[2710,20],[7710,50],[17710,100],[32710,150],[47710,150],[57710,100],[62710,50],[64710,20],[65210,5],[65410,2],[65510,1]]
const ASLEEP_DAY:=[48,163,164,167,214]
const ASLEEP_NIGHT:=[10,11,12,13,14,15,21,23,102,165,190]

static func trainer(g)->int:
	if not g.save_data.has("js_trainer_id"):
		g.save_data.js_trainer_id=g.rng.randi_range(0,65535)
		g._persist()
	return int(g.save_data.js_trainer_id)

static func rotate(n:int,k:int)->int:return ((n>>k)|(n<<(8-k)))&255

static func inches(dvs:int,ot:int)->int:
	var b:=rotate(dvs>>8,2)^rotate(ot>>8,1)
	var c:=rotate(dvs&255,2)^rotate(ot&255,1)
	var v:=b*256+c
	var mm:=0
	if v<10:mm=190+v
	elif b==255:mm=1370+c
	else:
		# Crystal's original comparison only tests the high byte. The
		# 16-bit subtraction and low byte of the quotient wrap like the cartridge.
		for i in LENGTHS.size():
			var threshold:=int(LENGTHS[i][0])
			if b>=threshold>>8:continue
			mm=(i+2)*100+((((v-threshold)&65535)/int(LENGTHS[i][1]))&255)
			break
	return mm*10/254

static func magikarp(g,who:String):
	var flags:Dictionary=g._flags()
	if not flags.get("j_plant_clear",false):
		g._dialog(["这片湖里以前总能见到鲤鱼王。最近湖边来了穿黑衣服的人。"],who);return
	if not flags.get("js_measure_karp",false):
		flags.js_measure_karp=true;g._persist();g._dialog(["我想看看世上最长的鲤鱼王！带一只过来，让我替它量量。"],who);return
	var best:=int(flags.get("js_karp_inches",42))
	preload("res://core/crystal_sidequests.gd").choose_partner(g,"纪录 %d英尺%d英寸　测量哪只鲤鱼王？"%[best/12,best%12],func(p):return int(p.species_id)==129,func(slot):
		var p:Dictionary=g.save_data.party[slot]
		if not p.has("js_dvs"):p.js_dvs=g.rng.randi_range(0,65535)
		var size:=inches(int(p.js_dvs),int(p.get("ot_id",trainer(g))))
		var words:="这只量得%d英尺%d英寸。"%[size/12,size%12]
		if size>best:
			flags.js_karp_inches=size;flags.js_karp_trainer=p.get("ot","小悠")
			g._give_item("PP 多项小补剂",1,"other");words+="创造了新纪录！获得了PP多项小补剂。"
		else:words+="原来的纪录仍然保持。"
		g._persist();g._dialog([words],who))

static func tree(g)->bool:
	var room:Dictionary=g.world.map_data
	if not room.has("hgss") or not g._party_has_move("HEADBUTT"):return false
	var tile:Vector2i=g.world.player_pos+g.world._dir_vec()
	if (preload("res://core/hgss_field.gd").word(room.hgss,tile)&255)!=6:return false
	var d:Dictionary=preload("res://core/crystal_sidequests.gd").data()
	var key:String=d.tree_maps.get(str(room.id).trim_prefix("johto_"),"")
	if not d.tree_sets.has(key) or key=="rock":return false
	g._pick("让伙伴用头锤摇动树干？",["使用头锤","离开"],func(i):
		if i!=0:return
		var diff:=posmod((tile.x*tile.y+tile.x+tile.y)/5-trainer(g),10)
		var odds:=8 if diff==0 else (5 if diff<5 else 1)
		if g.rng.randi_range(0,9)>=odds:g._dialog(["树叶沙沙作响，这次什么也没有掉下来。"]);return
		var group:Array=d.tree_sets[key][1 if diff==0 else 0]
		var chance:int=g.rng.randi_range(1,100)
		for row in group:
			chance-=int(row[0])
			if chance>0:continue
			g._start_wild_battle(int(row[1]),int(row[2]))
			var sleepy:Array=ASLEEP_NIGHT if g._is_night() else ASLEEP_DAY
			if row[1] in sleepy and is_instance_valid(g.active_battle):
				g.active_battle.battle.cur_b().status="slp";g.active_battle.battle.cur_b().status_turns=7
			return)
	return true


static func rock(g)->bool:
	var room:String=g.world.map_data.get("id","")
	if room not in ["johto_cianwood_city","johto_route_40","johto_dark_cave_violet_entrance","johto_slowpoke_well_b1_f"]:return false
	if g.rng.randi_range(0,9)>=4:return false
	var species:=98 if g.rng.randi_range(1,100)<=90 else 213
	g._start_wild_battle(species,15)
	return true
