extends RefCounted
const Party := preload("res://core/party.gd")
const Moves := preload("res://core/galar_moves.gd")
const Hoenn := preload("res://core/hoenn_campaign.gd")
const Dex := preload("res://core/dex_variants.gd")
const Fusion := preload("res://core/fusion.gd")
const RIVALS := ["克拉拉","赛宝利"]
const PRIZES := ["极矿石","极巨菇菇","极巨甜蜜蜜","萝卜种子","雪中冰萝卜","黑色萝卜","牵绊缰绳","传说笔记","铠岛车票","王冠车票"]
static var maps: Dictionary

static func load_events() -> void:
	if not maps.is_empty():return
	var rows: Array=JSON.parse_string(FileAccess.get_file_as_string("res://content/galar_expansion.json"))
	for row in rows:maps.get_or_add(row.map,[]).append(row)

static func available(e: Dictionary,f: Dictionary) -> bool:
	if f.get(e.id,false) or (e.has("unless") and f.get(e.unless,false)):return false
	for key in e.require:
		if not f.get(key,false):return false
	return not e.has("branch") or f.get(e.branch[0],"")==e.branch[1]

static func who(name: String,f: Dictionary) -> String:
	return RIVALS[1 if f.get("g_version","sword")=="shield" else 0] if name=="$rival" else name

static func roster(m: Dictionary,f: Dictionary,base: Array) -> Array:
	load_events()
	var result:=base.duplicate()
	for row in maps.get(m.id,[]):
		if not available(row,f):continue
		var name:=who(row.who,f)
		var actor={"name":name,"at":row.at,"gfx":"expert_m","role":row.id,"local_id":row.id,
			"galar_actor":name,"lines":row.steps[0].say,"facing":"down"}
		result.append(actor)
	if m.id=="galar_stadium" and f.get("dlc_star_invite",false):
		result.append({"name":"丹帝","at":[13,9],"role":"dlc_star","galar_actor":"丹帝","gfx":"expert_m","lines":["明星赛又开幕了！"]})
	if m.id=="galar_wedgehurst_station_room" and f.get("dlc_pass",false):
		result.append({"name":"列车员","at":[3,8],"role":"dlc_station","galar_actor":"列车员","gfx":"devon_employee","lines":["请出示车票。"]})
	if m.id=="armor_dojo" and f.get("dlc_dojo",false):
		result.append({"name":"武馆医务员","at":[11,14],"role":"dlc_heal","gfx":"nurse","heal":true,"lines":["在武馆歇一会儿，我来照顾你们的伙伴。"]})
	if m.id=="armor_dojo" and f.get("dlc_mushrooms",false):
		result.append({"name":"极巨汤师傅","at":[17,14],"role":"dlc_soup","galar_actor":"极巨汤师傅","gfx":"expert_m","lines":["来一碗极巨汤？"]})
	if m.id=="armor_cave" and f.get("dlc_mushrooms",false):
		result.append({"name":"极巨菇菇","at":[14,15],"role":"dlc_forage","galar_actor":"极巨菇菇","gfx":"item_ball","lines":["洞里长出了新菇菇。"]})
	return result

static func gate(target: Dictionary,flags: Dictionary) -> String:
	var mid:=str(target.get("map",""))
	for branch in ["dark","water"]:
		var prefix: String="armor_"+branch+"_floor_"
		if not mid.begins_with(prefix):continue
		if flags.get("dlc_tower","")!=branch:return "先在马士德武馆为熊徒弟选定修行的塔。"
		var layer:=mid.trim_prefix(prefix).to_int()
		if layer>1 and not flags.get("dlc_"+branch+str(layer-1),false):return "先通过本层门生的考验，再往上一层。"
	return ""

static func event(g,kind: String,ctx: Dictionary) -> Dictionary:
	if kind!="talk" or g.world.map_data.get("region","") not in ["galar","armor","crown"]:return {}
	var actor:=str(ctx.get("actor",""))
	if not actor.begins_with("dlc_"):return {}
	if actor in ["dlc_soup","dlc_forage","dlc_station","dlc_star"]:
		return {"who":ctx.get("npc",""),"steps":[{"exp_action":actor.trim_prefix("dlc_")}]}
	load_events()
	for row in maps.get(g.world.map_data.id,[]):
		if actor==row.id and available(row,g._flags()):
			var e: Dictionary=row.duplicate(true)
			e.who=who(e.who,g._flags())
			for step in e.steps:
				if step.has("battle") and step.battle.get("armor_scale",false) and g._flags().get("g_champion",false):
					for foe in step.battle.team:foe.level=int(foe.level)+48
			e.steps.append({"flag":e.id})
			return e
	return {}

