extends SceneTree
## Exact combinations are discovered separately, even under a shared notebook number.


var failed := false

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, why: String) -> void:
	if not ok:
		push_error(why)
		failed = true

func labels(chooser: Control) -> Array:
	return chooser.find_children("*","Button",true,false).map(func(b): return b.text)

func run() -> void:
	var Records = load("res://core/dex_variants.gd")
	var Dex = load("res://scenes/dex_ui.gd")
	root.get_node("Data").load_core_tables()
	var save := {"dex":{"seen":[74],"caught":[]}}
	for sample in [{"species_id":990},{"species_id":19,"form":"RATTATA_ALOLA","shiny_kind":"square"},
			{"species_id":19,"form":"RATTATA_ALOLA","shiny_kind":"none","tera_active":true,"tera_type":"fire"}]:
		Records.record(save, sample, false)
	var original := save.duplicate(true)
	var ui = Dex.new()
	root.add_child(ui)
	ui.setup(save.dex.seen, save.dex.caught, save.dex_variants)
	ui._show_detail(232)
	expect(ui.options.size()==1 and ui.current.species_id==990, "seeing Iron Treads exposed Donphan or Great Tusk")
	expect(not ui._matches_record(232,"great-tusk") and ui._matches_record(232,"990"), "search leaked an unknown form")
	ui._show_detail(19)
	expect(ui.options.size()==1 and ui.current.art_key=="RATTATA_ALOLA" and ui.shiny_kind=="square","unseen normal Rattata appeared")
	ui._pick_shine()
	expect("◇ 方块闪" in labels(ui.chooser) and not "★ 星星闪" in labels(ui.chooser), "unobserved sparkle selectable")
	ui._select_shine("none")
	expect(ui.tera=="fire","unseen combination of normal colour and no Tera")
	ui._pick_battle()
	expect(not "常态" in labels(ui.chooser) and not "极巨化" in labels(ui.chooser),"unobserved battle states selectable")
	ui._select_battle("water")
	expect(ui.tera=="fire","unseen Tera selected")
	ui.handle_back()
	ui._show_detail(74)
	expect(ui.current.is_empty() and ui.options.is_empty(),"legacy species ID invented appearance")
	ui._show_detail(6)
	expect(ui.current.is_empty() and not ui._matches_record(6,"喷火龙"),"unseen species name revealed")
	expect(save==original,"opening a notebook created encounters")
	print("DEX SIGHTINGS ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
