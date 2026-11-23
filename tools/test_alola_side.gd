extends SceneTree
var Side
var BattleTree
var failures:=0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool,why: String) -> void:
	if not ok:
		push_error(why)
		failures+=1

func run() -> void:
	Side=load("res://core/alola_side.gd")
	BattleTree=load("res://core/alola_side_tree.gd")
	var book: Dictionary=Side.rows()
	var counts:={}
	var area_count:={}
	for id in book:
		var row: Dictionary=book[id]
		var path: String="res://content/regions/alola/maps/%s.json"%row.map
		expect(FileAccess.file_exists(path),id+" missing area "+path)
		if row.action=="collect":
			counts[row.kind]=int(counts.get(row.kind,0))+1
			area_count[row.map]=true
		if row.action=="wild":expect(ResourceLoader.exists("res://assets/emerald/field/alola_mon_%d.png"%int(row.species)),id+" missing field sprite")
		for req in row.require:
			if str(req).begins_with("as_"):
				expect(book.has(str(req).trim_prefix("as_")) or str(req) in ["as_hypno_solved","as_grove_done","as_report2","as_report4","as_ub01","as_ub02s","as_ub02m","as_ub03","as_ub04s","as_ub04m","as_ub05"],str(req))
	expect(counts=={"cell":95,"sticker":100,"core":5},"collectible totals")
	for version in ["sun","moon","ultra_sun","ultra_moon"]:
		var flags:={"a_started":true,"a_version":version,"a_credits":true}
		expect(Side.eligible(book.card,flags)==not str(version).begins_with("ultra"),"card version")
		expect(Side.eligible(book.ultra_balls,flags)==str(version).begins_with("ultra"),"grove version")
		expect(not Side.eligible(book.rr_giovanni,flags),"Giovanni locked")
		var field=load("res://core/alola_field.gd")
		for loc in field.data().wild[version]:
			for method in field.data().wild[version][loc]:
				for mon in field.habitat({"alola_location":loc},flags,method):
					expect(int(mon.species) not in range(785,807),"mission encounter leaked into regular habitat")
		for row in book.values():
			if row.get("action","")!="battle" or not (row.versions in ["all",version,"usum" if str(version).begins_with("ultra") else "sm"]):continue
			var team=row.get("team",0)
			if team is Dictionary:team=team.get(version,0)
			if int(team)>0:expect(not load("res://core/alola_campaign.gd").trainer(team,flags).is_empty(),"empty trainer "+str(row.id))
	for group in ["sm","usum","royal"]:
		for coach in BattleTree.data()[group]:
			for ref in coach[1]:expect(int(ref)>=0 and int(ref)<BattleTree.data().sets.size(),"invalid tree set")
	expect(BattleTree.data().usum[209][1].size()==3,"festival rental battle")
	print("ALOLA SIDE TABLES PASS ",book.size()," events; ",counts,"; area count ",area_count.size(),"; Battle Tree sets ",BattleTree.data().sets.size())
	quit(1 if failures>0 else 0)
