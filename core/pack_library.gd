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
