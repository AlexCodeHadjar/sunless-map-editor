class_name GamePreview
extends RefCounted
## «Открыть в игре» (ФТ-41): снимок карты настоящей отрисовкой игры.
## Карта уже в игре и не менялась — снимок сразу. Иначе — временный регион editor_preview: экспорт, импорт картинок,
## снимок, затем уборка (прежние файлы игры возвращаются из резервной копии, временные удаляются).
## Блокирующий вызов — из окна запускать в фоновой задаче.

const TMP_REGION := "editor_preview"
const TMP_DIR := ".map_editor_tmp"
const MARK := "@@SNAPSHOT@@"


static func run(doc: MapDoc, lib: PackLibrary, camp: String, out: String, exe: String = "") -> Dictionary:
	if exe == "":
		exe = OS.get_executable_path()
	var game := GameIO.norm(doc.game)
	if not GameIO.is_game_dir(game):
		return {"ok": false, "error": "нет папки игры"}
	var pl := GameIO.plan(doc, lib)
	if not pl.errors.is_empty():
		return {"ok": false, "error": "; ".join(pl.errors)}
	var dirty: bool = pl.items.any(func(it: Dictionary) -> bool: return it.status != "same")
	if not dirty and doc.chapter != "":
		var r0 := _snapshot(game, doc.chapter, camp, out, exe)
		r0["temporary"] = false
		return r0
	# временный регион
	var tmp := MapDoc.from_project(doc.to_project())
	tmp.region = TMP_REGION
	tmp.chapter = TMP_REGION
	tmp.map["region"] = TMP_REGION
	tmp.map["art"] = "res://art/map/%s/" % TMP_REGION
	for lid: String in tmp.locations:
		tmp.locations[lid]["chapter"] = TMP_REGION
		tmp.locations[lid]["region"] = TMP_REGION
	for sid: String in tmp.shops:
		tmp.shops[sid]["chapter"] = TMP_REGION
	# картинки из папки игры старого региона — тоже источник (пак «Из игры» остаётся тем же)
	for nm: String in GameIO.needed(doc):
		if tmp.source(nm).is_empty():
			var src := TexSource.new(doc, lib).resolve(nm)
			if str(src.from) == "game":
				tmp.textures[nm] = {"game_file": src.path}
	var tpl := GameIO.plan(tmp, lib)
	if not tpl.errors.is_empty():
		return {"ok": false, "error": "; ".join(tpl.errors)}
	var res := GameIO.write(tmp, tpl.items)
	var result := {}
	if not res.errors.is_empty():
		result = {"ok": false, "error": "; ".join(res.errors)}
	else:
		var o: Array = []
		OS.execute(exe, GameIO.reimport_args(game), o, true)
		result = _snapshot(game, TMP_REGION, camp, out, exe)
	_cleanup(game, tpl.items, str(res.backup))
	result["temporary"] = true
	return result


static func _snapshot(game: String, chapter: String, camp: String, out: String, exe: String) -> Dictionary:
	var dir := game + "/" + TMP_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	var script := FileAccess.get_file_as_string("res://tools/game_snapshot.gd")
	JsonX.write_text(dir + "/game_snapshot.gd", script)
	var args := PackedStringArray(["--path", game, "--resolution", "1920x1080", "--position", "0,0",
		"-s", "res://%s/game_snapshot.gd" % TMP_DIR, "--", "--chapter", chapter, "--camp", camp, "--out", out])
	var o: Array = []
	var code := OS.execute(exe, args, o, true)
	_rm(dir)
	var text := "\n".join(o)
	var i := text.find(MARK)
	if i < 0:
		return {"ok": false, "error": "игра не сделала снимок (код %d)" % code, "log": text.right(1500)}
	var line := text.substr(i + MARK.length()).get_slice("\n", 0)
	var d: Variant = JSON.parse_string(line)
	return d if d is Dictionary else {"ok": false, "error": "непонятный ответ игры"}


## Вернуть игру как было: изменённые файлы — из резервной копии, новые — удалить (с файлами импорта).
static func _cleanup(game: String, items: Array, backup: String) -> void:
	for it: Dictionary in items:
		match str(it.status):
			"changed":
				var b := backup + "/" + str(it.rel) + ".bak"
				if FileAccess.file_exists(b):
					DirAccess.copy_absolute(b, str(it.file))
			"new":
				DirAccess.remove_absolute(str(it.file))
				DirAccess.remove_absolute(str(it.file) + ".import")
	var art := "%s/art/map/%s" % [game, TMP_REGION]
	if DirAccess.dir_exists_absolute(art):
		_rm(art)


static func _rm(d: String) -> void:
	for f: String in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + "/" + f)
	for s: String in DirAccess.get_directories_at(d):
		_rm(d + "/" + s)
	DirAccess.remove_absolute(d)
