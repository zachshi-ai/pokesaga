extends RefCounted

const TRICK := "em_route110_trick_house_"
const REWARDS := [
	["神奇糖果","medicine",""],["计时球","ball",""],["硬石头","held","HARD_STONE"],
	["烟雾球","held","SMOKE_BALL"],["招式学习器 12","tm",""],["磁铁","held","MAGNET"],
	["PP极限提升剂","medicine",""]]
const QUIZZES := [
	[["110号道路找不到哪种宝可梦？",["走路草","土狼犬","傲骨燕"],2],["哪个不是水属性？",["露力丽","莲叶童子","长翅鸥"],0],["哪只不会使出吸血？",["毒粉蛾","超音蝠","土居忍士"],0]],
	[["满充借用千里的哪只宝可梦？",["拉鲁拉丝","蛇纹熊","懒人獭"],1],["谁在追赶小田卷博士？",["土狼犬","蘑蘑菇","蛇纹熊"],2],["海洋队在橙华森林派出了谁？",["土狼犬","超音蝠","利牙鱼"],0]],
	[["三封港口邮件与一瓶灼伤药，哪样贵？",["灼伤药","港口邮件","一样贵"],0],["卖一个超级球再买一瓶伤药，还剩多少？",["60元","55元","0元"],2],["除虫喷雾和劲爽汽水的总价比好伤药贵吗？",["更贵","更便宜","一样贵"],1]],
	[["海之家里，男客人和女客人谁更多？",["男客人","女客人","一样多"],0],["釜炎镇里的老爷爷和老奶奶，谁更多？",["老爷爷","老奶奶","一样多"],0],["训练家学校里有几名女学生？",["0名","1名","2名"],1]],
	[["凯那市宝可梦同好会里有几只宝可梦？",["2只","3只","4只"],1],["茵郁市的树屋有几间？",["6间","7间","8间"],0],["自行车道上有几位铁人三项选手？",["6位","7位","8位"],2]]]

static func quiz(g, number: int) -> void:
	if g.world.hoenn_local.get("quiz%d"%number,false):return
	var row: Array=QUIZZES[number-1][g.rng.randi_range(0,QUIZZES[number-1].size()-1)]
	g._pick("机关人偶%d · "%number+str(row[0]),row[1],func(answer):
		if answer==int(row[2]):
			g.world.hoenn_local["quiz%d"%number]=true
			g._persist()
			g._dialog(["答对了。请前进！"])
		else:
			g._dialog(["回答错误。请从这一关的入口重新挑战。"]).closed.connect(func():
				g.world.hoenn_local.clear()
				g._do_warp({"region":"hoenn","map":TRICK+"puzzle5","at":[0,21],"hoenn_native":true}),CONNECT_ONE_SHOT))

static func stage(f: Dictionary) -> int:
	return int(f.get("h_trick_cleared",0))+1

static func ready(f: Dictionary, n: int) -> bool:
	if n==1:return true
	if n==8:return f.get("h_champion",false)
	return n<8 and f.get("h_badge_%d"%(n+1),false)

static func reward_trick(g) -> void:
	var f: Dictionary=g._flags()
	var n:=stage(f)
	if n>8 or int(f.get("h_trick_finished",0))!=n:
		g._dialog(["沿着走廊就能回到入口。"],"机关大王")
		return
	if n==8:
		g._pick("八关全破！挑一顶帐篷留作纪念。",["红色帐篷","蓝色帐篷"],func(i):
			if stage(f)!=8:return
			var prize:=str(["红色帐篷","蓝色帐篷"][i])
			g._give_bag_item(prize,"decoration")
			finalize_trick(g,n,prize))
	else:
		var r: Array=REWARDS[n-1]
		g._give_bag_item(r[0],r[1],r[2])
		finalize_trick(g,n,r[0])

static func finalize_trick(g, n: int, prize: String) -> void:
	g._flags().h_trick_cleared=n
	g._persist()
	g._dialog(["第%d关破解成功！收下%s吧。"%[n,prize]],"机关大王")

