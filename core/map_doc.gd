class_name MapDoc
extends RefCounted
## Проект карты (ТЗ §7.1): карта главы в формате игры (map), записи мест региона для locations.json,
## откуда взята каждая текстура (textures), подключённые паки и состояние редактора.
## Все правки идут через edit()/commit() — так работают отмена и повтор (ФТ: Ctrl+Z / Ctrl+Y без ограничения).

signal changed(what: String)

const FORMAT := 1
## Поля карты, которые редактор понимает и показывает в своих панелях; остальное — «Дополнительно» (ФТ-34).
const KNOWN_KEYS := ["_doc", "region", "art", "base", "height", "water", "fog", "view_top", "foot", "zoom", "levels", "places",
	"variants", "sockets", "paths", "ebb_sockets", "emerge_groups", "event_states", "phase_states", "place_decals",
	"path_decals", "mod_decals", "traces", "haze", "edge_glow", "storm_band", "path_sets", "water_paths", "water_phases",
	"fragile", "risky", "rubble", "rubble_phase", "rubble_tex", "exposed", "zones", "movers", "threat", "decals", "point_tex",
	"tribute_fallback"]
## Порядок ключей новой карты — как в картах игры.
const KEY_ORDER := ["_doc", "region", "art", "base", "height", "water", "fog", "view_top", "foot", "zoom", "levels", "places",
	"variants", "sockets", "paths"]

var path := ""                ## файл .mapproj ("" — не сохранён)
var game := ""                ## папка игры SunLess
var region := ""
var chapter := ""             ## глава для новых мест в locations.json
var map: Dictionary = {}      ## то же, что data/maps/<регион>.json
var locations: Dictionary = {}   ## id → запись locations.json (места региона)
var shops: Dictionary = {}    ## id → запись shops.json (лавки на этой карте; только чтение, кроме флага)
var textures: Dictionary = {} ## имя в игре → {pack, tex}
var packs: Array = []         ## [{id, version, path}]
var editor: Dictionary = {"view": [0.5, 0.5, 1.0], "layers": {}, "notes": {}, "bookmarks": []}
var dirty := false

var _undo: Array = []
var _redo: Array = []
var _pending: Variant = null
var _pending_label := ""


static func new_map(region_id: String) -> MapDoc:
	var d := MapDoc.new()
	d.region = region_id
	d.map = {"region": region_id, "art": "res://art/map/%s/" % region_id, "base": "base.webp", "fog": "fog_tile.webp",
		"view_top": 0.06, "foot": 0.28, "zoom": 1.15, "places": {}, "paths": []}
	return d


# --- отмена / повтор -----------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	return {"map": map.duplicate(true), "locations": locations.duplicate(true), "shops": shops.duplicate(true),
		"textures": textures.duplicate(true), "chapter": chapter, "region": region}


func _restore(s: Dictionary) -> void:
	map = s.map.duplicate(true)
	locations = s.locations.duplicate(true)
	shops = s.shops.duplicate(true)
	textures = s.textures.duplicate(true)
	chapter = s.chapter
	region = s.region


## Начать правку (снимок «до»). Долгое действие (перетаскивание) — begin() при нажатии, commit() при отпускании.
func begin(label: String) -> void:
	if _pending == null:
		_pending = _snapshot()
		_pending_label = label


func commit(what: String = "map") -> void:
	if _pending == null:
		return
	_undo.append({"label": _pending_label, "state": _pending})
	_redo.clear()
	_pending = null
	dirty = true
	changed.emit(what)


## Отменить незаконченную правку (Esc во время перетаскивания).
func cancel() -> void:
	if _pending != null:
		_restore(_pending)
		_pending = null
		changed.emit("map")


## Правка одним вызовом: edit("Тропа", func(): …).
func edit(label: String, fn: Callable, what: String = "map") -> Variant:
	begin(label)
	var r: Variant = fn.call()
	commit(what)
	return r


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo_label() -> String:
	return "" if _undo.is_empty() else str(_undo[-1].label)


func redo_label() -> String:
	return "" if _redo.is_empty() else str(_redo[-1].label)


