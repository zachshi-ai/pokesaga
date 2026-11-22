extends RefCounted

const ISLANDS := {
	"南方孤岛":["无限船票","em_southern_island_exterior",[13,22]],
	"肚脐岩":["神秘船票","em_navel_rock_harbor",[8,4]],
	"诞生之岛":["极光船票","em_birth_island_harbor",[8,4]],
	"最遥远的孤岛":["古航海图","em_faraway_island_entrance",[13,38]]}
const ROCK := [[15,12],[11,14],[15,8],[19,14],[12,11],[18,11],[15,14],[11,14],[19,14],[15,15],[15,10]]
const LIMIT := [4,8,8,8,4,4,4,6,3,3]
const GUARDIANS := {
	"IslandCave_EventScript_Regice":[378,40,"h_regice_open"],
	"DesertRuins_EventScript_Regirock":[377,40,"h_regirock_open"],
	"AncientTomb_EventScript_Registeel":[379,40,"h_registeel_open"],
	"SkyPillar_Top_EventScript_Rayquaza":[384,70,"h_peace"],
	"FarawayIsland_Interior_EventScript_Mew":[151,30,"h_distribution"],
	"NavelRock_Bottom_EventScript_Lugia":[249,70,"h_distribution"]}
const WEATHER := [["114North","114South","115East","115West","116North","116South","118East","118West"],["105North","105South","125East","125West","127North","127South","129East","129West"]]
const BRAILLE := {"hoenn_desert_ruins":"h_regirock_open","em_ancient_tomb":"h_registeel_open","em_island_cave":"h_regice_open"}

static func warp(g, map: String, at: Array) -> void:
	g._do_warp({"region":"hoenn","map":map,"at":at,"hoenn_native":true})
	g._persist()

static func encounter(g, id: int, level: int) -> void:
	if g._flags().get("h_legend_%d"%id,false):return
	var is_roaming: bool=id in [380,381] and level==40
	var mon: Dictionary={}
	if is_roaming:
		mon=g.save_data.get("h_roamer_mon",{})
		if mon.is_empty():
			mon=g.PartyScript.make(id,level,g.EncounterScript.moves_for(id,level))
			g.PartyScript.set_shiny_kind(mon,g.PartyScript.roll_shiny(g.appearance_rng))
			g.save_data.h_roamer_mon=mon
	g._start_wild_battle(id,level,"",func(outcome):
		if outcome in ["a","caught"]:
			g._flags()["h_legend_%d"%id]=true
			if is_roaming:g.save_data.erase("h_roamer_mon")
			if outcome=="caught" and level==50 and id in [380,381]:g._give_bag_item("心之水滴","held","SOUL_DEW")
			if id in [382,383]:g._flags().erase("h_weather_site")
			g.world.refresh_story_actors(g._flags())
			g._persist()
		elif outcome=="b" and g._party_fainted():g._blackout()
		elif is_roaming:
			var routes: Array=preload("res://core/hoenn_base.gd").data().roaming.keys()
			routes.erase(g.world.map_data.id)
			g._flags().h_roaming_map=routes[g.rng.randi_range(0,routes.size()-1)]
			g._persist(),"",0,mon)

static func mirage(g) -> bool:
	var f: Dictionary=g._flags()
	var today:=Time.get_date_string_from_system()
	if f.get("h_mirage_day","")!=today:
		f.h_mirage_day=today
		f.h_mirage_value=g.rng.randi_range(0,65535)
	var present:=false
	for mon in g.save_data.get("party",[]):
		if not (mon is Dictionary) or mon.is_empty():continue
		if not mon.has("h_mirage_pid"):mon.h_mirage_pid=g.appearance_rng.randi_range(0,65535)
		if int(mon.h_mirage_pid)==int(f.h_mirage_value):present=true
	var changed: bool=present!=bool(f.get("h_mirage_today",false))
	f.h_mirage_today=present
	if changed and g.world.map_data.id=="hoenn_130":
		g.world.objects=g.world.map_data.objects.duplicate(true)
		if not present:g.world.objects=g.world.objects.filter(func(o):return o.get("kind","")!="berry_tree")
		g.world._rebuild()
	return present