static func member(g,sid: int,tag: String="") -> int:
	for i in g.save_data.party.size():
		var m=g.save_data.party[i]
		if m is Dictionary and int(m.get("species_id",0))==sid and (tag=="" or m.get(tag,false)):return i
	return -1

static func mon(sid: int,lv: int,form: String="") -> Dictionary:
	var result:=Party.make(sid,lv,Moves.moves_for(sid,lv,form),form)
	result.berry=""
	return result

static func say(g,text: String) -> void:
	g._dialog([text],str(g.cur_story.get("who",""))).closed.connect(g._story_step,CONNECT_ONE_SHOT)

static func stop(g,text: String) -> void:
	Hoenn.abort_event(g)
	g._dialog([text])

static func choose(g,title: String,labels: Array,callback: Callable) -> void:
	g._pick(title,labels,callback,func():Hoenn.abort_event(g))

static func battle(g,name: String,rows: Array,extra: Dictionary={}) -> void:
	var team: Array=[]
	for row in rows:
		team.append({"species":row[0],"level":row[1],"form":row[2] if row.size()>2 else ""})
	g._story_battle({"name":name,"team":team}.merged(extra,true))

static func grant(g,spec: Dictionary) -> void:
	if not Hoenn.has_room(g.save_data):
		stop(g,"队伍和电脑箱都满了。腾出一个位置，它会等你回来。")
		return
	var gift:=mon(int(spec.species),int(spec.level))
	if spec.has("tag"):gift[spec.tag]=true
	gift.gmax_factor=spec.get("gmax_factor",false)
	var dest: String=g._store_mon(gift)
	say(g,"%s%s。"%[gift.name,"加入了队伍" if dest=="party" else "已送到电脑箱"])

static func consume(g,name: String,n: int=1) -> void:
	for i in n:g._consume_item(name)

static func catch_battle(g,sid: int,lv: int,form: String="") -> void:
	if not Hoenn.has_room(g.save_data):
		stop(g,"腾出一个队伍或电脑箱位置，再来捕捉它。")
		return
	g._story_battle({"wild":true,"must_catch":true,"name":"野生宝可梦","team":[{"species":sid,"level":lv,"form":form}]})

