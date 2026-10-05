extends TestCase
## Симуляция (v2): прилив, появление на площадке, шаг фигуры, водные тропы, сети бури, облик по фазе;
## импорт сырых картинок, обновление пака, новая лавка.

const Doc := preload("res://tests/test_doc.gd")
const Packs := preload("res://tests/test_packs.gd")
const Export := preload("res://tests/test_export.gd")


static func water_doc() -> MapDoc:
	var d := Doc.small_doc()
	d.map["height"] = "height.png"
	d.locations.a["height"] = "high"
	d.locations.b["height"] = "low"
	d.locations.c["height"] = "mid"
	return d


func test_tide() -> void:
	var s := MapSim.new(water_doc())
	check(not s.flooded("b"), "обычная вода — сухо")
	s.tide = "flood"
	check(s.flooded("b") and not s.flooded("c") and s.maybe_flooded("c"), "прилив: низина тонет, средняя — может")
	s.tide = "storm"
	check(s.flooded("c") and not s.flooded("a"), "шторм: тонут и средние, высота — никогда")
	eq(s.route("a", "c"), [], "через затопленную низину не пройти")
	eq(s.route("a", "c", false), ["b", "c"], "путь задания — и через воду")
	eq(s.why_not("a", "b"), "Участок под водой — отлив позже", "причина «нельзя»")


func test_emerge_on_socket() -> void:
	var d := Doc.small_doc()
	d.add_place("isle", Vector2(0.5, 0.5), 0.1, ["dry"])
	d.locations.isle["emerge"] = true
	d.add_socket(Vector2(0.78, 0.6))
	var s := MapSim.new(d)
	check(not s.present("isle"), "появляющегося места нет, пока оно не на площадке")
	s.emerged["isle"] = 0
	check(s.present("isle"), "на площадке — есть")
	eq(s.anchor("isle"), Vector2(0.78, 0.6), "стоит на площадке")
	check(s.links().any(func(e: Array) -> bool: return MapDoc.same_pair(e, "isle", "c")), "тропа к ближайшему постоянному месту, как в игре")


func test_step_and_water_paths() -> void:
	var d := Doc.small_doc()
	d.map["water_paths"] = [["a", "c"]]
	d.map["water_phases"] = ["night"]
	var s := MapSim.new(d)
	eq(s.why_not("a", "c"), "По Чёрной воде — только на лодке", "без лодки")
	s.boat = true
	s.phase = "day"
	eq(s.why_not("a", "c"), "По Чёрной воде — только ночью", "не та фаза")
	s.phase = "night"
	eq(s.why_not("a", "c"), "", "ночью на лодке — можно")
	eq(s.why_not("a", "a"), "", "на месте")
	check(s.why_not("a", "zzz") != "", "не сосед")


func test_storm_sets_and_rubble() -> void:
	var d := Doc.small_doc()
	d.toggle_path("b", "c")
	d.map["path_sets"] = {"storm_phase": "ash_storm", "sets": [[["b", "c"]], [["a", "c"]]]}
	var s := MapSim.new(d)
	eq(s.route("a", "c"), ["b", "c"], "сеть 1")
	s.path_set = 1
	eq(s.route("a", "c"), ["c"], "сеть 2")
	d.map["rubble"] = {"R1": {"at": [0.5, 0.5], "pair": ["a", "c"]}}
	s.rubble_blocked["R1"] = true
	eq(s.route("a", "c"), [], "завал закрывает тропу")


func test_phase_states() -> void:
	var d := Doc.small_doc()
	d.places().b["states"] = ["dry", "night_glow", "storm"]
	d.map["phase_states"] = {"b": {"night": "night_glow"}}
	var s := MapSim.new(d)
	eq(s.place_state("b"), "dry", "обычно")
	s.phase = "night"
	eq(s.place_state("b"), "night_glow", "ночью — по фазе")
	s.phase = "storm"
	eq(s.place_state("b"), "storm", "шторм")