static func scientist(g) -> void:
	var f: Dictionary=g._flags()
	if not f.get("h_champion",false):g._dialog(["天气研究所一直监测丰缘各地的天气。"]);return
	var choices: Array=[]
	if not f.get("h_legend_383",false):choices.append_array(WEATHER[0])
	if not f.get("h_legend_382",false):choices.append_array(WEATHER[1])
	if choices.is_empty():g._dialog(["丰缘的强烈日照和暴雨都平息了。"]);return
	if not f.has("h_weather_site"):
		f.h_weather_site=choices[g.rng.randi_range(0,choices.size()-1)]
		f.h_weather_steps=0
		g._persist()
	var key:=str(f.h_weather_site)
	var kind: String="异常的强烈日照。岩壁上出现了陆之窟入口" if key in WEATHER[0] else "异常的暴雨。去附近变暗的海面潜水寻找海之窟"
	g._dialog(["%s号道路%s侧出现了%s。"%[key.left(3),{"North":"北","South":"南","East":"东","West":"西"}[key.substr(3)],kind]],"天气研究员")

static func tickets(g) -> void:
	var f: Dictionary=g._flags()
	if not f.get("h_champion",false):g._dialog(["丰缘联盟冠军可以在这里领取学习版的岛屿活动船票。"],"水手");return
	if f.get("h_distribution",false):g._dialog(["在水静港前台出示你持有的船票，即可往返活动岛屿。"],"水手");return
	g._pick("领取离线活动船票和古航海图？",["领取","以后再来"],func(i):
		if i!=0:return
		for island in ISLANDS:
			var name:=str(ISLANDS[island][0])
			if g._bag_count(name)==0:g._give_bag_item(name,"key")
		f.h_distribution=true
		g._persist()
		g._dialog(["收好了。凭船票去前台选目的地，岛上的水手会带你回来。"],"水手"))

static func tv(g) -> void:
	var f: Dictionary=g._flags()
	if not f.get("h_champion",false):g._dialog(["电视里正播放宝可梦新闻。"]);return
	if f.has("h_roaming_species"):
		var line: String="电视台正在回放你的双打比赛。你在采访中说了「%s」。"%f.h_reporter_quote if f.has("h_reporter_quote") else "有训练家在丰缘道路上发现了神秘飞行宝可梦的踪迹。"
		g._dialog([line])
		return
	g._pick("电视上飞过的宝可梦是什么颜色？",["红色","蓝色"],func(i):
		f.h_roaming_species=380 if i==0 else 381
		var routes: Array=preload("res://core/hoenn_base.gd").data().roaming.keys()
		f.h_roaming_map=routes[g.rng.randi_range(0,routes.size()-1)]
		g._persist()
		g._dialog(["新闻说，它正在丰缘各地移动。"],"妈妈"))

static func roam(g) -> int:
	var f: Dictionary=g._flags()
	var species:=int(f.get("h_roaming_species",0))
	if species==0 or f.get("h_legend_%d"%species,false):return 0
	return species if g.world.map_data.id==f.get("h_roaming_map","") and g.rng.randf()<0.25 else 0

static func positions(w, actors: Array) -> void:
	if w.map_data.id=="littleroot_birch_lab":
		for n in actors:
			var k:=str(n.get("source_script","")).get_slice("_EventScript_",1)
			if k in ["Cyndaquil","Totodile","Chikorita"]:n.at=[{"Cyndaquil":8,"Totodile":9,"Chikorita":10}[k],4]
	if w.map_data.id=="em_birth_island_exterior":
		for n in actors:
			if n.get("source_local","")=="LOCALID_BIRTH_ISLAND_EXTERIOR_ROCK":n.at=ROCK[clampi(int(w.taken.get("h_deoxys_rock",0)),0,10)]
	if w.map_data.id=="em_faraway_island_interior":
		for n in actors:
			if n.get("source_script","").ends_with("_Mew"):n.at=w.hoenn_local.get("mew_at",n.at)

