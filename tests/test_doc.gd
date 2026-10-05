extends TestCase


static func small_doc() -> MapDoc:
	var d := MapDoc.new_map("test_region")
	d.chapter = "test"
	d.add_place("a", Vector2(0.2, 0.5), 0.1, ["dry"])
	d.add_place("b", Vector2(0.5, 0.5), 0.1, ["dry", "flooded"])
	d.add_place("c", Vector2(0.8, 0.5), 0.1, ["dry"])
	d.toggle_path("a", "b")
	d.toggle_path("b", "c")
	return d


func test_places_and_locations() -> void:
	var d := small_doc()
	eq(d.places().size(), 3, "три места")
	eq(str(d.locations.a.region), "test_region", "запись места создана")
	eq(str(d.locations.a.chapter), "test", "глава")
	d.move_place("a", Vector2(0.12345, 1.7))
	eq(Array(d.place("a").at), [0.123, 1.0], "округление до 0,001 и край основы")
	d.set_size("a", 0.9)
	eq(float(d.place("a").size), 0.5, "размер ограничен")
	eq(d.free_id("a"), "a_2", "свободный id")


func test_paths() -> void:
	var d := small_doc()
	check(d.has_path("b", "a"), "тропа без направления")
	eq(d.toggle_path("a", "a"), "тропа к самому себе запрещена", "к себе нельзя")
	d.toggle_path("b", "a")
	check(not d.has_path("a", "b"), "повторный щелчок убирает тропу")
	eq(d.path_places("b"), ["c"], "тропы места")


func test_remove_place_with_paths() -> void:
	var d := small_doc()
	d.map["place_decals"] = [{"decal": "decal_x", "place": "b"}]
	d.map["variants"] = {"b": ["dry"]}
	d.remove_place("b")
	eq(d.paths(), [], "тропы места убраны")
	check(not d.locations.has("b"), "запись убрана")
	eq(Array(d.map.place_decals), [], "метки места убраны")


func test_rename_everywhere() -> void:
	var d := small_doc()
	d.map["fragile"] = {"b": {"crossings": 3}}
	d.map["zones"] = {"z": {"center": "b"}}
	d.set_source("b_dry", "p", "x_dry")
	d.set_source("bb_dry", "p", "y_dry")
	d.add_place("bb", Vector2(0.5, 0.2), 0.1, ["dry"])
	eq(d.rename_place("b", "bridge"), "", "переименовано")
	check(d.places().has("bridge") and not d.places().has("b"), "место")
	check(d.has_path("a", "bridge"), "тропы")
	check(d.map.fragile.has("bridge"), "ключи словарей")
	eq(str(d.map.zones.z.center), "bridge", "ссылки в зонах")
	eq(str(d.locations.bridge.id), "bridge", "запись места")
	check(d.textures.has("bridge_dry") and d.textures.has("bb_dry"), "источники текстур (чужое bb_ не тронуто)")
	eq(d.places().keys(), ["a", "bridge", "c", "bb"], "порядок мест сохранён")


func test_sockets_renumber() -> void:
	var d := small_doc()
	for i in 4:
		d.add_socket(Vector2(0.1 * i, 0.1))
	d.map["ebb_sockets"] = [0, 1, 3]
	d.map["emerge_groups"] = {"g": {"sockets": [1, 2, 3]}}
	d.remove_socket(1)
	eq(Array(d.map.ebb_sockets), [0, 2], "площадки отлива пересчитаны")
	eq(Array(d.map.emerge_groups.g.sockets), [1, 2], "группа пересчитана")
	eq(d.sockets().size(), 3, "площадок стало три")


func test_undo_redo() -> void:
	var d := small_doc()
	d.edit("Сдвинуть", func() -> void: d.move_place("a", Vector2(0.3, 0.3)))
	d.edit("Тропа", func() -> void: d.toggle_path("a", "c"))
	check(d.has_path("a", "c"), "тропа добавлена")
	check(d.undo(), "отмена")
	check(not d.has_path("a", "c"), "тропа отменена")
	check(d.undo(), "отмена 2")
	eq(Array(d.place("a").at), [0.2, 0.5], "сдвиг отменён")
	check(d.redo() and d.redo(), "повтор дважды")
	check(d.has_path("a", "c"), "тропа вернулась")
	d.begin("Тащу")
	d.move_place("a", Vector2(0.9, 0.9))
	d.cancel()
	eq(Array(d.place("a").at), [0.3, 0.3], "Esc отменяет перетаскивание")


func test_project_roundtrip() -> void:
	var d := small_doc()
	d.set_source("a_dry", "pk", "tower_dry")
	var f := tmp_dir("proj") + "/x.mapproj"
	eq(d.save(f), "", "проект сохранён")
	var d2 := MapDoc.load_project(f)
	eq(d2.region, "test_region", "регион")
	eq(JsonX.stringify(d2.map), JsonX.stringify(d.map), "карта та же")
	eq(d2.source("a_dry"), {"pack": "pk", "tex": "tower_dry"}, "источник текстуры")
	d2.map["future_field"] = {"x": [1, 2]}
	eq(d2.unknown_fields().keys(), ["future_field"], "неизвестные поля видны в «Дополнительно»")
	check(d2.map_for_game().has("future_field"), "и сохраняются в игру")