static func passage(g, mid: String) -> String:
	var f: Dictionary=g._flags()
	var here: String=g.world.map_data.id
	var n:=stage(f)
	if here==TRICK+"entrance" and mid.begins_with(TRICK+"puzzle"):
		if n>8:return "机关大王已踏上旅途。八道机关都被你破解了。"
		if not ready(f,n):return "下一关仍在准备中。继续挑战丰缘道馆和联盟吧。"
		if int(f.get("h_trick_found",0))!=n:return "屋里有人看着你。先找到藏起来的机关大王。"
	if here.begins_with(TRICK+"puzzle") and mid==TRICK+"end":
		var puzzle:=here.right(1).to_int()
		if puzzle!=n or int(f.get("h_trick_scroll",0))!=n:return "密码门上留着空白。先去找本关的卷轴。"
		if n==5:
			for i in range(1,6):
				if not g.world.hoenn_local.get("quiz%d"%i,false):return "请先通过五个机关人偶的考验。"
		f.h_trick_finished=n
	return ""

static func step(g) -> bool:
	var m: Dictionary=g.world.map_data
	var p: Vector2i=g.world.player_pos
	var doll:=int(m.get("mechanisms",{}).get("quiz_triggers",{}).get("%d,%d"%[p.x,p.y],0))
	if doll>0 and not g.world.hoenn_local.get("quiz%d"%doll,false) and not g.panel_open:
		quiz(g,doll)
		return true
	return false

static func object_action(g, o: Dictionary) -> bool:
	var script:=str(o.get("source_script",""))
	var f: Dictionary=g._flags()
	var n:=stage(f)
	if script.begins_with("TrickHidingSpot"):
		if script.trim_prefix("TrickHidingSpot").to_int()==n and ready(f,n) and int(f.get("h_trick_found",0))!=n:
			f.h_trick_found=n
			g._persist()
			g._dialog(["被你发现了！去调查北边的挂轴，进去挑战我的第%d关。"%n],"机关大王")
		else:g._dialog(["这里没有动静。"])
		return true
	if script=="Route110_TrickHouseEntrance_EventScript_Door":
		var message:=passage(g,TRICK+"puzzle1")
		if not message.is_empty():g._dialog([message])
		else:g._do_warp({"region":"hoenn","map":TRICK+"puzzle%d"%n,"at":[0,21],"hoenn_native":true})
		return true
	if script.begins_with("Route110_TrickHousePuzzle") and script.ends_with("_Scroll"):
		f.h_trick_scroll=g.world.map_data.id.right(1).to_int()
		g._persist()
		g._dialog(["记下了卷轴上的暗号。可以去开北侧的密码门了。"])
		return true
	if script.contains("_EventScript_ShoalSalt") or script.contains("_EventScript_ShoalShell"):
		var salt:=script.contains("ShoalSalt")
		var high: bool=g.world.map_data.id.contains("high_tide")
		var item: String="浅滩海盐" if salt else "浅滩贝壳"
		var today:=Time.get_date_string_from_system()
		var key:="h_shoal_"+script.get_slice("_EventScript_",1)
		if salt==high:g._dialog(["这里现在采不到"+item+"。"])
		elif f.get(key,"")==today:g._dialog(["今天已经在这里采集过了。"])
		else:
			g._give_bag_item(item,"other")
			f[key]=today
			g._persist()
			g._dialog(["采到了"+item+"！"])
		return true
	return false

static func actor_visibility(script: String, f: Dictionary) -> int:
	if script=="Route110_TrickHouseEntrance_EventScript_TrickMaster":return 0
	if script.begins_with("Route111_WinstrateFamilysHouse_EventScript_"):return int(f.get("h_winstrates",false))
	return -1