static func prompt(g,a: Dictionary) -> bool:
	if a.has("exp_gift"):
		grant(g,a.exp_gift)
		return true
	if not a.has("exp_action"):return false
	var f: Dictionary=g._flags()
	var sword: bool=f.get("g_version","sword")=="sword"
	var scaled: int=48 if f.get("g_champion",false) else 0
	match str(a.exp_action):
		"star":
			choose(g,"明星赛 · 选择双打搭档",["赫普","玛俐"],func(i):_star(g,i,0))
		"station":
			choose(g,"木杆镇车站 · 选择目的地",["铠岛 · 揖礼原野","王冠雪原 · 滑溜坡"],func(i):
				Hoenn.abort_event(g)
				g._do_warp({"region":["armor","crown"][i],"map":["armor_fields","crown_slope"][i],"at":[[18,12],[21,10]][i]}))
		"rival":
			var round_no:=int(a.round)
			var teams: Array=[[[543,10],[79,12,"SLOWPOKE_GALAR"]],[[79,18,"SLOWPOKE_GALAR"],[109,18],[544,19]],[[451,23],[110,24,"WEEZING_GALAR"],[544,24],[80,25,"SLOWBRO_GALAR"]]] if sword else [[[63,10],[79,12,"SLOWPOKE_GALAR"]],[[79,18,"SLOWPOKE_GALAR"],[64,18],[527,19]],[[77,23,"PONYTA_GALAR"],[64,24],[528,24],[80,25,"SLOWBRO_GALAR"]]]
			var rows: Array=teams[round_no-1]
			for foe in rows:foe[1]=int(foe[1])+mini(48,scaled) - (4 if scaled>0 and round_no==3 else 0)
			battle(g,who("$rival",f),rows,{"galar_power_spot":round_no==3,"galar_ace":80 if round_no==3 else 0,"exp_trial":("poison" if sword else "psychic") if round_no==3 else ""})
		"trial_soup":
			if not f.get("dlc_trial_broth",false):
				if g._bag_count("极巨菇菇")<3:
					stop(g,"先带三朵极巨菇菇回武馆。")
					return true
				consume(g,"极巨菇菇",3)
				f.dlc_trial_broth=true
			g._story_step()
		"starter_gift":
			choose(g,"与哪只宝可梦同行？",["妙蛙种子","杰尼龟"],func(i):grant(g,{"species":[1,7][i],"level":5,"gmax_factor":true}))
		"view":
			if member(g,891,"armor_kubfu")<0:stop(g,"从电脑把马士德送的熊徒弟带进队伍，再一起看风景。")
			else:say(g,"熊徒弟靠在小悠身旁，记住了这里的景色。")
		"tower":
			if not range(1,5).any(func(i):return f.get("dlc_view"+str(i),false)) or member(g,891,"armor_kubfu")<0:
				stop(g,"带着熊徒弟和岛上的门生一起看过风景，再来选塔。")
			else:choose(g,"只能选一座双拳塔",["恶之塔 · 一击流","水之塔 · 连击流"],func(i):
				f.dlc_tower=["dark","water"][i]
				say(g,"去%s找守塔门生吧。"%["恶之塔","水之塔"][i]))
		"kubfu_battle":
			var slot:=member(g,891,"armor_kubfu")
			if slot<0 or int(g.save_data.party[slot].hp)<=0:stop(g,"这是熊徒弟独自接受的考验。带上恢复体力的熊徒弟。")
			else:battle(g,"马士德" if int(a.floor)==5 else "塔中门生",[[int(a.foe),(65 if scaled else 23)+int(a.floor)]],{"exp_kubfu":slot})
		"scroll":
			var slot:=member(g,891,"armor_kubfu")
			if slot<0:stop(g,"请带熊徒弟回来阅读卷轴。")
			else:
				var pupil: Dictionary=g.save_data.party[slot]
				Party.evolve(pupil,892,"URSHIFU_RAPID_STRIKE" if a.style=="water" else "")
				var move_id:=746 if a.style=="water" else 745
				pupil.moves[0]=move_id
				pupil.pp[0]=int(g.get_node("/root/Data").move_of(move_id).get("pp",5))
				Dex.record(g.save_data,pupil,true)
				f.dlc_urshifu=true
				say(g,"读完卷轴，熊徒弟进化成了%s的武道熊师！"%("连击流" if a.style=="water" else "一击流"))
		"forage":
			var steps:=int(f.get("dlc_mush_steps",0))
			if f.has("dlc_last_pick") and steps-int(f.dlc_last_pick)<80:stop(g,"菌柄还没有长好。在岛上再走一段路吧。")
			else:
				g._give_item("极巨菇菇",3)
				f.dlc_last_pick=steps
				say(g,"采到了三朵极巨菇菇。")
		"soup","urshifu_soup":_soup(g,a.exp_action=="urshifu_soup")
		"mustard":
			var other_style: String="" if f.get("dlc_tower","dark")=="water" else "URSHIFU_RAPID_STRIKE"
			battle(g,"马士德",[[620,73],[405,73],[823,74],[745,75],[784,75],[892,75,other_style]],{"galar_power_spot":true,"galar_ace":892,"galar_gmax":true})
		"adventure":_adventure(g,bool(a.get("beast",false)))
		"seeds":
			if g._bag_count("极矿石")<8:stop(g,"交换一袋种子需要八块极矿石。")
			else:
				consume(g,"极矿石",8)
				g._give_item("萝卜种子",1)
				say(g,"收起了萝卜种子。雪田会长出冰萝卜，墓地的土会长出黑萝卜。")
		"plant":
			choose(g,"在这块田播种？",["播种","保留种子"],func(i):
				if i!=0 or g._bag_count("萝卜种子")<1:Hoenn.abort_event(g)
				else:
					consume(g,"萝卜种子")
					f.dlc_horse=a.style
					var carrot: String="雪中冰萝卜" if a.style=="ice" else "黑色萝卜"
					g._give_item(carrot,1)
					say(g,"在丰饶之舞的祝福下，长出了一根"+carrot+"。"))
		"steed":battle(g,"受惊的爱马",[[896 if f.dlc_horse=="ice" else 897,75]])
		"king_capture":
			g.story_queue.push_front({"exp_action":"mount_record"})
			catch_battle(g,898,80,"CALYREX_ICE" if f.dlc_horse=="ice" else "CALYREX_SHADOW")
		"mount_record":
			consume(g,"雪中冰萝卜" if f.dlc_horse=="ice" else "黑色萝卜")
			g._story_step()
		"temple":
			var lead: Dictionary={}
			for p in g.save_data.party:
				if p is Dictionary and not p.is_empty():
					lead=p
					break
			if a.kind=="rock" and lead.get("held","")!="EVERSTONE":stop(g,"让领头的宝可梦携带不变之石，再检查石门。")
			elif a.kind=="ice" and lead.get("species_id",0)!=615:stop(g,"让几何雪花排在队首，再检查石门。")
			elif a.kind=="steel":choose(g,"石门听着你的声音",["吹响口哨","离开"],func(i):
				if i==0:say(g,"回声穿过铁门，巨人醒来了。")
				else:Hoenn.abort_event(g))
			else:g._story_step()
		"split":
			if [377,378,379].any(func(s):return member(g,s)<0):stop(g,"把雷吉洛克、雷吉艾斯和雷吉斯奇鲁同时带到这里。")
			elif f.has("dlc_last_giant"):catch_battle(g,int(f.dlc_last_giant),70)
			else:
				var lamps=preload("res://scenes/galar_ruin_lamps.gd").new()
				g.menu_layer.add_child(lamps)
				g.panel_open+=1
				g._set_hud_visible(false)
				var close:=func():
					lamps.queue_free()
					g.panel_open=maxi(0,int(g.panel_open)-1)
					g._set_hud_visible(true)
				lamps.cancelled.connect(func():
					close.call()
					Hoenn.abort_event(g),CONNECT_ONE_SHOT)
				lamps.solved.connect(func(sid):
					close.call()
					f.dlc_last_giant=sid
					g._persist()
					catch_battle(g,sid,70),CONNECT_ONE_SHOT)
		_:return false
	return true