static func visibility(row: Dictionary,f: Dictionary) -> int:
	var sc:=str(row.get("source_script",""))
	if sc.begins_with("LittlerootTown_ProfessorBirchsLab_EventScript_") and sc.get_slice("_EventScript_",1) in ["Cyndaquil","Totodile","Chikorita"]:
		return int(f.get("h_johto_starter_offer",false) and not f.get("h_johto_starter_gift",false))
	if GUARDIANS.has(sc):
		var r: Array=GUARDIANS[sc]
		if sc.ends_with("_Rayquaza") and not f.get("h_peace",false):return -1
		return int(f.get(r[2],false) and not f.get("h_legend_%d"%r[0],false))
	if sc.ends_with("_BeldumPokeball") or sc=="MossdeepCity_StevensHouse_EventScript_Letter":
		return int(f.get("h_champion",false) and (not sc.ends_with("_BeldumPokeball") or not f.get("h_beldum",false)))
	match row.get("source_local",""):
		"LOCALID_NAVEL_ROCK_HO_OH":return int(f.get("h_distribution",false) and not f.get("h_legend_250",false))
		"LOCALID_MARINE_CAVE_KYOGRE":return int(f.get("h_champion",false) and not f.get("h_legend_382",false))
		"LOCALID_TERRA_CAVE_GROUDON":return int(f.get("h_champion",false) and not f.get("h_legend_383",false))
		"LOCALID_BIRTH_ISLAND_EXTERIOR_ROCK":return int(f.get("h_distribution",false) and not f.get("h_legend_386",false))
	return -1

