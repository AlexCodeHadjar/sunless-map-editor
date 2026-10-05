extends TestCase


func test_numbers_keep_type() -> void:
	var v: Dictionary = JsonX.parse('{"a": 55, "b": 1.0, "c": 0.712, "d": -3, "e": 1e-05, "f": [true, null, "x"]}')
	eq(typeof(v.a), TYPE_INT, "целое остаётся целым")
	eq(typeof(v.b), TYPE_FLOAT, "1.0 — дробное")
	eq(JsonX.stringify(v, 1), '{\n "a": 55,\n "b": 1.0,\n "c": 0.712,\n "d": -3,\n "e": 1e-05,\n "f": [\n  true,\n  null,\n  "x"\n ]\n}', "запись как у Python")


func test_strings() -> void:
	var s := "Кириллица «кавычки» \"q\" \\ \n\t конец"
	var back: Variant = JsonX.parse(JsonX.quote(s))
	eq(back, s, "строка туда-обратно")
	eq(JsonX.quote("a\u0001"), "\"a\\u0001\"", "управляющие символы")
	eq(JsonX.parse('"\\u0416\\ud83d\\ude00"'), "Ж😀", "\\u и суррогатные пары")


func test_order_and_empty() -> void:
	var v: Variant = JsonX.parse('{"z": {}, "a": [], "m": 1}')
	eq(JsonX.stringify(v), '{\n "z": {},\n "a": [],\n "m": 1\n}', "порядок ключей и пустые")


func test_errors() -> void:
	check(JsonX.parse('{"a": }') == null, "ошибка разбора")
	check(JsonX.last_error != "", "текст ошибки")


func test_game_files_byte_exact() -> void:
	var g := game_dir()
	if g == "":
		return
	var files := ["data/locations.json", "data/shops.json"]
	for f: String in DirAccess.get_files_at(g + "/data/maps"):
		if f.ends_with(".json"):
			files.append("data/maps/" + f)
	for f2: String in files:
		var raw := FileAccess.get_file_as_string(g + "/" + f2)
		eq(JsonX.stringify(JsonX.parse(raw)) + "\n", raw, "файл игры %s без изменений" % f2)


func test_atomic_write() -> void:
	var d := tmp_dir("json")
	eq(JsonX.write_file(d + "/a.json", {"x": 1}), "", "запись")
	eq(FileAccess.get_file_as_string(d + "/a.json"), '{\n "x": 1\n}\n', "LF в конце")
	eq(JsonX.write_file(d + "/a.json", {"x": 2}), "", "перезапись")
	check(not FileAccess.file_exists(d + "/a.json.tmp"), "временный файл убран")
