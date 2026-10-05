extends SceneTree
## Тесты редактора: godot --headless --path . -s res://tests/run_tests.gd [-- --only=<часть имени>]
## Папка игры для тестов на настоящих картах — переменная SUNLESS_GAME или соседняя папка ../SunLess.

const SUITES := [
	"res://tests/test_json.gd",
	"res://tests/test_packs.gd",
	"res://tests/test_doc.gd",
	"res://tests/test_checks.gd",
	"res://tests/test_export.gd",
	"res://tests/test_sim.gd",
	"res://tests/test_render.gd",
	"res://tests/test_cli.gd",
	"res://tests/test_scripts.gd",
]


func _init() -> void:
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var failed := 0
	var total := 0
	for path: String in SUITES:
		if only != "" and not path.contains(only):
			continue
		if not ResourceLoader.exists(path):
			continue
		var script: GDScript = load(path)
		if script == null:
			print("НЕ ЗАГРУЗИТЬ ", path)
			failed += 1
			continue
		var t: TestCase = script.new()
		t.name = path.get_file().get_basename()
		var t0 := Time.get_ticks_msec()
		t.run()
		total += t.checks
		failed += t.failures.size()
		print("%s %s: %d проверок, %d ошибок (%d мс)" % ["ОК " if t.failures.is_empty() else "СБОЙ", t.name, t.checks, t.failures.size(), Time.get_ticks_msec() - t0])
		for f: String in t.failures:
			print("    × ", f)
	print("Итого: %d проверок, %d ошибок" % [total, failed])
	quit(1 if failed > 0 else 0)
