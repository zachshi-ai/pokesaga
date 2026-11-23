extends RefCounted

const CAST := {"Youngster":"短裤小子","Lass":"迷你裙","Preschooler":"幼儿园小朋友","Schoolboy":"男同学","Schoolgirl":"女同学","Rising Star":"希望训练家","Ace Trainer":"精英训练家","Sky Trainer":"天空训练家","Roller Skater":"轮滑手","Veteran":"资深训练家","Backpacker":"背包客","Battle Girl":"对战少女","Hiker":"登山男","Worker":"工人","Gardener":"园丁","Psychic":"超能力者","Hex Maniac":"灵异迷","Artist":"画家","Tourist":"游客","Swimmer ♀":"泳装女子","Swimmer ♂":"泳装男子","Fisherman":"垂钓者","Furisode Girl":"和服少女","Black Belt":"空手道王","Fairy Tale Girl":"童话少女","Pokémon Breeder":"培育家","Pokémon Ranger":"巡护员","Punk Girl":"不良少女","Punk Guy":"不良少年"}
const GFX := {"Lass":"lass","Beauty":"beauty","Battle Girl":"battle_girl","Black Belt":"blackbelt","Gardener":"breeder","Hiker":"hiker","Worker":"hiker","Fisherman":"fisherman","Fairy Tale Girl":"picnicker","Preschooler":"tuber","Schoolgirl":"lass","Swimmer ♂":"swimmer_m","Swimmer ♀":"swimmer_f","Pokémon Breeder":"breeder","Pokémon Ranger":"ranger","Sky Trainer":"bird_keeper","Ace Trainer":"cooltrainer_m","Roller Skater":"camper","Backpacker":"camper","Artist":"gentleman","Furisode Girl":"aroma_lady","Punk Girl":"battle_girl","Punk Guy":"rocker"}
const PAIRS := ["Ace Duo","Artist Family","Brains & Brawn","Honeymooners","Mysterious Sisters","Poké Fan Family","Punk Couple","Rangers"]
const FACING := {"up":Vector2i.UP,"down":Vector2i.DOWN,"left":Vector2i.LEFT,"right":Vector2i.RIGHT}
static var locations: Dictionary
static var registry: Dictionary

static func roster(map: Dictionary,flags: Dictionary,rows: Array) -> Array:
	var result:=rows.duplicate()
	var anchors: Dictionary=map.get("kalos_anchors",{})
	if map.get("kalos_center",false):
		result.append({"at":anchors.nurse,"name":"护士","heal":true,"facing":"down"})
		result.append({"at":anchors.mart,"name":"店员","shop":true,"kalos_shop":true,"facing":"down"})
	if not flags.get("k_starter",0):return result
	if locations.is_empty():locations=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_route_trainers.json"))
	if registry.is_empty():registry=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_trainers.json"))
	var trainers: Array=locations.get(str(map.id),locations.get(str(int(map.kalos_zone)),[]))
	for i in trainers.size():
		var pos: Array=anchors.get("trainer%d"%(i+1),[])
		if pos.size()!=2:continue
		var id:=str(int(trainers[i]))
		var person: Array=registry.people[id]
		var flag:="k_trainer_"+id
		var label:="%s %s"%[CAST.get(person[1],"训练家"),person[0]]
		var roster_data: Dictionary=registry.y if flags.get("k_version","x")=="y" and registry.y.has(id) else registry.teams
		result.append({"at":pos,"name":label,"gfx":GFX.get(person[1],"youngster"),"facing":["down","left","up","right"][i%4],
			"kalos_trainer":flag,"sky_battle":person[1]=="Sky Trainer","defeated":flags.get(flag,false),
			"battle":{"name":label,"team":roster_data[id],"double":person[1] in PAIRS,"sky_battle":person[1]=="Sky Trainer"},
			"lines":["来一场宝可梦对战吧！"],"post":["下次见面时，让我看看你和伙伴的新招式吧。"]})
	return result

static func talk(g,row: Dictionary) -> bool:
	if not row.has("kalos_trainer"):return false
	if g._flags().get(row.kalos_trainer,false):
		g._dialog(row.post,row.name)
		return true
	if row.battle.double and g.save_data.party.filter(func(mon):return int(mon.get("hp",0))>0).size()<2:
		g._dialog(["我们等两只健康的宝可梦上场，再来打一场双打吧。"],row.name)
		return true
	if row.sky_battle:
		if not g.save_data.party.any(func(mon):return sky_eligible(mon) and int(mon.get("hp",0))>0):
			g._dialog(["这是一场空中对战。请带能在空中飞行的伙伴来。"],row.name)
		else:g._pick("参加空中对战？",["接受挑战","先离开"],func(i):
			if i==0:g._start_battle(row))
		return true
	return false

static func sky_eligible(mon: Dictionary) -> bool:
	var sid:=int(mon.get("species_id",0))
	if sid==0 or sid in [16,21,83,84,85,92,94,163,177,198,225,276,396,441,519,580,587,627,629,661,701]:return false
	return "flying" in Data.stats_of(sid,str(mon.get("form",""))).get("types",[]) or int(mon.get("ability",0))==26

static func challenge(g) -> bool:
	if g.panel_open or not g.cur_story.is_empty() or not g._flags().get("k_starter",0):return false
	for row in g.world.npcs:
		if not row.has("kalos_trainer") or row.defeated or row.sky_battle:continue
		if row.battle.double and g.save_data.party.filter(func(mon):return int(mon.get("hp",0))>0).size()<2:continue
		var pos:=Vector2i(int(row.at[0]),int(row.at[1]))
		for i in 2:
			pos+=Vector2i(FACING[row.facing])
			if pos==g.world.player_pos:
				g.held_dir=""
				g.run_held=false
				g._talk_to_npc(row)
				return true
			if g.world.is_blocked(pos) or not g.world._npc_at(pos).is_empty():break
	return false

static func goods(g) -> Array:
	match g.world.map_data.id:
		"kalos_zone_10":return [{"name":"伤药","category":"heal","price":300}]
		"kalos_zone_11":return [{"name":"精灵球","category":"ball","price":200}]
	var badges:=preload("res://core/region_journey.gd").badges(g.save_data,"kalos").size()
	var stock: Array=[]
	for item in [[0,"精灵球","ball",200],[0,"伤药","heal",300],[0,"解毒药","heal",100],[0,"解麻药","heal",200],[1,"解眠药","heal",250],[1,"灼伤药","heal",250],[1,"解冻药","heal",250],[1,"好伤药","heal",700],[1,"除虫喷雾","other",350],[2,"超级球","ball",600],[3,"活力碎片","heal",1500],[3,"离洞绳","other",550],[3,"白银喷雾","other",500],[4,"高级球","ball",1200],[5,"厉害伤药","heal",1200],[5,"万灵药","heal",600],[6,"黄金喷雾","other",700],[7,"全满药","heal",2500],[8,"全复药","heal",3000]]:
		if badges>=int(item[0]):stock.append({"name":item[1],"category":item[2],"price":item[3]})
	return stock