static func talk(g, n: Dictionary) -> bool:
	var sc:=str(n.get("source_script",""))
	var f: Dictionary=g._flags()
	if sc=="LittlerootTown_ProfessorBirchsLab_EventScript_Birch" and f.get("h_champion",false):
		if not f.get("h_national_dex",false):
			f.h_national_dex=true
			g._persist()
			g._dialog(["你的丰缘图鉴已经升级为全国图鉴。抓齐丰缘图鉴的200种宝可梦，再来找我。"],"小田卷博士")
		else:
			var owned: Array=g.save_data.get("dex",{}).get("caught",[])
			var need: Array=preload("res://core/hoenn_base.gd").data().regional
			var obtained: Dictionary={}
			for sid in owned:obtained[int(sid)]=true
			var count:=0
			for id in need:
				if obtained.has(int(id)):count+=1
			if count<200:g._dialog(["丰缘图鉴已经收集了%d种。集齐200种，就来研究所一趟。"%count],"小田卷博士")
			elif f.get("h_johto_starter_gift",false):g._dialog(["照顾好新伙伴。"],"小田卷博士")
			else:
				f.h_johto_starter_offer=true
				g.world.refresh_story_actors(f)
				g._persist()
				g._dialog(["恭喜你完成丰缘图鉴！从这三颗精灵球里选一个新伙伴吧。"],"小田卷博士")
		return true
	var starters: Dictionary={"Cyndaquil":155,"Totodile":158,"Chikorita":152}
	var key:=sc.get_slice("_EventScript_",1)
	if sc.begins_with("LittlerootTown_ProfessorBirchsLab_") and starters.has(key) and f.get("h_johto_starter_offer",false) and not f.get("h_johto_starter_gift",false):
		var sid:=int(starters[key])
		g._pick("要选择"+str(g.get_node("/root/Data").species_of(sid).name)+"吗？",["选择","再看看"],func(i):
			if i==0 and g._add_to_team(sid,5)!="full":
				f.h_johto_starter_gift=true
				g.world.refresh_story_actors(f)
				g._persist()
				g._dialog(["新伙伴加入了队伍！"]))
		return true
	if GUARDIANS.has(sc):
		var r: Array=GUARDIANS[sc]
		if not f.get(r[2],false):return false
		encounter(g,r[0],r[1]);return true
	match str(n.get("source_local","")):
		"LOCALID_NAVEL_ROCK_HO_OH":encounter(g,250,70);return true
		"LOCALID_MARINE_CAVE_KYOGRE":encounter(g,382,70);return true
		"LOCALID_TERRA_CAVE_GROUDON":encounter(g,383,70);return true
	if sc=="BirthIsland_Exterior_EventScript_Triangle":
		var stage:=clampi(int(f.get("h_deoxys_rock",0)),0,10)
		if stage>0 and int(f.get("h_deoxys_steps",0))>LIMIT[stage-1]:stage=0
		elif stage==10:
			encounter(g,386,30);return true
		else:stage+=1
		f.h_deoxys_rock=stage
		f.h_deoxys_steps=0
		g.world.refresh_story_actors(f)
		g._persist()
		g._show_toast("三角岩回到了原位。" if stage==0 else "三角岩移动了！")
		return true
	if sc=="PacifidlogTown_House5_EventScript_MirageIslandWatcher":
		var present:=mirage(g)
		g._persist()
		g._dialog(["我看见了！130号水路上有一座岛！" if present else "今天从这里看不到幻之岛。"],"观岛老人")
		return true
	if sc.ends_with("_WeatherScientist"):
		scientist(g);return true
	if sc=="LilycoveCity_Harbor_EventScript_Sailor":
		tickets(g);return true
	for island in ISLANDS:
		if sc.ends_with("_Sailor") and g.world.map_data.id==ISLANDS[island][1]:
			g._pick("返回水静港？",["登船","留在岛上"],func(i):
				if i==0:warp(g,"em_lilycove_city_harbor",[8,11]))
			return true
	if sc.ends_with("_EggWoman"):
		if f.get("h_wynaut",false):g._dialog(["蛋里生出来的宝可梦还好吗？"])
		elif not g.save_data.get("egg",{}).is_empty():g._dialog(["你正照看着别的蛋，等它孵化了再来吧。"])
		else:g._pick("老奶奶递来一颗宝可梦蛋。要收下吗？",["收下","稍后再来"],func(i):
			if i==0:
				g.save_data.egg={"species":360,"steps":5120}
				f.h_wynaut=true
				g._persist()
				g._dialog(["照顾好它。多走一走，就会孵出来的。"]))
		return true
	if sc.ends_with("_BeldumPokeball"):
		if not f.get("h_beldum",false):
			if g._add_to_team(374,5)=="full":g._dialog(["请先给铁哑铃腾出位置。"]);return true
			f.h_beldum=true
			g.world.refresh_story_actors(f)
			g._persist()
			g._dialog(["球里是大吾留下的铁哑铃！"])
		return true
	if sc=="MossdeepCity_StevensHouse_EventScript_Letter":g._dialog(["我出发继续寻找稀有石头了。请好好照顾我留下的铁哑铃。"],"大吾的信");return true
	return false

static func object_action(g, o: Dictionary) -> bool:
	var sc:=str(o.get("source_script",""))
	var f: Dictionary=g._flags()
	if sc=="EmeraldRoamingTV":tv(g);return true
	if sc=="SouthernIsland_Interior_EventScript_TryLatiEncounter":
		if not f.has("h_roaming_species"):g._dialog(["凑近石碑，仿佛听见远处传来电视新闻的声音。先回家看看。"]);return true
		encounter(g,381 if int(f.h_roaming_species)==380 else 380,50);return true
	if sc.begins_with("WeatherDoor"):
		if sc.trim_prefix("WeatherDoor")==str(f.get("h_weather_site","")):
			var at:Array=o.at
			f.h_weather_return={"map":g.world.map_data.id,"at":[at[0],at[1]+1]}
			warp(g,"em_terra_cave_entrance",[8,17])
			return true
		return false
	if sc=="SealedChamber_InnerRoom_EventScript_BrailleBackWall":
		var party: Array=g.save_data.get("party",[]).filter(func(m):return m is Dictionary and not m.is_empty())
		if party.size()>=2 and int(party.front().species_id)==321 and int(party.back().species_id)==369:
			f.h_regi_doors=true
			g._persist()
			g._dialog(["远处传来了三声巨响。三处遗迹的门都打开了。"])
		else:g._dialog(["开头是吼鲸王，最后是古空棘鱼。"])
		return true
	if sc.begins_with("SealedChamber_OuterRoom_EventScript_Braille") and o.at[1]==2:g._dialog(["在这里使用挖洞。从 START 打开秘传菜单。"]);return true
	if sc.contains("_EventScript_CaveEntrance"):
		var map:String=g.world.map_data.id
		if map=="em_island_cave":
			g.world.hoenn_local.regice_lap={"8,21":true}
			g._dialog(["沿墙绕一周，回到起点。中途请勿离开墙边。"])
		elif map=="em_ancient_tomb":g._dialog(["站在洞窟中央，让闪光照亮石室。"])
		elif map=="hoenn_desert_ruins":g._dialog(["先向左两步，再向下两步，在那里使用碎岩。"])
		else:return false
		return true
	return false

