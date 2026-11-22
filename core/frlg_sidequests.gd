extends RefCounted
## FireRed field events using original script identities and projected map coordinates.
const Party := preload("res://core/party.gd")
const Encounter := preload("res://core/encounter.gd")
const Dex := preload("res://core/dex_variants.gd")
const TRI := [[15,12],[11,14],[15,8],[19,14],[12,11],[18,11],[15,14],[11,14],[19,14],[15,15],[15,10]]
const CAPS := [4,8,8,8,4,4,4,6,3,3]
const SEALS := [[7,2],[4,4],[10,4],[5,6],[9,6],[5,8],[9,8]]
const CHAMBERS := {"monean":"AAAAAAAAAAA?","liptoo":"CCCDDDHHHUUO","weepth":"NNNNSSSSIIEE","dilford":"PPLLJJRRRQQQ","scufib":"YYTTGGGFFFKK","rixy":"VVVWWWXXMMBB","viapois":"ZZZZZZZZZZZ!"}
const LAND_WEIGHTS := [20,20,10,10,10,10,5,5,4,4,1,1]
static var catalog: Dictionary
static func data() -> Dictionary:
	if catalog.is_empty(): catalog=JSON.parse_string(FileAccess.get_file_as_string("res://content/frlg_sidequests.json"))
	return catalog

static func roster(m: Dictionary, flags: Dictionary, live: Array) -> Array:
	var binding: Dictionary=data().actors.get("%s/%s"%[m.region,m.id],{})
	if m.id.begins_with("trainer_tower_") and preload("res://core/frlg_tower.gd").floor_of(m.id)>0:
		return preload("res://core/frlg_tower.gd").roster(m.id,flags,live,data().tower)
	var result: Array=preload("res://core/frlg_fame.gd").roster(m,flags,live.duplicate(true),data().fame.get("%s/%s"%[m.region,m.id],{}))
	if binding.is_empty():return result
	for row in binding.values():
		var original: Array=row.at
		var actor: Dictionary={}
		# Some original actors are hidden by placeholder story flags. Their side
		# quest below supplies the actual visibility and replaces that placeholder.
		for i in range(result.size()-1,-1,-1):
			if result[i].at==original:
				actor=result[i]
				result.remove_at(i)
		var action: Array=row.side
		var flag: String=row.flag
		if action[0]=="fan" and action[3] and not flags.get("kanto_champion",false):continue
		if action[0]=="doll" and int(flags.get("fr_hof_count",0))<int(action[3]):continue
		if (action[0] in ["wild","gift_mon","dojo_gift","triangle"] and flags.get(flag,false)) or (action[0]=="triangle" and flags.get("fr_deoxys_done",false)):continue
		if actor.is_empty():actor={"at":original,"gfx":"man","lines":[]}
		actor.side=action
		actor.side_flag=flag
		actor.name=action[1]
		if row.has("gfx"):
			actor.gfx=row.gfx
			actor.field_art=row.gfx
		if action[0]=="triangle":
			actor.at=TRI[clampi(int(flags.get("fr_triangle_stage",0)),0,10)]
			if flags.get("fr_deoxys_awake",false): actor.name="代欧奇希斯"
		if action[0]=="prospector" and not flags.get("national_dex",false):actor.at=[6,3]
		if action[0]=="dojo":
			actor.name="空手道师父" if row.source.ends_with("MasterKoichi") else "空手道弟子 · "+str(row.source).get_slice("EventScript_",1)
			actor.erase("battle") # The victory callback unlocks the gift once.
		result.append(actor)
	if m.id=="birth_island_exterior":
		result=result.filter(func(n):return n.at!=[15,3] or n.has("side"))
	return result

static func say(g, text: String, who: String) -> void:
	g._dialog([text],who)

static func change(g, flag: String) -> void:
	g._flags()[flag]=true
	g.world.refresh_story_actors(g._flags())
	g._apply_defeated()
	g._persist()

static func gift(g, flag: String, item: String, category: String, who: String, held := "") -> void:
	if g._flags().get(flag,false):
		say(g,"之前送给你的%s派上用场了吗？"%item,who)
		return
	if held=="":g._give_item(item,1,category)
	else:g._give_bag_item(item,"held",held)
	change(g,flag)
	say(g,"请收下%s。"%item,who)

static func pick_party(g,title: String, accept: Callable, selected: Callable) -> void:
	var slots: Array=[]
	var labels: Array=[]
	for slot in g.save_data.party.size():
		var mon=g.save_data.party[slot]
		if mon is Dictionary and not mon.is_empty() and accept.call(mon):
			slots.append(slot)
			labels.append("%s  Lv.%d"%[mon.name,mon.level])
	if slots.is_empty():
		say(g,"现在的队伍里没有符合条件的伙伴。",title)
		return
	g._pick(title,labels,func(i):selected.call(slots[i]))