func test_raw_import() -> void:
	var img := Image.create(200, 120, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 0, 1))
	img.fill_rect(Rect2i(60, 20, 40, 80), Color(0.4, 0.5, 0.3))
	var clean := RawImport.remove_chroma(img)
	eq(clean.get_pixel(1, 1).a, 0.0, "пурпурный фон стал прозрачным")
	eq(clean.get_pixel(80, 60).a, 1.0, "место осталось")
	var sq := RawImport.center_square(clean, 256)
	eq(sq.get_size(), Vector2i(256, 256), "квадрат")
	var used := sq.get_used_rect()
	check(absi(used.get_center().x - 128) <= 2 and absi(used.get_center().y - 128) <= 2, "место по центру")
	check(used.size.y > 220, "место растянуто до поля 5%")
	var d := tmp_dir("raw")
	eq(RawImport.save(sq, "place", "Swamp Hut", "dry", d), "", "сохранено")
	var p := TexPack.open(d)
	check(p.textures.has("swamp_hut_dry") and str(p.textures.swamp_hut_dry.kind) == "place", "в паке — облик места")
	eq(RawImport.rel_path("decal", "skull", ""), "decals/decal_skull.png", "метка получает приставку decal_")


func test_pack_update() -> void:
	var d := tmp_dir("pack_upd")
	Packs.make_pack(d + "/p")
	var lib := PackLibrary.new()
	lib.path_file = d + "/lib.json"
	var p := lib.add(d + "/p")
	eq(lib.diff(p.id).new, [], "сразу после подключения — без изменений")
	make_image(64, 64, Color.YELLOW).save_png(d + "/p/decals/decal_new.png")
	DirAccess.remove_absolute(d + "/p/decals/decal_skull.png")
	make_image(256, 256, Color.CYAN).save_png(d + "/p/places/tower/dry.png")
	var df := lib.diff(p.id)
	eq(df.new, ["decal_new"], "новая текстура")
	eq(df.missing, ["decal_skull"], "пропавшая текстура")
	eq(df.changed, ["tower_dry"], "изменённая текстура")
	lib.accept(p.id)
	eq(lib.diff(p.id).changed, [], "после принятия — без изменений")


func test_new_shop_export() -> void:
	var root := tmp_dir("shop_exp")
	Export.fake_game(root + "/game")
	JsonX.write_file(root + "/game/data/shops.json", [{"id": "old_shop", "chapter": "x", "name": "Лавка", "pos": [0, 0], "slots": 3, "refresh_every": 7, "stock": [{"card": "K01"}], "services": []}])
	var doc := Doc.small_doc()
	doc.game = root + "/game"
	doc.shops["b"] = {"id": "b", "chapter": "test", "name": "Новая лавка", "pos": [0.5, 0.5], "slots": 3, "refresh_every": 7, "stock": [{"card": "K01"}]}
	doc.locations.erase("b")
	var pl := GameIO.plan(doc, null if false else PackLibrary.new())
	var shops_item: Array = pl.items.filter(func(it: Dictionary) -> bool: return it.rel == "data/shops.json")
	eq(shops_item.size(), 1, "shops.json меняется")
	var written: Array = JsonX.parse((shops_item[0].data as PackedByteArray).get_string_from_utf8())
	eq(written.map(func(s: Dictionary) -> String: return s.id), ["old_shop", "b"], "новая лавка — в конце, старая на месте")
	eq(MapChecks.errors(MapChecks.run(doc, null)).size(), 0, "лавка считается высотой и проходом")
	eq(GameIO.game_shop_template(root + "/game", "nope").get("id"), "old_shop", "шаблон ассортимента")


func test_height_map_check() -> void:
	var d := tmp_dir("hm")
	var doc := water_doc()
	var lib := PackLibrary.new()
	lib.path_file = d + "/lib.json"
	DirAccess.make_dir_recursive_absolute(d + "/p/base")
	var hm := Image.create(200, 100, false, Image.FORMAT_L8)
	hm.fill(Color(0.8, 0.8, 0.8))   # всё высоко (204)
	hm.save_png(d + "/p/base/height.png")
	var p := lib.add(d + "/p")
	doc.set_source("height", p.id, "height")
	var rows := MapChecks.run(doc, TexSource.new(doc, lib))
	var hits: Array = rows.filter(func(r: Dictionary) -> bool: return r.code == "height_map")
	eq(hits.size(), 1, "низина выше прилива — предупреждение")
	eq(Array(hits[0].places), ["b"], "про низину b")
