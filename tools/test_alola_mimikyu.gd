extends SceneTree
var errors:=0
func _initialize() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value:errors+=1;push_error(message)

func run() -> void:
	var db=root.get_node("Data")
	db.load_core_tables()
	var dex=load("res://core/dex_variants.gd")
	var art=load("res://core/dex_art.gd")
	var engine=load("res://core/battle.gd")
	var party=load("res://core/party.gd")
	var screen=load("res://scenes/dex_ui.gd")
	var initial:="MIMIKYU_TOTEM_DISGUISED"
	var busted:="MIMIKYU_TOTEM_BUSTED"
	var mon: Dictionary=party.make(778,40,[421,583],initial)
	mon.alola_totem_size=true
	var save:={"dex":{"caught":[],"seen":[]}}
	dex.record(save,mon,true)
	var ui=screen.new()
	root.add_child(ui)
	ui.setup(save.dex.seen,save.dex.caught,save.dex_variants)
	ui._show_detail(778)
	check(ui.options.size()==1 and ui.current.form==initial,"Totem gift disclosed a normal or broken disguise")
	check(ui.current.label=="霸主·化形","incorrect displayed form label")
	ui._pick_stats()
	check(ui.chooser.find_children("*","Label",true,false).any(func(n):return "0.4 米" in n.text and "2.8 千克" in n.text),"Totem height and weight hidden")
	ui.handle_back()
	for back in [false,true]:
		for shiny in [false,true]:
			for shape in [initial,busted]:
				var enlarged: Image=art.texture(778,shape,shiny,back).get_image()
				var ordinary: Image=art.texture(778,"" if shape==initial else "MIMIKYU_BUSTED",shiny,back).get_image()
				check(enlarged.get_used_rect().size.y>ordinary.get_used_rect().size.y,"Totem art size equals ordinary picture")
	var fighter=engine.new(191)
	fighter.start([engine.make_combatant(9,75,[57])],[mon])
	fighter._take_action("a","move:0")
	check(fighter.cur_b().form==busted,"Disguise did not change to broken Totem form")
	dex.record(save,fighter.cur_b(),false)
	ui.free()
	ui=screen.new()
	root.add_child(ui)
	ui.setup(save.dex.seen,save.dex.caught,save.dex_variants)
	ui._show_detail(778)
	check(ui.options.size()==2 and ui.options.all(func(v):return "TOTEM" in v.form),"seeing broken Totem exposed a normal Mimikyu")
	var old: Dictionary=party.make(778,40,[421])
	old.alola_totem_size=true
	var old_save:={"party":[old]}
	dex.restore(old_save)
	check(old.form==initial and int(old_save.dex_variants.get("778|"+initial+"|none|",0))==2,"owned legacy Totem was lost")
	print("ALOLA TOTEM MIMIKYU ", "FAIL" if errors else "PASS", " gift, battle hit, notebook discovery, front/back shiny art, dimensions, saved individual")
	quit(1 if errors else 0)