static func teach(g, move: int, flag: String, eligible: Array, who: String, payment := "") -> void:
	if flag!="" and g._flags().get(flag,false):
		say(g,"我已经把这一招传给你的伙伴了。",who)
		return
	var title="传授"+str(Data.move_of(move).name)
	pick_party(g,title,func(mon):return (eligible.is_empty() or eligible.any(func(id):return int(id)==int(mon.species_id))) and not mon.moves.has(move),
		func(slot):g._tm_teach_one(move,slot,Data.move_of(move).name,true,func():
			if payment!="":
				for n in (2 if payment=="小蘑菇" else 1):g._consume_item(payment)
			if flag!="":g._flags()[flag]=true))

const CAPE_MOVES := {3:338,6:307,9:308}

static func cape_tutor(g, old_flag: String, who: String) -> void:
	var f: Dictionary=g._flags()
	if f.get(old_flag,false):
		# The first implementation recorded one shared flag. Recover the move
		# when the taught starter still has it, including stored partners.
		var owned: Array=g.save_data.party+g.save_data.get("box",[])
		for box in g.save_data.get("boxes",[]):
			if box is Dictionary:owned.append_array(box.get("mons",[]))
		for mon in owned:
			if not mon is Dictionary:continue
			var known: int=CAPE_MOVES.get(int(mon.get("species_id",0)),0)
			if known>0 and mon.get("moves",[]).has(known):f["fr_cape_move_%d"%known]=true
		f.erase(old_flag)
		g._persist()
	var lead:=lead_mon(g)
	var move: int=CAPE_MOVES.get(int(lead.get("species_id",0)),0)
	if move==0 or int(lead.get("friendship",0))!=255:
		say(g,"让最信赖你的妙蛙花、喷火龙或水箭龟走在队首，再来找我。",who)
		return
	var learned:="fr_cape_move_%d"%move
	var label: String=Data.move_of(move).name
	if f.get(learned,false):
		say(g,"我已经传授过%s了。"%label,who)
		return
	g._pick("传授队首的%s「%s」？"%[lead.name,label],["传授","离开"],func(i):
		if i==0:g._tm_teach_one(move,g.save_data.party.find(lead),label,true,func():f[learned]=true))

static func remind(g,who: String) -> void:
	var payment=""
	if g._bag_count("小蘑菇")>=2:payment="小蘑菇"
	elif g._bag_count("大蘑菇")>=1:payment="大蘑菇"
	else:
		say(g,"带两枚小蘑菇或一枚大蘑菇来，我可以帮伙伴想起成长中学过的一招。",who)
		return
	pick_party(g,"想让谁回忆招式？",func(_mon):return true,func(slot):
		var mon: Dictionary=g.save_data.party[slot]
		var moves: Array=[]
		for pair in Data.species_of(mon.species_id).get("learnset",[]):
			if int(pair[0])<=int(mon.level) and not mon.moves.has(pair[1]) and not moves.has(pair[1]):moves.append(pair[1])
		if moves.is_empty():
			say(g,"这位伙伴现在没有可以回忆的招式。",who)
			return
		g._pick("选择要回忆的招式",moves.map(func(mid):return Data.move_of(mid).name),func(index):
			var mv: int=moves[index]
			g._tm_teach_one(mv,slot,Data.move_of(mv).name,true,func():
				for n in (2 if payment=="小蘑菇" else 1):g._consume_item(payment))))

static func trade(g,a: Array,flag: String) -> void:
	var previous: int=g._flags().get(flag+"_offered",a[2])
	if a.size()>7 and g._flags().get("fr_leaf_tables",false):a=a.slice(0,2)+a[7]
	var who: String=a[1]
	if g._flags().get(flag,false):
		say(g,"谢谢你的%s，它在这里过得很好。"%Data.species_of(previous).name,who)
		return
	var wanted: int=a[2]
	var received: int=a[3]
	g._pick("用%s交换我的%s？"%[Data.species_of(wanted).name,Data.species_of(received).name],["交换","离开"],func(i):
		if i!=0:return
		pick_party(g,"选择送出的伙伴",func(mon):return int(mon.species_id)==wanted,func(slot):
			var old: Dictionary=g.save_data.party[slot]
			var mon:=Party.make(received,int(old.level),Encounter.moves_for(received,int(old.level)))
			mon.nickname=a[4]
			mon.original_trainer=a[5]
			mon.held="" if a[6]=="NONE" else a[6]
			g.save_data.party[slot]=mon
			Dex.record(g.save_data,mon,true)
			g._flags()[flag+"_offered"]=wanted
			change(g,flag)
			say(g,"交换完成！%s（%s）加入队伍。"%[mon.name,a[4]],who)))

