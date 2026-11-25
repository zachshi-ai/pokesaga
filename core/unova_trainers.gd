extends RefCounted
## Zone-local entities use original trainer scripts; both Unova journeys may reuse the same trainer number.
const Field := preload("res://core/unova_field.gd")
const DIRECTIONS := {"up":Vector2i.UP,"down":Vector2i.DOWN,"left":Vector2i.LEFT,"right":Vector2i.RIGHT}
static var book: Dictionary
static var shops: Dictionary

static func data() -> Dictionary:
	if book.is_empty(): book=JSON.parse_string(FileAccess.get_file_as_string("res://content/unova_trainers.json"))
	return book

static func shop_data(era: String) -> Dictionary:
	if shops.is_empty():shops=JSON.parse_string(FileAccess.get_file_as_string("res://content/unova_shops.json"))
	return shops[era]

static func goods(game, shop_id: int) -> Array:
	var flags: Dictionary=game._flags()
	var stock:=shop_data(Field.era(flags))
	var prefix:=Field.flag_prefix(flags)
	var badges:=0
	for n in range(1,9):
		if flags.get(prefix+"badge_"+str(n),false):badges+=1
	var keys: Array=stock.badge_marts[int(stock.badge_tiers[badges])] if shop_id==255 else stock.marts[shop_id]
	var side=load("res://core/unova_side.gd")
	var items: Dictionary=side.data().items
	var result: Array=[]
	for item in keys:
		var row: Array=items.get(item,[])
		if row.is_empty():continue
		var label:=str(row[0])
		if str(item).begins_with("TM"):label=Field.machine_name(game,int(str(item).substr(2)),false)
		result.append({"name":label,"category":row[1],"price":int(row[2])*10,"unova_item":item})
	return result

static func visible(flag: Variant, flags: Dictionary, era: String) -> bool:
	var code:=str(flag).trim_suffix(".0").trim_prefix("EVENT_FLAG_")
	var number:=code.hex_to_int() if code.begins_with("0x") else int(code)
	if number==0:return true
	if era=="bw":
		match number:
			590:return flags.get("u1_dragonspiral",false) and not flags.get("u1_castle_stone",false)
			738:return flags.get("u1_web",false) and not flags.get("u1_cave_n",false)
			609:return flags.get("u1_tower_alarm",false) and not flags.get("u1_dragonspiral",false)
			764,830,832:return true # Black versions of the battle house and Route 7.
	else:
		if number==0x03d0:return flags.get("u2_board_ship",false) and not flags.get("u2_ghetsis",false)
		if number==0x038e:return Field.season(int(Time.get_date_dict_from_system().month))==2
		if number in [0x040f,0x036a]:return true
	return false

# These serialized actors stand on the only approach to a scripted transition.
# The DS script turns or steps aside after validating the visitor's progress.
const DOOR_STAFF := {
	"unova_9":[9,"u1_ghetsis",[25,26],"黑带","先走完联盟之旅，再来修行岩屋吧。","现在你可以进岩屋修行了。"],
	"unova_bw_zone_39":[0,"u1_ghetsis",[18,15],"水手","皇家合众号还没有开放登船。","登船口就在这里。"],
	"unova_b2_zone_39":[0,"u2_champion",[18,15],"水手","皇家合众号还没有开放登船。","登船口就在这里。"],
	"unova_b2_zone_568":[4,"us_dressing_room",[2,5],"护卫","这是专属更衣室。请先让每部电影都以好结局上映。","老板已经交代过了。请进入更衣室。"],
}

static func door_staff(map: Dictionary,flags: Dictionary,rows: Array) -> Array:
	var job: Array=DOOR_STAFF.get(map.id,[])
	if job.is_empty():return rows
	for i in rows.size():
		if int(rows[i].get("unova_local_id",-1))!=int(job[0]):continue
		var open: bool=flags.get(job[1],false)
		var actor: Dictionary=rows[i].duplicate()
		actor.name=job[3]
		actor.lines=[job[5] if open else job[4]]
		if open:actor.at=job[2]
		rows[i]=actor
		break
	return rows

