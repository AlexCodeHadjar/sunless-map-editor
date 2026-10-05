class_name PackLibrary
extends RefCounted
## Библиотека паков (ФТ-01): подключённые папки и архивы, доступные во всех проектах.
## Хранится в user://library.json ({packs: [{path, enabled}]}); файлы паков не трогаются.

signal changed

const FILE := "user://library.json"

var entries: Array = []      ## [{path, enabled}]
var packs: Dictionary = {}   ## id → TexPack (только загруженные)
var path_file := FILE


static func load_default() -> PackLibrary:
	var lib := PackLibrary.new()
	var env := OS.get_environment("SUNLESS_MAP_LIBRARY")
	if env != "":
		lib.path_file = env
	lib.load_file()
	return lib


func load_file() -> void:
	entries.clear()
	packs.clear()
	var d: Variant = JsonX.read_file(path_file)
	if d is Dictionary:
		entries = Array(d.get("packs", []))
	for e: Dictionary in entries:
		_open(e)


func save() -> String:
	return JsonX.write_file(path_file, {"packs": entries})


func _open(e: Dictionary) -> TexPack:
	var p := TexPack.open(str(e.path))
	# пак «Из игры» и другие паки с закреплённым id/названием
	if str(e.get("fixed_id", "")) != "":
		p.id = str(e.fixed_id)
	if str(e.get("name", "")) != "":
		p.name = str(e.name)
	# одинаковые id у разных паков — второй получает суффикс (его текстуры всё равно видны отдельно)
	var pid := p.id
	var n := 2
	while packs.has(pid) and packs[pid].root != p.root:
		pid = "%s_%d" % [p.id, n]
		n += 1
	p.id = pid
	e["id"] = pid
	packs[pid] = p
	return p


## Подключить папку или .zip. Возвращает пак (или уже подключённый с тем же путём).
func add(path: String, fixed_id: String = "", title: String = "") -> TexPack:
	var norm := path.replace("\\", "/").trim_suffix("/")
	for e: Dictionary in entries:
		if str(e.path) == norm:
			e["enabled"] = true
			save()
			changed.emit()
			return packs.get(str(e.get("id", "")))
	var e2 := {"path": norm, "enabled": true}
	if fixed_id != "":
		e2["fixed_id"] = fixed_id
	if title != "":
		e2["name"] = title
	entries.append(e2)
	var p := _open(e2)
	e2["snapshot"] = signature(p)
	e2["version"] = p.version
	save()
	changed.emit()
	return p


## Убрать пак из библиотеки (файлы не трогаются).
func remove(pack_id: String) -> void:
	for e: Dictionary in entries.duplicate():
		if str(e.get("id", "")) == pack_id:
			entries.erase(e)
	packs.erase(pack_id)
	save()
	changed.emit()


func set_enabled(pack_id: String, on: bool) -> void:
	for e: Dictionary in entries:
		if str(e.get("id", "")) == pack_id:
			e["enabled"] = on
	save()
	changed.emit()


func is_enabled(pack_id: String) -> bool:
	for e: Dictionary in entries:
		if str(e.get("id", "")) == pack_id:
			return bool(e.get("enabled", true))
	return false


## Перечитать пак с диска (после правки файлов или новой версии).
func reload(pack_id: String) -> TexPack:
	for e: Dictionary in entries:
		if str(e.get("id", "")) == pack_id:
			var p := TexPack.open(str(e.path))
			p.id = pack_id
			if str(e.get("name", "")) != "":
				p.name = str(e.name)
			packs[pack_id] = p
			changed.emit()
			return p
	return null


func get_pack(pack_id: String) -> TexPack:
	return packs.get(pack_id)


func by_path(path: String) -> TexPack:
	var norm := path.replace("\\", "/").trim_suffix("/")
	for p: TexPack in packs.values():
		if p.root == norm:
			return p
	return null


func enabled_packs() -> Array:
	var out: Array = []
	for e: Dictionary in entries:
		if bool(e.get("enabled", true)) and packs.has(str(e.get("id", ""))):
			out.append(packs[str(e.id)])
	return out


## Где есть текстура с таким именем: [pack_id, …] в порядке библиотеки.
func find(nm: String) -> Array:
	var out: Array = []
	for p: TexPack in enabled_packs():
		if p.textures.has(nm):
			out.append(p.id)
	return out


# --- обновление пака (ФТ-04) ---------------------------------------------------------------------

## Отпечаток текстур пака: имя → «файл|размер|время» (у архива — по содержимому).
static func signature(p: TexPack) -> Dictionary:
	var out := {}
	for nm: String in p.textures:
		var f := str(p.textures[nm].file)
		if p.is_zip:
			out[nm] = "%s|%s" % [f, p.file_hash(nm)]
		else:
			var path := p.root + "/" + f
			var fa := FileAccess.open(path, FileAccess.READ)
			var ln := fa.get_length() if fa != null else 0
			if fa != null:
				fa.close()
			out[nm] = "%s|%d|%d" % [f, ln, FileAccess.get_modified_time(path)]
	return out


func entry(pack_id: String) -> Dictionary:
	for e: Dictionary in entries:
		if str(e.get("id", "")) == pack_id:
			return e
	return {}


## Что изменилось в паке с момента подключения/последнего принятия: {new, changed, missing, version_was, version}.
func diff(pack_id: String) -> Dictionary:
	var e := entry(pack_id)
	var p := reload(pack_id)
	if p == null or e.is_empty():
		return {}
	var was: Dictionary = e.get("snapshot", {})
	var now := signature(p)
	var out := {"new": [], "changed": [], "missing": [], "version_was": int(e.get("version", p.version)), "version": p.version}
	for nm: String in now:
		if not was.has(nm):
			out.new.append(nm)
		elif str(was[nm]) != str(now[nm]):
			out.changed.append(nm)
	for nm2: String in was:
		if not now.has(nm2):
			out.missing.append(nm2)
	return out


## Принять текущее состояние пака как известное.
func accept(pack_id: String) -> void:
	var e := entry(pack_id)
	var p := get_pack(pack_id)
	if e.is_empty() or p == null:
		return
	e["snapshot"] = signature(p)
	e["version"] = p.version
	save()