static func static_battle(g,sid: int,level: int,flag: String, form := "") -> void:
	if not g._has_party():
		say(g,"先带上能够战斗的伙伴。","")
		return
	g._start_wild_battle(sid,level,form,func(result):
		if result in ["a","caught"]:change(g,flag)
		elif result=="b" and g._party_fainted():g._blackout())

static func triangle(g) -> void:
	var f: Dictionary=g._flags()
	if f.get("fr_deoxys_awake",false):
		static_battle(g,386,30,"fr_deoxys_done","DEOXYS_DEFENSE" if f.get("fr_leaf_tables",false) else "DEOXYS_ATTACK")
		return
	var stage: int=f.get("fr_triangle_stage",0)
	var steps: int=f.get("fr_triangle_steps",0)
	f.fr_triangle_steps=0
	if stage>0 and steps>CAPS[stage-1]:
		f.fr_triangle_stage=0
		g._show_toast("三角石失去了光芒，回到了起点。")
	elif stage==10:
		change(g,"fr_deoxys_awake")
		static_battle(g,386,30,"fr_deoxys_done","DEOXYS_DEFENSE" if f.get("fr_leaf_tables",false) else "DEOXYS_ATTACK")
		return
	else:
		f.fr_triangle_stage=stage+1
		g.snd.play_sfx("switch")
	g.world.refresh_story_actors(f)
	g._persist()

static func arrive_step(g) -> void:
	var mid: String=g.world.map_data.id
	if g._flags().get("kanto_champion",false):g._flags().fr_groom_steps=mini(500,int(g._flags().get("fr_groom_steps",500))+1)
	if mid=="birth_island_exterior" and g._flags().get("fr_triangle_stage",0)>0:g._flags().fr_triangle_steps=int(g._flags().get("fr_triangle_steps",0))+1
	if mid=="navel_rock_summit" and g.world.player_pos==Vector2i(9,12):
		var bird: Dictionary=g.world._npc_at(Vector2i(9,6))
		if bird.has("side"):static_battle(g,250,70,bird.side_flag)

static func after_push(g) -> void:
	if g.world.map_data.id!="seven_island_sevault_canyon_tanoby_key" or g._flags().get("fr_tanoby",false):return
	for p in SEALS:
		if g.world.object_ref(Vector2i(p[0],p[1])).get("kind","")!="boulder":return
	change(g,"fr_tanoby")
	say(g,"七块石头同时压下石盘。海上遗迹深处传来一阵轰鸣。","")

static func unown(g) -> String:
	var room: String=g.world.map_data.id
	for chamber in CHAMBERS:
		if not room.contains(chamber+"_chamber"): continue
		if not g._flags().get("fr_tanoby",false):return "locked"
		var roll: int=g.rng.randi_range(0,99)
		for i in LAND_WEIGHTS.size():
			roll-=LAND_WEIGHTS[i]
			if roll<0:
				var letter: String=CHAMBERS[chamber][i]
				if letter=="?":return "UNOWN_QUESTION"
				if letter=="!":return "UNOWN_EXCLAMATION"
				return "UNOWN_"+letter
	return ""