static func _soup(g,urshifu: bool) -> void:
	var members: Array=[]
	for m in g.save_data.party:
		if not m is Dictionary or m.is_empty():continue
		if urshifu and (m.get("species_id",0)!=892 or not m.get("armor_kubfu",false)):continue
		var forms: Array=g.get_node("/root/Data").forms_of(int(m.species_id))
		if forms.any(func(row):return str(row.get("key","")).ends_with("_GMAX")):members.append(m)
	if members.is_empty():
		stop(g,"带上修行过的武道熊师。" if urshifu else "队伍中没有可以喝极巨汤的宝可梦。")
		return
	choose(g,"哪位伙伴喝极巨汤？",members.map(func(m):return str(m.name)),func(i):
		var chosen: Dictionary=members[i]
		var honey: bool=int(chosen.species_id)==892
		if honey and not urshifu and not g._flags().get("dlc_urshifu_soup",false):
			stop(g,"先带武道熊师去找蜜叶，让它品尝为它准备的第一碗极巨汤。")
			return
		if g._bag_count("极巨菇菇")<3 or (honey and g._bag_count("极巨甜蜜蜜")<1):
			stop(g,"需要三朵极巨菇菇。武道熊师还需要一份极巨甜蜜蜜。")
			return
		consume(g,"极巨菇菇",3)
		if honey:consume(g,"极巨甜蜜蜜")
		chosen.gmax_factor=not chosen.get("gmax_factor",false)
		say(g,"%s%s。"%[chosen.name,"获得了超极巨能量" if chosen.gmax_factor else "恢复为普通极巨化"]))

static func _star(g,choice: int,round_no: int) -> void:
	var rival:=int({810:818,813:812,816:815}.get(int(g._flags().get("g_starter",810)),818))
	var pairings: Array=[
		["亚洛","露璃娜",[275,830,842],[768,847,834]],
		["卡芜","奇巴纳",[38,59,851],[330,844,884]],
		["丹帝","聂梓" if choice==1 else "玛俐",[681,887,6],[560,849,862] if choice==1 else [454,877,861]]]
	var pair: Array=pairings[round_no]
	var team: Array=[]
	var partners: Array=[]
	for sid in ([832,823,rival] if choice==0 else [454,877,861]):
		partners.append({"species":sid,"level":75,"moves":Moves.moves_for(sid,75)})
	for i in 3:
		for side in 2:
			var sid:=int(pair[2+side][i])
			team.append({"species":sid,"level":72+round_no*3,"moves":Moves.moves_for(sid,72+round_no*3),"trainer_group":"first" if side==0 else "second"})
	var config={"double":true,"ally":"galar","ally_team":partners,"team":team,"galar_power_spot":true,
		"galar_ace":int(pair[2][2]),"galar_gmax":true,"prize":0}
	g._start_battle({"name":str(pair[0])+"与"+str(pair[1]),"battle":config},func(outcome):
		if outcome!="a":
			g._heal_party()
			stop(g,"这一届明星赛结束了。整好队伍，可以再来报名。")
			return
		g._heal_party()
		if round_no<2:_star(g,choice,round_no+1)
		else:
			var flags: Dictionary=g._flags()
			flags.dlc_star_wins=int(flags.get("dlc_star_wins",0))+1
			g.save_data.money=int(g.save_data.get("money",0))+(1000000 if int(flags.dlc_star_wins)==1 else 80000)
			say(g,"小悠与%s赢得了明星赛！奖金已到账。"%["赫普","玛俐"][choice]))

