extends RefCounted

const FR := preload("res://core/frlg_sidequests.gd")
static var catalog: Dictionary
static var clock: Callable

static func data() -> Dictionary:
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string("res://content/sinnoh_restaurant.json"))
	return catalog

static func now() -> Dictionary:
	return clock.call() if clock.is_valid() else Time.get_datetime_dict_from_system()

static func open_at(time: Dictionary) -> bool:
	return int(time.hour)>=9 and int(time.hour)<23

static func date_key(time: Dictionary) -> String:
	return "%04d-%02d-%02d"%[time.year,time.month,time.day]

static func dining(flags: Dictionary,time: Dictionary) -> Dictionary:
	var day:=date_key(time)
	var table: Dictionary=flags.get("s_restaurant",{})
	if table.get("day","")==day:return table
	var rng:=RandomNumberGenerator.new()
	rng.seed=hash([flags.get_or_add("s_restaurant_seed",randi()),day])
	var pool: Array=data().pairs.keys()
	var guests: Dictionary={}
	for i in 5:
		var pair: String=pool.pop_at(rng.randi_range(0,pool.size()-1))
		guests[pair]=rng.randi_range(0,2)
	table={"day":day,"guests":guests,"won":[]}
	flags.s_restaurant=table
	return table

static func visible(key: String,flags: Dictionary) -> int:
	if not key.begins_with("FLAG_HIDE_RESTAURANT_"):return -1
	var time:=now()
	if not open_at(time):return 0
	return int(dining(flags,time).guests.has(key))

static func closing(g,side) -> bool:
	var time:=now()
	if open_at(time):
		if g._flags().get("s_restaurant",{}).get("day","")!=date_key(time):
			dining(g._flags(),time)
			g.world.refresh_story_actors(g._flags())
			g._persist()
		return false
	side.go(g,"VALOR_LAKEFRONT",[706,791])
	FR.say(g,str(data().texts.WeAreNowClosed),"七星餐厅")
	return true

static func talk(g,side,npc: Dictionary) -> bool:
	var script:=str(npc.get("source_script",""))
	if not script.begins_with("Restaurant_"):return false
	if closing(g,side):return true
	if script=="Restaurant_Waiter":
		FR.say(g,str(data().texts.PartakeInBattles),"服务员")
		return true
	var group:=str(npc.get("source_flag",""))
	var table:=dining(g._flags(),now())
	if not table.guests.has(group):return true
	var pair: Dictionary=data().pairs[group]
	var names: String="、".join(pair.trainers)
	var token: String=group.get_slice("RESTAURANT_",1)
	var short_name: String=token.get_slice("_",0)
	if not script.to_upper().ends_with(short_name):short_name=token.get_slice("_",1)
	short_name=short_name.capitalize()
	var variant:=str(int(table.guests[group]))
	var lines: Dictionary=data().texts
	if table.won.has(group):
		FR.say(g,str(lines[short_name+"Defeated"+variant]),names)
		return true
	if g.save_data.party.filter(func(m):return m is Dictionary and int(m.get("hp",0))>0).size()<2:
		FR.say(g,str(lines[short_name+"NeedMultiplePokemon"]),names)
		return true
	g._dialog([lines[short_name+"Intro"+variant]],names).closed.connect(func():
		g._pick(str(lines[short_name+"AskBattle"+variant]),["接受双打","继续用餐"],func(i):
			if i!=0:return
			var team: Array=pair.team.duplicate(true)
			for unit in team:
				if unit.moves.is_empty():unit.moves=side.moves_for(int(unit.species),int(unit.level))
			var cfg:={"team":team,"double":true,"prize":int(pair.prize)}
			g._start_battle({"name":names,"battle":cfg,"lines":[]},func(result):
				if result=="a":
					if not table.won.has(group):table.won.append(group)
					g._persist()
					FR.say(g,str(lines[short_name+"Defeated"+variant]),names)
				elif result=="b" and g._party_fainted():g._blackout())))
	return true