static func interact(g,npc: Dictionary) -> bool:
	preload("res://core/frlg_fame.gd").speaker(g,npc)
	if not npc.has("side"):return false
	var a: Array=npc.side
	var who: String=a[1]
	var f: Dictionary=g._flags()
	var flag: String=npc.side_flag
	match a[0]:
		"tower_desk","tower_owner","tower_fight","tower_done":preload("res://core/frlg_tower.gd").talk(g,a,data().tower)
		"doll_clerk":g._open_shop()
		"trade":trade(g,a,flag)
		"comparison":
			g._pick("关都支线版本　交换、游戏角奖品与代欧奇希斯",["火红","叶绿"],func(i):
				f.fr_leaf_tables=i==1
				g._persist()
				say(g,"已切换到%s。已完成的交换与捕获仍保存在同一份图鉴。"%("叶绿" if i==1 else "火红"),who))
		"diploma":show_diploma(g)
		"gift_item":gift(g,flag,a[2],a[3],who)
		"map":
			if not f.get("got_dex",false):say(g,"爷爷在研究所等你呢。",who)
			elif f.get("kanto_champion",false) and f.get("fr_town_map",false):
				if f.get("fr_groom_steps",500)<500:say(g,"走在最前面的伙伴对你的亲密度是 %d。"%int(lead_mon(g).get("friendship",0)),who)
				else:pick_party(g,"要帮哪位伙伴梳毛？",func(_m):return true,func(slot):
					var mon: Dictionary=g.save_data.party[slot]
					mon.friendship=mini(255,int(mon.friendship)+3)
					f.fr_groom_steps=0
					g._persist()
					say(g,"%s很享受这次梳理。"%mon.name,who))
			else:gift(g,"fr_town_map","城镇地图","key",who)
		"aide":
			var count=preload("res://core/kanto_campaign.gd").caught_species_count(g.save_data)
			if not f.get("got_dex",false) or count<int(a[2]):say(g,"登记捕获%d种关都宝可梦就能领%s。你目前登记了%d种。"%[a[2],a[3],count],who)
			else:gift(g,flag,a[3],"key",who,a[4])
		"buy_mon","gift_mon","dojo_gift":
			if f.get(flag,false):
				say(g,"你的伙伴还好吗？",who)
			elif a[0]=="dojo_gift" and (not f.get("fr_dojo_win",false) or f.get("fr_dojo_chosen",false)):
				say(g,"获胜后可以从两只宝可梦中选择一只。",who)
			else:
				var price: int=a[4] if a.size()>4 else 0
				g._pick(("花%d元购买" % price if price else "领取")+str(Data.species_of(a[2]).name)+"？",["确定","离开"],func(i):
					if i!=0:return
					if int(g.save_data.money)<price:
						say(g,"钱还不够。",who)
						return
					g.save_data.money-=price
					var dest=g._add_to_team(a[2],a[3])
					if a[0]=="dojo_gift":f.fr_dojo_chosen=true
					change(g,flag)
					say(g,"%s%s。"%[Data.species_of(a[2]).name,"加入了队伍" if dest=="party" else "被送往电脑"],who))
		"dojo":
			if f.get(flag,false):say(g,"师父落败后，可以去后面的精灵球挑一位伙伴。",who)
			elif g._has_party():
				var trainer: Dictionary=npc.duplicate(true)
				trainer.battle={"team":a[2]}
				g._start_battle(trainer,func(result):
					if result=="a":
						if flag.ends_with("MasterKoichi"):f.fr_dojo_win=true
						change(g,flag)
					elif result=="b" and g._party_fainted():g._blackout())
			else:say(g,"带上伙伴来挑战吧。",who)
		"wild":static_battle(g,a[2],a[3],flag)
		"triangle":triangle(g)
		"tutor","copycat":
			var mv: int=102 if a[0]=="copycat" else a[2]
			if a[0]=="copycat" and not f.get("fr_copycat_doll",false):
				if g._bag_count("皮皮玩偶")>0:
					g._pick("把皮皮玩偶送给模仿少女？",["送给她","留着"],func(i):
						if i==0:
							g._consume_item("皮皮玩偶")
							change(g,"fr_copycat_doll")
							teach(g,mv,flag,data().tutor_compatibility.get(str(mv),[]),who))
				else:say(g,"我好想要一个皮皮玩偶！玉虹百货有卖。",who)
			else:teach(g,mv,flag,data().tutor_compatibility.get(str(mv),[]),who)
		"starter_tutor":cape_tutor(g,flag,who)
		"relearn":remind(g,who)
		"delete_move":
			pick_party(g,"哪位伙伴想忘掉招式？",func(mon):return mon.moves.size()>1,func(slot):
				var mon: Dictionary=g.save_data.party[slot]
				g._pick("选择要忘记的招式",mon.moves.map(func(mid):return Data.move_of(mid).name),func(i):
					mon.moves.remove_at(i)
					if i<mon.pp.size():mon.pp.remove_at(i)
					if i<mon.get("pp_ups",[]).size():mon.pp_ups.remove_at(i)
					g._persist()
					say(g,"已经忘掉那一招了。",who)))
		"egg":
			if f.get(flag,false):say(g,"那颗蛋长得怎么样了？",who)
			elif int(lead_mon(g).get("friendship",0))!=255:say(g,"让我看看排在最前面的伙伴。等它完全信赖你的时候再来。",who)
			elif Party.occupied(g.save_data.party)>=Party.MAX_SIZE or not g.save_data.get("egg",{}).is_empty():say(g,"为蛋腾出一个位置再过来吧。",who)
			else:
				g.save_data.egg={"species":175,"steps":2560}
				change(g,flag)
				say(g,"这颗波克比的蛋就托付给你了。走路时带上它吧。",who)
		"prospector":
			if f.get("national_dex",false):gift(g,flag,"金珠","other",who)
			else:say(g,"这条矿道还没挖通。等我找到金子，再来看看吧。",who)
		"memorial_man":say(g,"我的大岩蛇安息在这里。它生前最喜欢喝柠檬汁。",who)
		"dance":
			g._heal_party()
			say(g,"和吉利蛋一起跳完舞，伙伴的体力与招式次数都恢复了。",who)
		"size_contest":
			if a[2]==129 and g._bag_count("厉害钓竿")==0:return false
			pick_party(g,"选择参加测量的"+str(Data.species_of(a[2]).name),func(mon):return int(mon.species_id)==int(a[2]),func(slot):
				var mon: Dictionary=g.save_data.party[slot]
				if not mon.has("fr_size_hash"):mon.fr_size_hash=g.rng.randi_range(0,65535)
				var height:=size_mm(int(a[2]),int(mon.fr_size_hash))
				var record:=size_mm(int(a[2]),int(f.get(flag,0)))
				var msg:="这只长 %.1f 厘米，之前的纪录为 %.1f 厘米。"%[height/10.0,record/10.0]
				if height>record:
					f[flag]=int(mon.fr_size_hash)
					g._give_item(a[3],1,"ball")
					msg+="刷新了纪录！请收下%s。"%a[3]
				g._persist()
				say(g,msg,who))
		"fan":
			if not f.get("kanto_champion",false):say(g,"我最喜欢看馆主和联盟强者的比赛。什么时候你也能打进联盟呢？",who)
			else:
				if not f.has("fr_fans"):f.fr_fans=[1,2,3];g._persist()
				var fans: Array=f.fr_fans
				var support: bool=fans.any(func(number):return int(number)==int(a[2]))
				var message: String="上次的联盟挑战我看了！下次再为你加油！" if support else "我也有自己喜欢的高手。下一场比赛，也许你会改变我的想法。"
				say(g,message+" 现在俱乐部里有%d位你的支持者。"%fans.size(),who)
		"doll":say(g,"架子上摆着%s的玩偶。"%Data.species_of(int(a[2])).name,who)
		"stickers":stickers(g)
		"joyful":
			if not f.get("sevii_delivered_meteorite",false):say(g,"等老板一家团聚，办完委托，游戏角就会营业。",who)
			else:g._pick("两岛游戏角",["宝可梦跳绳","嘟嘟利摘树果"],func(i):joyful(g,"jump" if i==0 else "dodrio"))
		"link_battle":
			pick_party(g,"选择参加通信单打的伙伴",func(mon):return int(mon.get("hp",0))>0,func(slot):
				var room:=preload("res://scenes/frlg_link_battle.gd").new()
				room.name="LinkBattle"
				g.menu_layer.add_child(room)
				g.panel_open+=1
				g.held_dir=""
				g._set_hud_visible(false)
				room.launch(g.save_data.party[slot])
				room.departed.connect(func(won,played):
					if played:fan_result(g,won)
					if won:f.fr_link_wins=int(f.get("fr_link_wins",0))+1
					g.panel_open=maxi(0,g.panel_open-1)
					g._set_hud_visible(g.panel_open==0)
					g._persist()))
		"powder","powder_club":
			var powder=load("res://core/berry_powder.gd")
			if a[0]=="powder":powder.vendor(g)
			else:powder.club(g)
		"coins","prizes","free_coins","drink_girl":counter(g,a,flag)
		_:return false
	return true

