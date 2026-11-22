extends RefCounted

const Field := preload("res://core/unova_field.gd")
const Party := preload("res://core/party.gd")
const WEIGHTS := [1,4,15,1,4,10,25,1,4,10,25]

static func content() -> Dictionary:
	return load("res://core/unova_side.gd").data()

static func table(g) -> Dictionary:
	return g.save_data.get_or_add("unova_grottos",{})

static func generate(g,index: int,initial:=false) -> void:
	var row: Array=content().grottos[index]
	var group:=randi_range(0,3)
	var slot:=0
	var roll:=randi_range(1,100)
	for weight in WEIGHTS:
		roll-=weight
		if roll<=0:break
		slot+=1
	if initial:
		slot=0
		group=0
	var result: Dictionary
	if slot<3:
		var v: Array=row[3][slot][group]
		var id:=int(v[0])
		var lv:=randi_range(int(v[1]),int(v[2]))
		var mon:=Party.make(id,lv,Field.moves_for(id,lv,g._flags()))
		var ability:=int(content().hidden_abilities.get(str(id),0))
		if ability>0:
			mon.ability=ability
			mon.ability_name=g.get_node("/root/Data").abilities.get(ability,{}).get("name","")
		mon.unova_stationary=true
		mon.sex="female" if randi_range(0,99)<int(v[3]) else "male"
		Party.set_shiny_kind(mon,"none")
		result={"mon":mon}
	else:
		result={"item":row[4 if slot<7 else 5][slot-3 if slot<7 else slot-7][group],"hidden":slot>=7}
	table(g)[str(index)]=result

static func enter(g,index: int) -> void:
	if Field.era(g._flags())!="b2":return
	if not g._flags().get("u2_badge_4",false):
		g._dialog(["树枝之间似乎有一条小路。"]);return
	if not g._flags().get("us_grotto_unlocked",false):
		if index!=1:g._dialog(["紧密的树枝封住了入口。"]);return
		g._flags().us_grotto_unlocked=true
		generate(g,1,true)
		g._persist()
	var slot: Dictionary=table(g).get(str(index),{})
	g._flags().us_grotto_display=int(slot.mon.species_id) if slot.has("mon") else -1 if slot.has("item") and not slot.get("hidden",false) else 0
	g.save_data.unova_grotto_visit={"index":index,"map":g.world.map_data.id,"at":[g.world.player_pos.x,g.world.player_pos.y]}
	g._persist()
	g._do_warp({"region":"unova","map":"unova_b2_zone_518","at":[15,23]})

static func leave(g) -> void:
	var visit: Dictionary=g.save_data.get("unova_grotto_visit",{})
	var target: Dictionary={"region":"unova","map":visit.get("map","unova_5"),"at":visit.get("at",[4,6])}
	g._do_warp(target)

static func open(g,index: int) -> void:
	if index<0 or index>=content().grottos.size():return
	var place: Dictionary=table(g).get(str(index),{})
	if place.is_empty():
		g._dialog(["你拨开树枝搜了一圈。今天的树洞静悄悄的。"],"隐藏洞穴");return
	if place.has("mon"):
		var mon: Dictionary=place.mon
		g._pick("树洞深处栖息着%s。"%mon.name,["靠近","先离开"],func(i):
			if i!=0 or not g._has_party():return
			g._start_wild_battle(int(mon.species_id),int(mon.level),"",func(outcome):
				if outcome!="b":
					table(g).erase(str(index))
					g._flags().us_grotto_display=0
					g.world.refresh_story_actors(g._flags())
					g._persist()
				elif g._party_fainted():g._blackout(),"none",0,mon))
	else:
		var service=load("res://core/unova_side.gd")
		var key:=str(place.item)
		service.give(g,key)
		table(g).erase(str(index))
		g._flags().us_grotto_display=0
		g.world.refresh_story_actors(g._flags())
		g._persist()
		g._dialog(["%s%s。"%["在草丛深处摸到了" if place.hidden else "在树洞里捡到了",service.item_name(key)]],"隐藏洞穴")

static func step(g) -> bool:
	if g.world.map_data.get("unova_zone","")=="hidden_grotto" and g.world.player_pos==Vector2i(15,26):
		leave(g)
		return true
	if g._flags().get("us_grotto_unlocked",false) and Field.era(g._flags())=="b2":
		var count:=int(g.save_data.get("unova_grotto_steps",0))+1
		g.save_data.unova_grotto_steps=count%256
		if count>=256:
			var occupied:=table(g)
			for i in content().grottos.size():
				if not occupied.has(str(i)) and randi_range(0,99)<5:generate(g,i)
			g._persist()
	return load("res://core/unova_side_quests.gd").step(g)