static func ritual(g) -> bool:
	var m:String=g.world.map_data.id
	var p:Vector2i=g.world.player_pos
	var f:Dictionary=g._flags()
	var move:=""
	var flag:=""
	if m=="em_sealed_chamber_outer_room" and p.y==3 and p.x in [9,10,11]:
		move="DIG";flag="h_regi_dig"
	elif m=="hoenn_desert_ruins" and p.y==23 and p.x in [5,6,7]:
		move="ROCK_SMASH";flag="h_regirock_open"
	elif m=="em_ancient_tomb" and p==Vector2i(8,25):
		move="FLASH";flag="h_registeel_open"
	if move=="" or f.get(flag,false):return false
	var allowed:bool=g._party_has_move(move) if move=="DIG" else g._party_can_move(move)
	var label:String={"DIG":"挖洞","ROCK_SMASH":"碎岩","FLASH":"闪光"}[move]
	if not allowed:g._dialog(["这里需要能使用%s的伙伴。"%label]);return true
	g._pick("石室对%s产生了反应。"%label,["使用"+label,"离开"],func(i):
		if i==0:
			f[flag]=true
			g.world._rebuild()
			g._persist()
			g._dialog(["石壁轰然移开了！"]))
	return true

static func step(g) -> void:
	var m:Dictionary=g.world.map_data
	var p:Vector2i=g.world.player_pos
	var f:Dictionary=g._flags()
	if m.id=="hoenn_130":mirage(g)
	if m.id in ["em_terra_cave_end","em_marine_cave_end","em_navel_rock_top"]:
		for event in m.get("coord_events",[]):
			if p!=Vector2i(event.x,event.y):continue
			var boss:=int({"TerraCave_End_EventScript_Groudon":383,"MarineCave_End_EventScript_Kyogre":382,"NavelRock_Top_EventScript_HoOh":250}.get(event.get("script",""),0))
			if boss>0 and f.get("h_distribution" if boss==250 else "h_champion",false) and not f.get("h_legend_%d"%boss,false):
				encounter(g,boss,70)
				return
	if m.id=="em_birth_island_exterior":f.h_deoxys_steps=int(f.get("h_deoxys_steps",0))+1
	if m.id=="em_island_cave" and g.world.hoenn_local.has("regice_lap"):
		var lap:Dictionary=g.world.hoenn_local.regice_lap
		var path:Array=m.mechanisms.regice_lap
		if [p.x,p.y] not in path:g.world.hoenn_local.erase("regice_lap")
		else:
			lap["%d,%d"%[p.x,p.y]]=true
			if lap.size()==path.size() and p==Vector2i(8,21):
				f.h_regice_open=true
				g.world.hoenn_local.erase("regice_lap")
				g.world._rebuild()
				g._persist()
				g._dialog(["石壁缓缓打开了。"])
	if m.id=="em_faraway_island_interior" and not f.get("h_legend_151",false):
		mew_step(g)
	if m.id!=f.get("h_roaming_previous","") and f.has("h_roaming_species"):
		var paths: Dictionary=preload("res://core/hoenn_base.gd").data().roaming
		var current:=str(f.get("h_roaming_map",""))
		var roads: Array=paths.keys() if not paths.has(current) or g.rng.randi_range(0,15)==0 else paths[current].duplicate()
		roads.erase(f.get("h_roaming_last",""))
		if not roads.is_empty():f.h_roaming_map=roads[g.rng.randi_range(0,roads.size()-1)]
		f.h_roaming_last=f.get("h_roaming_previous","")
		f.h_roaming_previous=m.id
	if m.get("map_type","") in ["MAP_TYPE_ROUTE","MAP_TYPE_TOWN","MAP_TYPE_CITY","MAP_TYPE_OCEAN_ROUTE"] and f.has("h_weather_site"):
		f.h_weather_steps=int(f.get("h_weather_steps",0))+1
		if f.h_weather_steps>=999:f.erase("h_weather_site")