static func lead_mon(g) -> Dictionary:
	for m in g.save_data.party:
		if m is Dictionary and not m.is_empty():return m
	return {}

const DRINKS := [["美味之水",200,16],["劲爽汽水",300,20],["柠檬汁",350,33]]
const MON_PRIZES := [[63,9,180],[35,8,500],[147,18,2800],[123,25,5500],[137,26,9999]]
const TM_PRIZES := [[13,4000],[23,3500],[24,4000],[30,4500],[35,4000]]
const ITEM_PRIZES := [["烟雾球","SMOKE_BALL",800],["奇迹种子","MIRACLE_SEED",1000],["木炭","CHARCOAL",1000],["神秘水滴","MYSTIC_WATER",1000],["黄色玻璃哨","YELLOW_FLUTE",1600]]

static func field(g) -> bool:
	if g.world.map_data.get("region","") not in ["kanto","sevii"]:return false
	var key="%s/%s"%[g.world.map_data.region,g.world.map_data.id]
	var pos: Vector2i=g.world.player_pos+g.world._dir_vec()
	var cell: Array=data().field.get(key,{}).get("%d,%d"%[pos.x,pos.y],[])
	if cell.is_empty():return preload("res://core/frlg_fame.gd").field(g,pos)
	match cell[0]:
		"memorial":
			if g._flags().get("fr_memorial",false):say(g,"墓碑边安静地放着一罐柠檬汁。",cell[1])
			elif g._bag_count(DRINKS[2][0])==0:say(g,"这里安息着大岩蛇。在墓碑前供奉它喜欢的柠檬汁吧。",cell[1])
			else:g._pick("要在墓碑前供奉柠檬汁吗？",["供奉","离开"],func(i):
				if i==0:
					g._consume_item(DRINKS[2][0])
					gift(g,"fr_memorial","招式学习器 42","tm","大岩蛇的训练家"))
		"jump_record","dodrio_record":
			var best: Dictionary=g._flags().get("fr_"+cell[0],{})
			say(g,"最高分 %d，最长连续成功 %d 次。"%[best.get("points",0),best.get("streak",0)],cell[1])
		"vending":
			g._pick("自动售货机",DRINKS.map(func(row):return "%s　¥%d"%[row[0],row[1]]),func(i):
				var row: Array=DRINKS[i]
				if g.save_data.money<row[1]:say(g,"钱不够。","售货机")
				else:
					g.save_data.money-=row[1]
					g._give_item(row[0],1,"heal")
					g._persist()
					say(g,"取出了%s。"%row[0],"售货机"))
		"slots":
			if g._bag_count("代币盒")==0:say(g,"先去玉虹餐厅领取代币盒。","游戏机")
			else:
				var ui:=preload("res://scenes/frlg_slots.gd").new()
				ui.name="Reels"
				g.menu_layer.add_child(ui)
				g.panel_open+=1
				g._set_hud_visible(false)
				g.held_dir=""
				ui.setup(data().reels,int(g.save_data.get("fr_coins",0)),g.rng)
				ui.paid.connect(func(delta):
					g.save_data.fr_coins=clampi(int(g.save_data.get("fr_coins",0))+delta,0,9999)
					g._persist())
				ui.closed.connect(func():
					g.panel_open=maxi(0,g.panel_open-1)
					g._set_hud_visible(g.panel_open==0))

		"record":say(g,"这里记着钓鱼兄弟见过的最大鲤鱼王。",cell[1])
	return true

