class_name TestCase
extends RefCounted
## Основа набора тестов: функции test_* вызываются по очереди.

var name := ""
var checks := 0
var failures: Array = []
var _current := ""


func run() -> void:
	for m: Dictionary in get_method_list():
		var mn := str(m.name)
		if mn.begins_with("test_"):
			_current = mn
			call(mn)


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures.append("%s: %s" % [_current, what])


func eq(a: Variant, b: Variant, what: String) -> void:
	checks += 1
	if typeof(a) != typeof(b) or a != b:
		failures.append("%s: %s — получено %s, ждали %s" % [_current, what, str(a).left(300), str(b).left(300)])


## Папка игры SunLess ("" — нет; тесты на настоящих картах пропускаются).
static func game_dir() -> String:
	var env := OS.get_environment("SUNLESS_GAME")
	if env != "" and GameIO.is_game_dir(env):
		return env
	var sib := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir() + "/SunLess"
	return sib if GameIO.is_game_dir(sib) else ""


## Временная папка теста (чистая).
static func tmp_dir(sub: String) -> String:
	var d := ProjectSettings.globalize_path("user://test_tmp/" + sub)
	if DirAccess.dir_exists_absolute(d):
		_rm(d)
	DirAccess.make_dir_recursive_absolute(d)
	return d


static func _rm(d: String) -> void:
	for f: String in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + "/" + f)
	for s: String in DirAccess.get_directories_at(d):
		_rm(d + "/" + s)
	DirAccess.remove_absolute(d)


## Картинка-заглушка: квадрат цвета с прозрачным краем (как виньетка) или сплошная.
static func make_image(w: int, h: int, col: Color, alpha: bool = true) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8 if alpha else Image.FORMAT_RGB8)
	img.fill(Color(0, 0, 0, 0) if alpha else col)
	if alpha:
		img.fill_rect(Rect2i(w / 4, h / 4, w / 2, h / 2), col)
	return img