static func _adventure(g,beast: bool) -> void:
	var choices:=[260,310,282]
	choose(g,"极巨大冒险 · 租借一只宝可梦",["巨沼怪","雷电兽","沙奈朵"],func(i):
		_adventure_round(g,beast,mon(choices[i],65),0))

static func _adventure_round(g,beast: bool,rental: Dictionary,stage: int) -> void:
	var paths:=[[324,437],[350,460],[621,663]]
	var run_fight:=func(sid: int):
		var boss: Dictionary={"species":sid,"level":70 if stage==3 else 65}
		var cfg: Dictionary={"galar_raid":"adventure","galar_power_spot":true,"team":[boss],"exp_rental":rental,"prize":0,
			"raid_helpers":[[699,65,573],[49,65,405],[80,65,94]]}
		g._start_battle({"name":"极巨巢穴","battle":cfg},func(result):
			if result!="a":
				stop(g,"调查队撤回入口。返还租借宝可梦后，可以再组队出发。")
			elif stage==3:grant(g,{"species":sid,"level":70})
			else:
				choose(g,"下一个巢穴",["保留租借伙伴","换用刚才的宝可梦"],func(i):
					_adventure_round(g,beast,rental if i==0 else mon(sid,65),stage+1)))
	if stage==3:run_fight.call(800 if beast else 245)
	else:
		var fork: Array=paths[stage]
		var data=g.get_node("/root/Data")
		choose(g,"选择巢穴路线　%d / 4"%(stage+1),fork.map(func(s):return str(data.species_of(s).name)),func(i):run_fight.call(fork[i]))

static func use(g,name: String) -> bool:
	if name not in PRIZES or g._bag_count(name)<1:return false
	var f: Dictionary=g._flags()
	if name=="传说笔记":
		var progress: Array=[]
		for clue in [["丰饶之王",["dlc_king_capture"]],["遗迹的巨人",["dlc_split"]],["大树的传说鸟",["dlc_articuno","dlc_zapdos","dlc_moltres"]]]:
			progress.append("%s　%d / %d"%[clue[0],clue[1].filter(func(k):return f.get(k,false)).size(),clue[1].size()])
		g._dialog(progress,"传说笔记")
	elif name=="牵绊缰绳":
		var party: Array=g.save_data.party
		var king:=member(g,898)
		if king<0:g._show_toast("先把蕾冠王带在队伍中。")
		elif party[king].has("fused_part"):
			g._show_toast(Fusion.unfuse(party,king))
			g._persist()
		else:
			var mounts: Array=[896,897].filter(func(s):return member(g,s)>=0)
			if mounts.is_empty():g._show_toast("需要把雪暴马或灵幽马也带在队伍中。")
			else:g._pick("让蕾冠王骑上哪匹马？",mounts.map(func(s):return str(g.get_node("/root/Data").species_of(s).name)),func(i):
				var horse:=int(mounts[i])
				g._show_toast(Fusion.fuse(party,king,member(g,horse),"CALYREX_ICE" if horse==896 else "CALYREX_SHADOW"))
				Dex.record(g.save_data,party[member(g,898)],true)
				g._persist())
	else:
		var tips={"铠岛车票":"在木杆镇车站向列车员出示，乘车前往铠岛。","王冠车票":"在木杆镇车站向列车员出示，乘车前往滑溜坡。","极矿石":"冻凝村的村民用八块极矿石交换萝卜种子。","极巨菇菇":"三朵可以在马士德武馆煮一碗极巨汤。","极巨甜蜜蜜":"和三朵极巨菇菇一起交给武馆的汤师傅。","萝卜种子":"在雪田或古墓旁的田地播种。","雪中冰萝卜":"带上它和牵绊缰绳前往王冠神殿。","黑色萝卜":"带上它和牵绊缰绳前往王冠神殿。"}
		g._dialog([tips[name]],name)
	return true