static func counter(g,a: Array,flag: String) -> void:
	var who: String=a[1]
	if a[0]=="drink_girl":
		var options:=DRINKS.filter(func(row):return g._bag_count(row[0])>0 and not g._flags().get("fr_drink_"+str(row[2]),false))
		if options.is_empty():say(g,"口好渴！不知道屋顶的自动售货机都卖些什么。",who)
		else:g._pick("送她哪种饮料？",options.map(func(r):return r[0]),func(i):
			var row: Array=options[i]
			g._consume_item(row[0])
			gift(g,"fr_drink_"+str(row[2]),"招式学习器 %02d"%row[2],"tm",who))
		return
	if g._bag_count("代币盒")==0:
		say(g,"带上代币盒再来吧。玉虹餐厅里有位常客。",who)
		return
	var balance: int=g.save_data.get("fr_coins",0)
	match a[0]:
		"free_coins":
			if g._flags().get(flag,false):say(g,"祝你好运！",who)
			elif balance+int(a[2])>9999:say(g,"代币盒装不下我想送你的代币了，腾出位置再来吧。",who)
			else:
				g.save_data.fr_coins=balance+int(a[2])
				change(g,flag)
				say(g,"送给你%d枚代币。"%a[2],who)
		"coins":
			g._pick("代币盒　%d / 9999"%balance,["50枚　¥1000","500枚　¥10000"],func(i):
				var coins: int=50 if i==0 else 500
				if g.save_data.money<coins*20 or balance+coins>9999:say(g,"钱不够，或代币盒放不下。",who)
				else:
					g.save_data.money-=coins*20
					g.save_data.fr_coins=balance+coins
					g._persist()
					say(g,"已把%d枚代币放进盒子。"%coins,who))
		"prizes":
			var prices: Array
			var names: Array=[]
			match a[2]:
				"mons":
					prices=[[63,7,120],[35,12,750],[127,18,2500],[147,24,4600],[137,18,6500]] if g._flags().get("fr_leaf_tables",false) else MON_PRIZES
					for row in prices:names.append(Data.species_of(row[0]).name)
				"tms":
					prices=TM_PRIZES
					for row in prices:names.append("招式学习器 %02d"%row[0])
				_:
					prices=ITEM_PRIZES
					for row in prices:names.append(row[0])
			var labels: Array=[]
			for i in prices.size():labels.append("%s　%d枚"%[names[i],prices[i][-1]])
			g._pick("兑换奖品　%d枚"%balance,labels,func(i):
				var row: Array=prices[i]
				if balance<row[-1]:
					say(g,"代币不足。",who)
					return
				g.save_data.fr_coins=balance-int(row[-1])
				if a[2]=="mons":g._add_to_team(row[0],row[1])
				elif a[2]=="tms":g._give_item(names[i],1,"tm")
				elif row[1]=="YELLOW_FLUTE":g._give_item(names[i],1,"key")
				else:g._give_bag_item(names[i],"held",row[1])
				g._persist()
				say(g,"已兑换%s。"%names[i],who))