static func talk(g, npc: Dictionary) -> bool:
	var script:=str(npc.get("source_script",""))
	if script=="Route109_SeashoreHouse_EventScript_Owner":
		var f: Dictionary=g._flags()
		if not ["DWAYNE","SIMON","JOHANNA"].all(func(t):return f.get("h_trainer_TRAINER_"+t,false)):
			g._dialog(["打赢屋里的三个训练家，让我看看你的本事！"],"海滨之家店主")
		elif not f.get("h_seashore_soda",false):
			g._give_item("劲爽汽水",6,"heal")
			f.h_seashore_soda=true
			g._persist()
			g._dialog(["三场都赢了！这六瓶劲爽汽水归你。"],"海滨之家店主")
		else:g._pick("劲爽汽水一瓶300元，来一瓶吗？",["购买","离开"],func(i):
			if i!=0:return
			if g.save_data.money<300:g._dialog(["钱不够买一瓶。"]);return
			g.save_data.money-=300
			g._give_item("劲爽汽水",1,"heal")
			g._persist()
			g._dialog(["给，你的劲爽汽水。"]))
		return true
	if script=="SlateportCity_EventScript_EffortRibbonWoman":
		if g.save_data.party.is_empty():g._dialog(["带伙伴来找我吧。"]);return true
		var mon: Dictionary=g.save_data.party[0]
		var total:=0
		for amount in mon.get("effort",{}).values():total+=int(amount)
		if mon.get("effort_ribbon",false):g._dialog(["努力奖章很适合它！"])
		elif total<510:g._dialog(["再和它一起加油吧，它一定还能成长。"])
		else:
			mon.effort_ribbon=true
			g._persist()
			g._dialog(["你的%s付出了所有努力！请收下这枚努力奖章。"%mon.name])
		return true
	if script=="PacifidlogTown_House2_EventScript_FanClubYoungerBrother":
		if g.save_data.party.is_empty():g._dialog(["让我看看你的伙伴。"]);return true
		var today:=floori(float(Time.get_unix_time_from_datetime_dict(Time.get_date_dict_from_system()))/86400.0)
		var remaining:=int(g._flags().get("h_fan_tm_day",today-7))+7-today
		var friends:=int(g.save_data.party[0].get("friendship",200))
		if remaining>0:g._dialog(["还要等%d天，再来找我吧。"%remaining])
		elif friends>=50 and friends<150:g._dialog(["它跟你渐渐亲近了。继续好好照顾它。"])
		else:
			var number:=27 if friends>=150 else 21
			g._give_item("招式学习器 %02d"%number,1,"tm")
			g._flags().h_fan_tm_day=today
			g._persist()
			g._dialog(["这只伙伴的心意就藏在这招里。收下%s的招式学习器吧。"%("报恩" if number==27 else "迁怒")])
		return true
	if script.begins_with("Route110_TrickHousePuzzle5_EventScript_Mechadoll"):
		quiz(g,script.right(1).to_int())
		return true
	if script=="Route111_WinstrateFamilysHouse_EventScript_Victoria":
		if not g._flags().get("h_macho_brace",false):
			g._give_bag_item("强制锻炼器","held","MACHO_BRACE")
			g._flags().h_macho_brace=true
			g._persist()
			g._dialog(["我们全家训练时都用这个强制锻炼器。让伙伴带上它吧！"],"连胜妈妈")
		else:g._dialog(["我们一家人的训练，你都见识过了。"],"连胜妈妈")
		return true
	if script.ends_with("_ShellBellExpert"):
		if g._bag_count("浅滩海盐")<4 or g._bag_count("浅滩贝壳")<4:
			g._dialog(["退潮采海盐，涨潮采贝壳。各带四个给我，就能做出贝壳之铃。"])
		else:g._pick("用四份海盐和四个贝壳制作贝壳之铃？",["制作","留着"],func(i):
			if i!=0 or g._bag_count("浅滩海盐")<4 or g._bag_count("浅滩贝壳")<4:return
			for j in 4:
				g._consume_item("浅滩海盐")
				g._consume_item("浅滩贝壳")
			g._give_bag_item("贝壳之铃","held","SHELL_BELL")
			g._persist()
			g._dialog(["做好了！让伙伴携带，攻击对手时能恢复体力。"]))
		return true
	return false
