extends SceneTree
## godot --headless --path . --script tools/test_dex_catalog.gd
var catalog
var failed := false

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, why: String) -> void:
	if not value:
		failed = true
		push_error("DEX CATALOG " + why)

func variants_by_key(entry: int) -> Dictionary:
	var rows := {}
	for v in catalog.variants(entry):
		expect(not rows.has(v.key), "duplicate variant " + String(v.key))
		rows[v.key] = v
	return rows

func run() -> void:
	root.get_node("Data").load_core_tables()
	catalog = load("res://core/dex_catalog.gd")
	var ids: Array = catalog.entry_ids()
	expect(ids.size() == 1003, "unexpected entry count")
	var old := [984,990,232,"1007",1008,967,1023,0]
	expect(catalog.aggregate(old) == [232,638,967] and old[0] == 984, "legacy IDs were lost or mutated")
	for term in ["0984","#990","Great Tusk","铁辙迹","铁轍迹"]:
		expect(catalog.matches(232,term), "paradox search " + term)
	for pair in [[985,39],[986,591],[987,200],[988,637],[989,82],[991,225],[992,297],
			[993,635],[994,637],[995,248],[1005,373],[1006,475],[1009,245],[1010,640],
			[1020,244],[1021,243],[1022,639],[1023,638]]:
		expect(catalog.entry_id(pair[0]) == pair[1], "paradox mapping " + str(pair))
	expect(catalog.preferred_variant(232,"#990").species_id == 990 and catalog.preferred_variant(232,"铁辙迹").species_id == 990, "wrong exact match")
	expect(catalog.entry_name(232) == "顿甲", "canonical name")
	var elephant := variants_by_key(232)
	expect(catalog.stats(elephant["great-tusk"]).id == 984, "battle species overwritten")
	expect(catalog.stats(elephant["iron-treads"]).types == ["ground","steel"], "paradox stats lost")
	expect(variants_by_key(282).has("iron-valiant") and not catalog.matches(282,"1006"), "secondary reference/search")
	for pair in [[201,28],[493,18],[666,20],[773,18],[774,14],[869,64],[1017,8]]:
		expect(variants_by_key(pair[0]).size() == pair[1], "missing forms " + str(pair))
	var unown := variants_by_key(201)
	expect(unown["unown-f"].label == "F", "Unown F")
	var v := variants_by_key(666)
	expect(v["vivillon-icy-snow"].art_key != v["vivillon-tundra"].art_key, "Vivillon patterns")
	var cake := variants_by_key(869)
	var pictures := {}
	for form in cake.values(): pictures[form.art_key] = true
	expect("" not in catalog.record_forms(cake["alcremie-matcha-cream-ribbon-sweet"]) and "" in catalog.record_forms(cake["alcremie-vanilla-cream-strawberry-sweet"]), "cosmetic unlock leaked")
	expect("EEVEE_PARTNER" in catalog.record_forms(variants_by_key(133)["eevee-starter"]), "partner Eevee old form")
	expect(pictures.size() == 64, "Alcremie combinations collapsed")
	expect(catalog.stats(variants_by_key(493)["arceus-fire"]).types == ["fire"], "Arceus Fire type")
	expect(catalog.stats(variants_by_key(773)["silvally-ice"]).types == ["ice"], "Silvally Ice type")
	expect(catalog.tera_types(variants_by_key(1017)["ogerpon-wellspring-mask"]) == ["water"], "Ogerpon mask")
	expect(catalog.tera_types(variants_by_key(1024)["terapagos-stellar"]) == ["stellar"], "Terapagos")
	expect(variants_by_key(25).has("pikachu-female") and catalog.tera_types(elephant["donphan"]).size() == 19, "female or universal Tera")
	var artwork: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/dex_art.json"))
	for species_id in [201,493,666,869]:
		var frames := {}
		for row in catalog.variants(species_id):
			frames[artwork[str(species_id)].get(row.art_key, -1)] = true
		expect(frames.size() == catalog.variants(species_id).size() and not frames.has(-1), "visually distinct atlas slots " + str(species_id))
	var backs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/dex_back_art.json"))
	var visited := {}
	for id in ids:
		for form in catalog.variants(id):
			visited[form.species_id] = true
			expect(artwork[str(int(form.species_id))].has(form.art_key), "missing atlas art " + form.key)
			expect(backs[str(int(form.species_id))].has(form.art_key), "missing rear art " + form.key)
			expect(not catalog.stats(form).get("base",{}).is_empty(), "stats missing " + form.key)
			expect(not String(form.label).is_empty(), "label missing " + form.key)
	expect(visited.size() == 1025, "incomplete battle species coverage")
	var art = load("res://core/dex_art.gd")
	var front = art.texture(25,"",false)
	var back = art.texture(25,"",false,true)
	var shiny = art.texture(25,"",true)
	expect(front is AtlasTexture and back is AtlasTexture and shiny is AtlasTexture,"Emerald Pikachu views")
	expect(front.atlas.resource_path != back.atlas.resource_path and front.atlas.resource_path != shiny.atlas.resource_path,"different front, back and shiny art")
	expect(art.texture(990,"",false)!=null and art.texture(990,"",false,true)!=null,"later species front and back artwork")
	var inspection = art.texture(255, "TORCHIC_FEMALE", false)
	var opposing = art.battle_texture(255, "TORCHIC_FEMALE", false, false)
	expect(opposing.region == art.texture(255, "", false).region and inspection.region != opposing.region, "Torchic rear-only gender mark")
	var apple = art.texture(585,"DEERLING_WINTER",false)
	var summer = art.texture(585,"DEERLING_SUMMER",false)
	expect(apple.region!=summer.region,"Deerling seasons")
	print("DEX CATALOG ", "FAIL" if failed else "PASS", " entries=",ids.size()," species=",visited.size())
	quit(1 if failed else 0)