static func use_bag(g,nm: String) -> bool:
	if nm not in ["名人传言器","教学电视","城镇地图"] and g.world.map_data.get("region","") not in ["kanto","sevii"]:return false
	match nm:
		"教学电视":teachy_tv(g)
		"名人传言器":preload("res://core/frlg_fame.gd").open(g)
		"城镇地图":g._open_world_atlas(false)
		"代币盒":say(g,"盒中有%d枚玉虹游戏代币。"%int(g.save_data.get("fr_coins",0)),"代币盒")
		_:return false
	return true


# With fixed battle IVs this game keeps the original 16-bit measurement seed on
# each individual, including ones migrated from an older save.
const SIZE_BANDS := [[290,1,0],[300,1,10],[400,2,110],[500,4,310],[600,20,710],[700,50,2710],[800,100,7710],[900,150,17710],[1000,150,32710],[1100,100,47710],[1200,50,57710],[1300,20,62710],[1400,5,64710],[1500,2,65210],[1600,1,65410],[1700,1,65510]]
static func size_mm(sid: int, seed_value: int) -> int:
	for i in range(SIZE_BANDS.size()-1,-1,-1):
		var band: Array=SIZE_BANDS[i]
		if seed_value>=int(band[2]):
			return (9 if sid==129 else 15)*(int(band[0])+(seed_value-int(band[2]))/int(band[1]))/10
	return 0

static func joyful(g,mode: String) -> void:
	var jump: bool=mode=="jump"
	pick_party(g,"选择可以跳绳的伙伴" if jump else "选择嘟嘟利",func(mon):
		return data().jumpers.has(str(mon.species_id)) if jump else int(mon.species_id)==85,func(slot):
		var mon: Dictionary=g.save_data.party[slot]
		var ui:=preload("res://scenes/frlg_island_room.gd").new()
		ui.name="JoyfulGame"
		g.menu_layer.add_child(ui)
		g.panel_open+=1
		g._set_hud_visible(false)
		g.held_dir=""
		ui.launch(mode,int(mon.species_id),g.rng)
		ui.settled.connect(func(points,streak,key,n):
			if points>0 or streak>0:
				var flag:="fr_"+mode+"_record"
				var best: Dictionary=g._flags().get(flag,{})
				g._flags()[flag]={"points":maxi(points,int(best.get("points",0))),"streak":maxi(streak,int(best.get("streak",0)))}
			if n>0 and Data.berries.has(key):
				for i in n:g._give_bag_item(Data.berry_name(key),"berry","",key)
			g.panel_open=maxi(0,g.panel_open-1)
			g._set_hud_visible(g.panel_open==0)
			g._persist()))


const STICKERS := [["联盟名人堂","fr_hof_count",[1,40,100,200]],["孵蛋","fr_egg_count",[1,100,200,300]],["通信对战胜利","fr_link_wins",[1,20,50,100]]]
static func stickers(g) -> void:
	var labels: Array=[]
	for row in STICKERS:labels.append("%s　%d 次"%[row[0],g._flags().get(row[1],0)])
	labels.append("查看贴纸收藏")
	g._pick("向贴纸收藏家讲哪段经历？",labels,func(i):
		var grades:=["尚未获得","普通","铜色","银色","金色"]
		if i==STICKERS.size():
			var lines: Array=[]
			for row in STICKERS:lines.append("%s　%s"%[row[0],grades[int(g._flags().get("sticker_"+str(row[1]),0))]])
			g._dialog(lines,"训练家贴纸")
			return
		var row: Array=STICKERS[i]
		var total: int=g._flags().get(row[1],0)
		var tier:=0
		for threshold in row[2]:
			if total>=int(threshold):tier+=1
		var key:="sticker_"+str(row[1])
		if tier>int(g._flags().get(key,0)):
			g._flags()[key]=tier
			g._persist()
			say(g,"你的%s纪录达到了%d次，送你%s贴纸。"%[row[0],total,grades[tier]],"贴纸收藏家")
		else:say(g,"目前是%d次。下次有新纪录，再来找我吧。"%total,"贴纸收藏家"))