func undo() -> bool:
	if _undo.is_empty():
		return false
	var it: Dictionary = _undo.pop_back()
	_redo.append({"label": it.label, "state": _snapshot()})
	_restore(it.state)
	dirty = true
	changed.emit("map")
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	var it: Dictionary = _redo.pop_back()
	_undo.append({"label": it.label, "state": _snapshot()})
	_restore(it.state)
	dirty = true
	changed.emit("map")
	return true


func history() -> Array:
	return _undo.map(func(x: Dictionary) -> String: return str(x.label))


# --- доступ --------------------------------------------------------------------------------------

func places() -> Dictionary:
	if not map.has("places"):
		map["places"] = {}
	return map["places"]


func paths() -> Array:
	if not map.has("paths"):
		map["paths"] = []
	return map["paths"]


func sockets() -> Array:
	return map.get("sockets", [])


func place(lid: String) -> Dictionary:
	return places().get(lid, {})


func at(lid: String) -> Vector2:
	var a: Array = place(lid).get("at", [0.5, 0.5])
	return Vector2(float(a[0]), float(a[1]))


func size_of(lid: String) -> float:
	return float(place(lid).get("size", 0.12))


func states(lid: String) -> Array:
	return Array(place(lid).get("states", ["dry"]))


func loc(lid: String) -> Dictionary:
	return locations.get(lid, {})


func display_name(lid: String) -> String:
	if locations.has(lid):
		return str(locations[lid].get("name", lid))
	if shops.has(lid):
		return str(shops[lid].get("name", lid))
	return lid


func is_shop(lid: String) -> bool:
	return shops.has(lid)


func is_emerging(lid: String) -> bool:
	return bool(loc(lid).get("emerge", false))


func height_of(lid: String) -> String:
	if is_shop(lid):
		return "high"
	return str(loc(lid).get("height", ""))


## Постоянные места (без появляющихся): узлы графа «без тупиков».
func permanent() -> Array:
	var out: Array = []
	for lid: String in places():
		if not is_emerging(lid):
			out.append(lid)
	return out


func base_aspect() -> float:
	return float(editor.get("aspect", 2.0))


# --- места ---------------------------------------------------------------------------------------

static func r3(x: float) -> float:
	return snappedf(x, 0.001)


## Свободный id места на основе желаемого (coral_maze → coral_maze_2).
func free_id(want: String) -> String:
	var base := TexPack.slug(want)
	if not places().has(base) and not locations.has(base) and not shops.has(base):
		return base
	var n := 2
	while places().has("%s_%d" % [base, n]) or locations.has("%s_%d" % [base, n]):
		n += 1
	return "%s_%d" % [base, n]


## Добавить место (без снимка истории — вызывать внутри edit()). states — облики; textures — {облик: [пак, текстура]}.
func add_place(lid: String, p: Vector2, sz: float, sts: Array, name: String = "") -> void:
	places()[lid] = {"at": [r3(p.x), r3(p.y)], "size": r3(sz), "states": sts.duplicate()}
	if not locations.has(lid) and not shops.has(lid):
		locations[lid] = new_location(lid, name if name != "" else lid, p)


func new_location(lid: String, name: String, p: Vector2) -> Dictionary:
	var e := {"id": lid, "name": name, "chapter": chapter if chapter != "" else region, "region": region,
		"pos": [r3(p.x), r3(p.y)], "height": "mid", "text": "",
		"camp": {"rest": 10, "beds": 0, "danger": 0.2, "services": []}}
	return e


func move_place(lid: String, p: Vector2) -> void:
	if not places().has(lid):
		return
	places()[lid]["at"] = [r3(clampf(p.x, 0.0, 1.0)), r3(clampf(p.y, 0.0, 1.0))]


func set_size(lid: String, sz: float) -> void:
	if places().has(lid):
		places()[lid]["size"] = r3(clampf(sz, 0.02, 0.5))


