extends RefCounted
## The three Hypno, shopping-mall performance, and Ilima's new trial each have their own state.
const Party:=preload("res://core/party.gd")
const MOVES:=[[95,171,139,29],[417,60,50,139],[93,50,1,96]]
const CLUES:=["摆锤晃了一下，守门的怪力已经开始打瞌睡。","它盯着楼梯的拐角，像是在安排下一步。","一枚柜台上的硬币摇晃着，慢慢悬了起来。"]

static func side():
	return load("res://core/alola_side.gd")

static func play(g,row: Dictionary) -> void:
	match str(row.action):
		"hypno":
			var i:=int(row.suspect)
			var db=g.get_node("/root/Data")
			var moves: Array=MOVES[i].map(func(mid):return db.move_of(mid).name)
			g._pick(CLUES[i]+"\n会使用"+"、".join(moves),["调查这只","再观察一下"],func(choice):
				if choice==0:
					event_wild(g,97,29,MOVES[i],func():
						g._flags().as_hypno_solved=true
						g._flags().as_hypno_choice=i
						side().refresh(g)
						g._dialog(["伊利马停下笔，将三份笔录摊在一起。去听听他的结论吧。"])))
		"bear_actor":g._dialog([row.text],row.name)
		"bear_show":
			g._pick("要留下观看穿着熊的表演吗？",["观看","稍后再来"],func(i):
				if i!=0:return
				side().complete(g,row)
				g._dialog(["两位演员穿上布偶服演示拥抱的力道。舞台旁却又伸出一双粉色的手。","台上怎么有三只？小朋友们，先到我身后来！"],"表演主持人"))
		"bewear":
			g._pick("真正的穿着熊走下了舞台。",["上前迎战","暂时退开"],func(i):
				if i==0:event_wild(g,760,28,[608,656,175,371],func():side().complete(g,row)))
		"ilima_invite":
			g._pick("我想记录你的对战方式。可以来训练家学校陪我打一场吗？",["接受挑战","改天再来"],func(i):
				if i==0:
					side().complete(g,row)
					var school: Dictionary=g.get_node("/root/Data").load_map("alola","alola_school")
					g._do_warp({"region":"alola","map":school.id,"at":school.spawn,"alola_native":true}))
		"ilima_test":
			var match_data: Dictionary=load("res://core/alola_campaign.gd").team({"alola_team":396},g._flags())
			g._dialog(["这里有足够的空间。让我见识一下你的伙伴吧！"],"伊利马").closed.connect(func():
				g._start_battle({"name":"伊利马","battle":match_data},func(outcome):
					if outcome=="a":
						g._give_bag_item("不变之石","held","EVERSTONE")
						side().complete(g,row)
						g._dialog(["谢谢你！请收下这块不变之石。让宝可梦携带它便能保持现有的样子。"],"伊利马")
					elif outcome=="b" and g._party_fainted():g._blackout()))
		"ilima_pedestal":
			if g._bag_count("伊利马的一般Ｚ")==0:return
			g._pick("把托付的纯晶放回台座？",["放回一般Ｚ","稍后再来"],func(i):
				if i!=0:return
				var sun: bool=g._flags().a_version=="ultra_sun"
				var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_campaign_totems.json"))
				var cfg: Dictionary=source.ultrasunultramoon["735_rematch" if sun else "20_rematch"]
				var name: String="霸主猫鼬探长" if sun else "霸主阿罗拉拉达"
				g._dialog(["纯晶就要落到台座上，背后再次传来霸主的吼声。"]).closed.connect(func():
					g._start_battle({"name":name,"battle":cfg},func(outcome):
						if outcome=="a":
							g._consume_item("伊利马的一般Ｚ")
							g._flags().a_trial_guide_outfit=true
							side().complete(g,row)
							g._dialog(["纯晶稳稳地嵌入台座。下一个来挑战的孩子可以找到它了。","你让霸主认可了继承考验的人。这顶帽子和这件短袖送给你，可以换上考验向导装。"],"伊利马")
						elif outcome=="b" and g._party_fainted():g._blackout())))

static func event_wild(g,species: int,level: int,moves: Array,win: Callable) -> void:
	if not g._has_party():g._dialog(["先让队伍中的伙伴恢复体力。"]);return
	var mon:=Party.make(species,level,moves)
	mon.held="";mon.berry=""
	mon.alola_stationary=true
	g._start_wild_battle(species,level,"",func(outcome):
		if outcome in ["a","caught"]:win.call()
		elif outcome=="b" and g._party_fainted():g._blackout(),"",0,mon)
