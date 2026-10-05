extends TestCase

const Doc := preload("res://tests/test_doc.gd")


static func codes(rows: Array) -> Array:
	return rows.map(func(r: Dictionary) -> String: return r.code)


func test_graph() -> void:
	var adj := MapGraph.adjacency([["a", "c"], ["a", "b"], ["b", "d"], ["c", "d"]])
	eq(Array(adj.a), ["b", "c"], "соседи по алфавиту")
	eq(MapGraph.route(adj, "a", "d"), ["b", "d"], "путь как в игре: при равной длине — через b")
	eq(MapGraph.distances(adj, "a"), {"a": 0, "b": 1, "c": 1, "d": 2}, "шаги")
	eq(MapGraph.route(adj, "a", "d", func(n: String) -> bool: return n == "b"), ["c", "d"], "обход закрытого места")
	eq(MapGraph.components(["a", "b", "x"], [["a", "b"]]), [["a", "b"], ["x"]], "части графа")


func test_connected_small_map() -> void:
	var d := Doc.small_doc()
	var rows := MapChecks.run(d, null)
	eq(MapChecks.errors(rows), [], "связная карта без ошибок")
	d.toggle_path("b", "c")
	rows = MapChecks.run(d, null)
	check(codes(rows).has("isolated"), "место без троп")
	check(codes(rows).has("spine_all"), "не всё связано")
	var bad: Array = rows.filter(func(r: Dictionary) -> bool: return r.code == "isolated")
	eq(Array(bad[0].places), ["c"], "виноватое место для подсветки")


func test_dry_spine() -> void:
	var d := Doc.small_doc()
	d.map["height"] = "height.png"
	d.locations.a["height"] = "high"
	d.locations.b["height"] = "low"
	d.locations.c["height"] = "high"
	var rows := MapChecks.run(d, null)
	check(codes(rows).has("spine_dry"), "высоты связаны только через низину — ошибка хребта")
	check(codes(rows).has("spine_deg"), "у высоты одна тропа")
	d.toggle_path("a", "c")
	d.add_place("d", Vector2(0.5, 0.2), 0.08, ["dry"])
	d.locations.d["height"] = "high"
	d.toggle_path("d", "a")
	d.toggle_path("d", "c")
	rows = MapChecks.run(d, null)
	check(not codes(rows).has("spine_dry"), "хребет есть")
	check(not codes(rows).has("spine_deg"), "у всех высот по две тропы")


func test_warnings() -> void:
	var d := Doc.small_doc()
	d.add_place("e", Vector2(0.51, 0.5), 0.1, ["burning"])
	d.toggle_path("e", "a")
	d.add_place("f", Vector2(0.99, 0.9), 0.1, ["dry"])
	d.toggle_path("f", "a")
	var rows := MapChecks.run(d, null)
	var c := codes(rows)
	check(c.has("overlap"), "наложение")
	check(c.has("no_dry"), "нет dry")
	check(c.has("edge"), "за краем основы")
	check(c.has("path_long"), "длинная тропа")
	check(MapChecks.errors(rows).is_empty(), "это только предупреждения")


func test_emerge_and_refs() -> void:
	var d := Doc.small_doc()
	d.locations.c["emerge"] = true
	d.locations.c["socket_group"] = "ghost"
	d.map["zones"] = {"z": {"name": "Зона", "center": "nowhere"}}
	var rows := MapChecks.run(d, null)
	var c := codes(rows)
	check(c.has("no_sockets"), "площадок нет")
	check(c.has("no_group"), "группы нет")
	check(c.has("ref"), "ссылка зоны на неизвестное место")


func test_game_maps_pass() -> void:
	var g := game_dir()
	if g == "":
		return
	var lib := PackLibrary.new()
	lib.path_file = tmp_dir("lib_checks") + "/library.json"
	for region: String in ["forgotten_shore", "academy", "ash_path", "dark_city", "real_city"]:
		var doc := GameIO.open_region(g, region, lib)
		var rows := MapChecks.run(doc, TexSource.new(doc, lib))
		eq(MapChecks.errors(rows).map(func(r: Dictionary) -> String: return r.text), [], "карта игры %s проходит проверки" % region)


func test_shore_acceptance_spine() -> void:
	var g := game_dir()
	if g == "":
		return
	var lib := PackLibrary.new()
	lib.path_file = tmp_dir("lib_checks2") + "/library.json"
	var doc := GameIO.open_region(g, "forgotten_shore", lib)
	eq(doc.places().size(), 29, "все 29 мест Берега")
	# сценарий приёмки: убрать тропу «Высота — Холм у статуи» → ошибка сухого хребта
	var hg := ""
	var sh := ""
	for lid: String in doc.places():
		if doc.display_name(lid) == "Высота":
			hg = lid
		if doc.display_name(lid) == "Холм у статуи":
			sh = lid
	check(hg != "" and sh != "" and doc.has_path(hg, sh), "тропа «Высота — Холм у статуи» есть")
	doc.toggle_path(hg, sh)
	var rows := MapChecks.run(doc, null)
	var spine: Array = rows.filter(func(r: Dictionary) -> bool: return str(r.code).begins_with("spine"))
	check(not spine.is_empty(), "проверка «сухой хребет» сообщает ошибку")
	check(spine.any(func(r: Dictionary) -> bool: return Array(r.places).has(hg) or Array(r.places).has(sh)), "и подсвечивает место")