## Удалить место вместе с тропами и упоминаниями в правилах карты (запись в locations тоже).
func remove_place(lid: String) -> void:
	places().erase(lid)
	map["paths"] = paths().filter(func(e: Array) -> bool: return not e.has(lid))
	locations.erase(lid)
	for k: String in textures.keys():
		if k.begins_with(lid + "_") and _tex_place(k) == lid:
			textures.erase(k)
	if map.has("variants"):
		map["variants"].erase(lid)
	if map.has("water_paths"):
		map["water_paths"] = Array(map["water_paths"]).filter(func(e: Array) -> bool: return not e.has(lid))
	if map.has("path_sets"):
		for i in Array(map["path_sets"].get("sets", [])).size():
			map["path_sets"]["sets"][i] = Array(map["path_sets"]["sets"][i]).filter(func(e: Array) -> bool: return not e.has(lid))
	for key: String in ["event_states", "place_decals"]:
		if map.has(key):
			map[key] = Array(map[key]).filter(func(e: Dictionary) -> bool: return str(e.get("place", "")) != lid)
	if map.has("path_decals"):
		map["path_decals"] = Array(map["path_decals"]).filter(func(e: Dictionary) -> bool: return not Array(e.get("path", [])).has(lid))
	for key2: String in ["phase_states", "fragile"]:
		if map.has(key2):
			map[key2].erase(lid)
	if map.has("exposed"):
		map["exposed"] = Array(map["exposed"]).filter(func(x: String) -> bool: return x != lid)


## Чья это текстура по имени: место с самым длинным совпадающим id.
func _tex_place(nm: String) -> String:
	var best := ""
	for lid: String in places():
		if nm.begins_with(lid + "_") and lid.length() > best.length():
			best = lid
	return best


## Переименовать место во всех полях карты, в locations и в источниках текстур.
func rename_place(old: String, nw: String) -> String:
	nw = TexPack.slug(nw)
	if nw == old:
		return ""
	if places().has(nw) or locations.has(nw):
		return "место %s уже есть" % nw
	if not places().has(old):
		return "нет места %s" % old
	var owned: Array = textures.keys().filter(func(k: String) -> bool: return _tex_place(k) == old)
	map = _rename_in(map, old, nw)
	var newp := {}
	for k: String in places():
		newp[nw if k == old else k] = places()[k]
	map["places"] = newp
	if locations.has(old):
		var e: Dictionary = locations[old]
		e["id"] = nw
		var nl := {}
		for k2: String in locations:
			nl[nw if k2 == old else k2] = locations[k2]
		locations = nl
	var nt := {}
	for k3: String in textures:
		if owned.has(k3):
			nt[nw + k3.substr(old.length())] = textures[k3]
		else:
			nt[k3] = textures[k3]
	textures = nt
	return ""


## Замена id во вложенных структурах: строки, равные old, и ключи словарей, равные old.
func _rename_in(v: Variant, old: String, nw: String) -> Variant:
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			var nk: Variant = nw if (k is String and k == old) else k
			out[nk] = _rename_in(v[k], old, nw)
		return out
	if v is Array:
		var a: Array = []
		for x: Variant in v:
			a.append(_rename_in(x, old, nw))
		return a
	if v is String and v == old:
		return nw
	return v


# --- облики --------------------------------------------------------------------------------------

## Источник текстуры игры: {pack, tex} или {}.
func source(game_name: String) -> Dictionary:
	var s: Variant = textures.get(game_name, {})
	if s is String:
		return {"pack": s, "tex": game_name}
	return s


func set_source(game_name: String, pack_id: String, tex: String) -> void:
	textures[game_name] = {"pack": pack_id, "tex": tex}


func add_state(lid: String, st: String, pack_id: String, tex: String) -> void:
	if not places().has(lid):
		return
	var sts: Array = places()[lid].get("states", [])
	if not sts.has(st):
		sts.append(st)
	places()[lid]["states"] = sts
	set_source("%s_%s" % [lid, st], pack_id, tex)


func remove_state(lid: String, st: String) -> void:
	if not places().has(lid):
		return
	var sts: Array = places()[lid].get("states", [])
	sts.erase(st)
	textures.erase("%s_%s" % [lid, st])
	if map.has("variants") and map["variants"].has(lid):
		map["variants"][lid] = Array(map["variants"][lid]).filter(func(x: String) -> bool: return x != st)


## Облик по умолчанию — первый в списке (игра берёт dry, если он есть, иначе первый).
func make_default_state(lid: String, st: String) -> void:
	var sts: Array = places().get(lid, {}).get("states", [])
	if sts.has(st):
		sts.erase(st)
		sts.push_front(st)


# --- тропы ---------------------------------------------------------------------------------------