static func fan_result(g,won: bool) -> void:
	var f: Dictionary=g._flags()
	if not f.has("fr_fans"):return
	var fans: Array=f.fr_fans.map(func(n):return int(n))
	var order: Array=[2,4,6,1,8,7,5,3] if won else [6,7,4,8,5,2,1,3]
	if not won and fans.size()<=1:return
	var options: Array=order.filter(func(n):return not fans.has(n) if won else fans.has(n))
	if options.is_empty():return
	var change_id: int=options.back()
	for n in options:
		if g.rng.randi_range(0,1)==1:change_id=n;break
	if won:fans.append(change_id)
	else:fans.erase(change_id)
	f.fr_fans=fans

static func fan_clock(g,delta: float) -> void:
	if g.save_data.is_empty() or not g.save_data.get("flags",{}).has("fr_fans"):return
	var f: Dictionary=g._flags()
	if f.fr_fans.size()<5:f.fr_fan_seconds=0;return
	f.fr_fan_seconds=float(f.get("fr_fan_seconds",0))+delta
	if f.fr_fan_seconds>=43200:
		f.fr_fan_seconds=0
		fan_result(g,false)

static func lance_fans(g) -> void:
	var f: Dictionary=g._flags()
	if not f.has("fr_fans"):return
	f.fr_fan_counter=mini(20,int(f.get("fr_fan_counter",0))+2)
	if f.fr_fan_counter==20 and f.fr_fans.size()<3:
		fan_result(g,true)
		f.fr_fan_counter=0


static func teachy_tv(g) -> void:
	var titles:=["战斗入门","异常状态","属性相性","捕捉宝可梦"]
	if g.bag_items.any(func(row):return row.get("category")=="tm" and int(row.get("count",0))>0):
		titles.append_array(["招式学习器","登记常用道具"])
	g._pick("教学电视",titles,func(i):
		if i<4:
			var demo:=preload("res://scenes/frlg_teachy_demo.gd").new()
			demo.name="TeachyDemo"
			g.menu_layer.add_child(demo)
			g.panel_open+=1
			g._set_hud_visible(false)
			demo.finished.connect(func(_result):
				g.panel_open=maxi(0,g.panel_open-1)
				g._set_hud_visible(g.panel_open==0))
			demo.play_lesson(i,data().tv[i])
			return
		if i==4:g._dialog(["在背包选择学习器和队员。若招式槽已满，可选择要忘记的一招。"],titles[i]);return
		var options: Array=[]
		for row in g.bag_items:
			if row.get("category","")=="key" and row.name!="教学电视" and int(row.get("count",0))>0:options.append(row.name)
		if options.is_empty():say(g,"还没有可以登记的重要道具。","教学电视");return
		g._pick("选择一个道具，之后可从 START 的工具菜单直接使用",options,func(j):
			g._flags().fr_registered_item=options[j]
			g._persist()
			say(g,"已登记%s。"%options[j],"教学电视")))

static func show_diploma(g) -> void:
	var caught: Dictionary={}
	for sid in g.save_data.dex.get("caught",[]):caught[int(sid)]=true
	var national:=true
	for sid in range(1,385):
		if sid in [151,249,250,251] or caught.has(sid):continue
		if sid<=150:
			say(g,"我负责设计宝可梦。登记关都的 150 种伙伴后，再来让我看看你的图鉴！","游戏设计师")
			return
		national=false
	var place:="全国" if national else "关都"
	g._flags()["fr_diploma_national" if national else "fr_diploma_kanto"]=true
	g._persist()
	var outer:=ColorRect.new()
	outer.name="PokedexDiploma"
	outer.color=Color("#172525")
	g.menu_layer.add_child(outer)
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var certificate:=TextureRect.new()
	outer.add_child(certificate)
	certificate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	certificate.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	certificate.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	certificate.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	certificate.texture=load("res://assets/emerald/fr_diploma_%s.png"%("national" if national else "kanto"))
	var caption:=Label.new()
	caption.text="%s图鉴完成证书\n\n授予训练家　%s\n你的脚步记录了%s的宝可梦。\n\nGAME FREAK"%[place,g.save_data.get("player_name","小悠"),place]
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color",Color("#334b35"))
	certificate.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var close:=Button.new()
	close.text="收好证书"
	outer.add_child(close)
	close.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	close.offset_left=-93;close.offset_top=-40
	g.panel_open+=1
	g._set_hud_visible(false)
	var finish:=func():
		if outer.is_queued_for_deletion():return
		outer.queue_free()
		g.panel_open=maxi(0,g.panel_open-1)
		g._set_hud_visible(g.panel_open==0)
	close.pressed.connect(finish)
	outer.set_meta("choice_back",finish)
