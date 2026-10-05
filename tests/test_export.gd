extends TestCase

const Packs := preload("res://tests/test_packs.gd")


## Мини-игра: project.godot, data/maps, locations.json с чужим регионом, shops.json.
static func fake_game(d: String) -> void:
	DirAccess.make_dir_recursive_absolute(d + "/data/maps")
	FileAccess.open(d + "/project.godot", FileAccess.WRITE).store_string("config_version=5\n")
	JsonX.write_file(d + "/data/locations.json", [
		{"id": "other1", "name": "Чужое", "chapter": "x", "region": "other"},
		{"id": "old_place", "name": "Старое", "chapter": "swamp", "region": "swamp"},
		{"id": "other2", "name": "Чужое 2", "chapter": "x", "region": "other"}])
	JsonX.write_file(d + "/data/shops.json", [])


func test_export_new_region() -> void:
	var root := tmp_dir("export")
	fake_game(root + "/game")
	Packs.make_pack(root + "/pack")
	var lib := PackLibrary.new()
	lib.path_file = root + "/library.json"
	var p := lib.add(root + "/pack")
	var doc := MapDoc.new_map("swamp")
	doc.game = root + "/game"
	doc.chapter = "swamp"
	doc.set_source("base", p.id, "base")
	doc.set_source("fog_tile", p.id, "fog_tile")
	doc.add_place("tower", Vector2(0.3, 0.4), 0.12, ["dry", "burning"])
	doc.set_source("tower_dry", p.id, "tower_dry")
	doc.set_source("tower_burning", p.id, "tower_burning")
	doc.add_place("swamp", Vector2(0.6, 0.4), 0.12, ["dry"])
	doc.set_source("swamp_dry", p.id, "swamp_dry")
	doc.toggle_path("tower", "swamp")
	doc.map["place_decals"] = [{"decal": "decal_skull", "place": "tower"}]
	doc.set_source("decal_skull", p.id, "decal_skull")
	var rows := MapChecks.run(doc, TexSource.new(doc, lib))
	eq(MapChecks.errors(rows).map(func(r: Dictionary) -> String: return r.text), [], "новая карта без ошибок")
	var pl := GameIO.plan(doc, lib)
	eq(pl.errors, [], "план без ошибок")
	var st := {}
	for it: Dictionary in pl.items:
		st[str(it.rel)] = str(it.status)
	eq(st.get("data/maps/swamp.json"), "new", "карта новая")
	eq(st.get("data/locations.json"), "changed", "locations обновится")
	eq(st.get("art/map/swamp/tower_burning.webp"), "new", "облик места")
	eq(st.get("art/map/swamp/base.webp"), "new", "основа")
	var res := GameIO.write(doc, pl.items)
	eq(res.errors, [], "записано без ошибок")
	var img := Image.load_from_file(root + "/game/art/map/swamp/base.webp")
	eq(img.get_size(), Vector2i(3072, 1536), "основа приведена к 3072×1536")
	eq(Image.load_from_file(root + "/game/art/map/swamp/tower_dry.webp").get_size(), Vector2i(512, 512), "место 512×512")
	eq(Image.load_from_file(root + "/game/art/map/swamp/decal_skull.webp").get_size(), Vector2i(256, 256), "метка 256×256")
	var locs: Array = JsonX.read_file(root + "/game/data/locations.json")
	eq(locs.map(func(l: Dictionary) -> String: return l.id), ["other1", "tower", "swamp", "other2"], "чужие записи на месте, старая запись региона заменена")
	var m: Dictionary = JsonX.read_file(root + "/game/data/maps/swamp.json")
	eq(str(m.region), "swamp", "регион в карте")
	eq(str(m.art), "res://art/map/swamp/", "папка картинок")
	# второй экспорт без правок — ничего не пишет (ФТ-44)
	var pl2 := GameIO.plan(doc, lib)
	var changed: Array = pl2.items.filter(func(it: Dictionary) -> bool: return it.status != "same")
	eq(changed.map(func(it: Dictionary) -> String: return it.rel), [], "без правок всё совпадает")
	# правка места → меняются только карта (и запись места не меняется)
	doc.move_place("tower", Vector2(0.31, 0.4))
	var pl3 := GameIO.plan(doc, lib)
	var changed3: Array = pl3.items.filter(func(it: Dictionary) -> bool: return it.status != "same").map(func(it: Dictionary) -> String: return it.rel)
	eq(changed3, ["data/maps/swamp.json"], "сдвиг места меняет только карту")
	var res3 := GameIO.write(doc, pl3.items)
	check(res3.backup != "" and FileAccess.file_exists(res3.backup + "/data/maps/swamp.json.bak"), "резервная копия прежней карты")


func test_game_shore_noop() -> void:
	var g := game_dir()
	if g == "":
		return
	var lib := PackLibrary.new()
	lib.path_file = tmp_dir("lib_exp") + "/library.json"
	for region: String in ["forgotten_shore", "ash_path", "academy"]:
		var doc := GameIO.open_region(g, region, lib)
		var pl := GameIO.plan(doc, lib)
		eq(pl.errors, [], "план %s без ошибок" % region)
		var bad: Array = pl.items.filter(func(it: Dictionary) -> bool: return it.status != "same").map(func(it: Dictionary) -> String: return "%s:%s" % [it.rel, it.status])
		eq(bad, [], "%s: открыть и экспортировать без правок — без изменений" % region)
	# приёмка: сдвинуть место и добавить тропу → меняется только карта Берега
	var shore := GameIO.open_region(g, "forgotten_shore", lib)
	shore.move_place("stone_isle", shore.at("stone_isle") + Vector2(0.01, 0))
	shore.toggle_path("stone_isle", "coral_maze")
	var pl2 := GameIO.plan(shore, lib)
	eq(pl2.items.filter(func(it: Dictionary) -> bool: return it.status != "same").map(func(it: Dictionary) -> String: return it.rel),
		["data/maps/forgotten_shore.json"], "правка меняет только карту Берега")