static func same_pair(e: Array, a: String, b: String) -> bool:
	return e.size() == 2 and ((str(e[0]) == a and str(e[1]) == b) or (str(e[0]) == b and str(e[1]) == a))


func has_path(a: String, b: String) -> bool:
	return paths().any(func(e: Array) -> bool: return same_pair(e, a, b))


## Тропа есть — убрать, нет — добавить. "" или причина отказа.
func toggle_path(a: String, b: String) -> String:
	if a == b:
		return "тропа к самому себе запрещена"
	if not places().has(a) or not places().has(b):
		return "нет такого места"
	if has_path(a, b):
		map["paths"] = paths().filter(func(e: Array) -> bool: return not same_pair(e, a, b))
	else:
		paths().append([a, b])
	return ""


func path_places(lid: String) -> Array:
	var out: Array = []
	for e: Array in paths():
		if str(e[0]) == lid:
			out.append(str(e[1]))
		elif str(e[1]) == lid:
			out.append(str(e[0]))
	return out


# --- площадки ------------------------------------------------------------------------------------

func add_socket(p: Vector2) -> int:
	if not map.has("sockets"):
		map["sockets"] = []
	map["sockets"].append([r3(p.x), r3(p.y)])
	return map["sockets"].size() - 1


func move_socket(i: int, p: Vector2) -> void:
	if i >= 0 and i < sockets().size():
		map["sockets"][i] = [r3(clampf(p.x, 0, 1)), r3(clampf(p.y, 0, 1))]


## Удалить площадку: номера после неё сдвигаются, ссылки в группах обновляются (ФТ-20).
func remove_socket(i: int) -> void:
	if i < 0 or i >= sockets().size():
		return
	map["sockets"].remove_at(i)
	var fix := func(a: Array) -> Array:
		var out: Array = []
		for x: Variant in a:
			var n := int(x)
			if n == i:
				continue
			out.append(n - 1 if n > i else n)
		return out
	if map.has("ebb_sockets"):
		map["ebb_sockets"] = fix.call(Array(map["ebb_sockets"]))
	for g: String in map.get("emerge_groups", {}):
		var grp: Dictionary = map["emerge_groups"][g]
		grp["sockets"] = fix.call(Array(grp.get("sockets", [])))


# --- поля «Дополнительно» ------------------------------------------------------------------------

func unknown_fields() -> Dictionary:
	var out := {}
	for k: String in map:
		if not KNOWN_KEYS.has(k):
			out[k] = map[k]
	return out


## Карта для записи в игру: ключи в порядке игры (известные первыми), координаты округлены до 0,001.
func map_for_game() -> Dictionary:
	var m := map.duplicate(true)
	m["region"] = region
	if not m.has("art") or str(m.art) == "":
		m["art"] = "res://art/map/%s/" % region
	# порядок ключей — как в файле игры; у новой карты — как в new_map()
	return m


# --- сохранение проекта (.mapproj) ---------------------------------------------------------------

func to_project() -> Dictionary:
	return {"format": FORMAT, "game": game, "region": region, "chapter": chapter, "packs": packs, "textures": textures,
		"map": map, "locations": locations, "shops": shops, "editor": editor}


static func from_project(d: Dictionary, file: String = "") -> MapDoc:
	var doc := MapDoc.new()
	doc.path = file
	doc.game = str(d.get("game", "")).replace("\\", "/").trim_suffix("/")
	doc.region = str(d.get("region", ""))
	doc.chapter = str(d.get("chapter", ""))
	doc.packs = Array(d.get("packs", []))
	doc.textures = Dictionary(d.get("textures", {}))
	doc.map = Dictionary(d.get("map", {}))
	doc.locations = Dictionary(d.get("locations", {}))
	doc.shops = Dictionary(d.get("shops", {}))
	var ed: Dictionary = d.get("editor", {})
	for k: String in ed:
		doc.editor[k] = ed[k]
	return doc


func save(file: String = "") -> String:
	if file != "":
		path = file
	if path == "":
		return "не выбран файл проекта"
	var err := JsonX.write_file(path, to_project())
	if err == "":
		dirty = false
		changed.emit("saved")
	return err


static func load_project(file: String) -> MapDoc:
	var d: Variant = JsonX.read_file(file)
	if not d is Dictionary:
		return null
	return from_project(d, file)