static func roster(map: Dictionary, flags: Dictionary, original: Array) -> Array:
	var era:=Field.era(flags)
	var records: Dictionary=data()[era]
	var clerks: Dictionary=shop_data(era).actors.get(str(map.id),{})
	var slots: Dictionary=records.locations.get(str(int(map.get("unova_zone_id",-1))),{})
	var rows:=original.duplicate()
	var occupied: Dictionary={}
	for row in rows:occupied[str(row.at)]=row
	var source: Array=map.get("unova_cast",[])
	var center:=source.any(func(row):return int(row.get("script",0))==2100)
	for native in source:
		if native.get("at",[]).size()!=2:continue
		var local:=int(native.get("local_id",native.get("id",-1)))
		var script:=int(native.get("script",0))
		var entry: Array=slots.get(str(local),[])
		var row: Dictionary={"at":native.at,"local_id":"unova_field_%d"%local,"unova_local_id":local,"facing":"down"}
		if center and script==2100:
			row.merge({"name":"护士","gfx":"nurse","heal":true})
		elif clerks.has(str(local)):
			row.unova_shop=int(clerks[str(local)])
			row.merge({"name":"店员","gfx":"clerk","shop":true,"facing":"left"},true)
		elif not entry.is_empty() and (visible(native.get("flag",0),flags,era) or (era=="b2" and int(entry[0]) in [171,172,178,179,207,208,209])):
			var tid:=int(entry[0])
			var person: Dictionary=records.trainers[str(tid)]
			var flag:=Field.flag_prefix(flags)+"trainer_%d"%tid
			row.merge({"name":person.name,"gfx":person.gfx,"facing":entry[2],"unova_trainer":flag,
				"sight":int(entry[1]),"defeated":flags.get(flag,false),"unova_class":person["class"],
				"battle":{"team":person.team,"prize":person.prize,"battle_type":person.battle_type,"double":person.battle_type=="double"},
				"lines":["让我们来一场宝可梦对战吧！"],"post":["谢谢你的指教。"]},true)
		else:continue
		var resident: Dictionary=occupied.get(str(native.at),{})
		if not resident.is_empty() and int(resident.get("unova_local_id",-1))==local:
			rows.erase(resident)
			occupied.erase(str(native.at))
		if map.id=="unova_bw_gym_nacrene" and row.get("defeated",false):
			if row.get("unova_trainer","")=="u1_trainer_88":row.at=[5,4]
			elif row.get("unova_trainer","")=="u1_trainer_87":row.at=[12,12]
		# Cheyenne's original X/Z is the middle of our flat projection's
		# one-way drop. Preserve her sightline from the ledge's upper bank.
		if era=="bw" and map.id=="unova_10" and local==5:row.at=[75,21]
		var previous: Dictionary=occupied.get(str(row.at),{})
		if not previous.is_empty():
			if int(previous.get("unova_local_id",-1))!=local:continue
			rows.erase(previous)
		rows.append(row)
		occupied[str(row.at)]=row
	return door_staff(map,flags,rows)

static func talk(g, row: Dictionary) -> bool:
	if not row.has("unova_trainer"):return false
	if g.world.map_data.id=="unova_bw_gym_nacrene" and not g._flags().get(row.unova_trainer,false):
		var required:=int({"u1_trainer_88":2,"u1_trainer_87":4}.get(row.unova_trainer,0))
		if int(g._flags().get("u1_library_books",0))<required:
			g._dialog(["这本书我还在看。你正在找馆长留下的下一条谜题吗？"],row.name)
			return true
	if not g._flags().get(Field.flag_prefix(g._flags())+"starter",0):
		g._dialog(["先去领取你的初始宝可梦吧。"],row.name)
		return true
	if g._flags().get(row.unova_trainer,false):
		if row.unova_class in ["Doctor","Nurse"]:
			g._heal_party()
			g._dialog(["你的伙伴都恢复精神了。路上小心！"],row.name)
		else:g._dialog(row.post,row.name)
		return true
	var needed:=2 if row.battle.double else 1
	if row.battle.battle_type in ["rotation","triple"]:needed=3
	if g.save_data.party.filter(func(m):return m is Dictionary and int(m.get("hp",0))>0).size()<needed:
		g._dialog(["这种对战需要至少 %d 只能出战的伙伴。"%needed],row.name)
		return true
	return false

static func challenge(g) -> bool:
	if g.panel_open or not g.cur_story.is_empty() or not g._flags().get(Field.flag_prefix(g._flags())+"starter",0):return false
	for row in g.world.npcs:
		if not row.has("unova_trainer") or row.get("defeated",false):continue
		var delta: Vector2i=DIRECTIONS.get(row.facing,Vector2i.DOWN)
		var pos:=Vector2i(int(row.at[0]),int(row.at[1]))
		# Twins with a lone challenger only explain their format if directly approached.
		if row.battle.double and g.save_data.party.filter(func(m):return int(m.get("hp",0))>0).size()<2:continue
		for i in int(row.sight):
			pos+=delta
			if pos==g.world.player_pos:
				g.held_dir=""
				g.run_held=false
				g._talk_to_npc(row)
				return true
			if g.world.is_blocked(pos) or not g.world._npc_at(pos).is_empty():break
	return false