static func dive(g) -> bool:
	var m:Dictionary=g.world.map_data
	var f:Dictionary=g._flags()
	var site:Dictionary=m.get("mechanisms",{}).get("weather_sites",{}).get(f.get("h_weather_site",""),{})
	var p:Vector2i=g.world.player_pos
	if site.is_empty() or [p.x,p.y] not in site.deep:return false
	if not g._party_can_move("DIVE"):g._dialog([g._field_move_hint("DIVE","潜水")]);return true
	g._pick("暴雨下的海面深不见底。",["下潜","取消"],func(i):
		if i==0:
			f.h_weather_return={"map":m.id,"at":[p.x,p.y]}
			warp(g,"em_underwater_marine_cave",[9,7]))
	return true

static func passage(g, here: String, dest: Dictionary) -> String:
	var f:Dictionary=g._flags()
	if (here=="em_terra_cave_entrance" and str(dest.get("map","")).begins_with("hoenn_")) or (here=="em_underwater_marine_cave" and str(dest.get("map","")).begins_with("em_underwater_route")):
		var back:Dictionary=f.get("h_weather_return",{})
		if not back.is_empty():
			dest.map=back.map
			dest.at=back.at
	if BRAILLE.has(dest.get("map","")):
		var map:String=dest.map
		if here!=map and not f.get("h_regi_doors",false):return "遗迹的大门还没有打开。"
		if here==map and int(dest.at[1])<15 and not f.get(BRAILLE[map],false):return "墙上的盲文似乎藏着秘密。"
	if dest.get("map","")=="em_sealed_chamber_inner_room" and not f.get("h_regi_dig",false):return "盲文墙仍然封闭着。"
	return ""


static func mew_step(g) -> void:
	var w=g.world
	var here: Vector2i=w.player_pos
	var grass: Array=w.map_data.physics.grass
	if not int(grass[here.y][here.x]):return
	var ticks:=int(w.hoenn_local.get("mew_steps",0))+1
	w.hoenn_local.mew_steps=ticks
	var pos:Array=w.hoenn_local.get("mew_at",[13,15])
	var old:=Vector2i(pos[0],pos[1])
	if ticks%9!=0:
		var best:=old
		var best_dist:=-1
		var choices: Array=[Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT]
		for i in 4:
			var cell:Vector2i=old+choices[(ticks+i)%4]
			if cell==here or cell.x<0 or cell.y<0 or cell.y>=grass.size() or cell.x>=grass[cell.y].size() or not int(grass[cell.y][cell.x]) or w.blocked_by_terrain(cell):continue
			var dist:=cell.distance_squared_to(here)
			if dist>best_dist:best=cell;best_dist=dist
		w.hoenn_local.mew_at=[best.x,best.y]
	w.refresh_story_actors(g._flags())
	for i in w.npcs.size():
		if w.npcs[i].get("source_local","")=="LOCALID_FARAWAY_ISLAND_MEW":
			w._npc_nodes[i*2+1].visible=ticks%8==0
			w._npc_nodes[i*2].visible=ticks%8==0
