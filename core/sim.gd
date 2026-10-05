class_name MapSim
extends RefCounted
## Симуляция карты (ТЗ §6.2): какие тропы есть сейчас, куда можно пройти, маршрут, прилив, туман, облик по фазе.
## Повторяет правила игры (MapRules.links, TravelRules.route, TerrainRules, FigureRules.why_not) без состояния прохождения.

var doc: MapDoc
var tide := "normal"          ## normal | warn | flood | storm
var boat := false             ## есть лодка (водные тропы)
var phase := ""               ## фаза недели ("" — любая)
var path_set := 0             ## текущая сеть троп бури
var rubble_blocked := {}      ## R1 → true — тропа завалена
var collapsed := {}           ## место (хрупкий проход) → true — обрушено
var emerged := {}             ## появляющееся место → номер площадки
var visited: Array = []       ## посещённые места (туман)


func _init(d: MapDoc) -> void:
	doc = d


func present(lid: String) -> bool:
	return not doc.is_emerging(lid) or emerged.has(lid)


## Точка места: появившееся — на своей площадке.
func anchor(lid: String) -> Vector2:
	if emerged.has(lid):
		var sk: Array = doc.sockets()
		var i := int(emerged[lid])
		if i >= 0 and i < sk.size():
			return Vector2(float(sk[i][0]), float(sk[i][1]))
	return doc.at(lid)


## Тропы сейчас: постоянные + сеть бури + водные; без заваленных и без отсутствующих мест;
## появившееся место — одной тропой к ближайшему постоянному.
func links() -> Array:
	var m := doc.map
	var all: Array = Array(doc.paths()).duplicate()
	var sets: Array = m.get("path_sets", {}).get("sets", [])
	if not sets.is_empty():
		all.append_array(Array(sets[posmod(path_set, sets.size())]))
	all.append_array(Array(m.get("water_paths", [])))
	var out: Array = []
	for e: Array in all:
		var a := str(e[0])
		var b := str(e[1])
		if not doc.places().has(a) or not doc.places().has(b):
			continue
		if present(a) and present(b) and not _under_rubble(a, b):
			out.append([a, b])
	for lid: String in emerged:
		var near := nearest_permanent(anchor(lid), lid)
		if near != "":
			out.append([lid, near])
	return out


func nearest_permanent(p: Vector2, except: String = "") -> String:
	var best := ""
	var bd := INF
	for other: String in doc.places():
		if other == except or doc.is_emerging(other):
			continue
		var d := anchor(other).distance_to(p)
		if d < bd:
			bd = d
			best = other
	return best


func _under_rubble(a: String, b: String) -> bool:
	var rb: Dictionary = doc.map.get("rubble", {})
	for rid: String in rb:
		if rubble_blocked.get(rid, false) and MapDoc.same_pair(Array(rb[rid].get("pair", [])), a, b):
			return true
	return false


func is_water(a: String, b: String) -> bool:
	for e: Array in doc.map.get("water_paths", []):
		if MapDoc.same_pair(e, a, b):
			return true
	return false


## Под водой при этом приливе: низины — в прилив, средние — в шторм (в прилив — «может уйти»).
func flooded(lid: String) -> bool:
	if not doc.map.has("height"):
		return false
	var h := doc.height_of(lid)
	match tide:
		"flood":
			return h == "low"
		"storm":
			return h == "low" or h == "mid"
	return false


func maybe_flooded(lid: String) -> bool:
	return doc.map.has("height") and tide == "flood" and doc.height_of(lid) == "mid"


func blocked(lid: String) -> bool:
	return not present(lid) or flooded(lid) or collapsed.has(lid)


func edge_ok(a: String, b: String) -> bool:
	if not is_water(a, b):
		return true
	if not boat:
		return false
	var phases: Array = doc.map.get("water_phases", [])
	return phase == "" or phases.is_empty() or phases.has(phase)


func adjacency() -> Dictionary:
	return MapGraph.adjacency(links())


func distances(from: String) -> Dictionary:
	return MapGraph.distances(adjacency(), from, blocked, edge_ok)


## Маршрут как в игре; dry_only=false — и через воду (путь задания).
func route(from: String, to: String, dry_only: bool = true) -> Array:
	if dry_only:
		return MapGraph.route(adjacency(), from, to, blocked, edge_ok)
	return MapGraph.route(adjacency(), from, to, func(n: String) -> bool: return not present(n))


func neighbors(lid: String) -> Array:
	return adjacency().get(lid, [])


## Почему фигура не может встать на соседний участок ("" — можно). Тексты — как FigureRules.why_not.
func why_not(from: String, to: String) -> String:
	if from == to:
		return ""
	if not neighbors(from).has(to):
		return "Туда нет тропы — фигура ходит только на соседний участок"
	if doc.is_shop(to):
		return "Здесь нельзя встать лагерем — только пройти мимо"
	if not present(to):
		return "Этого места сейчас нет на карте"
	if flooded(to):
		return "Участок под водой — отлив позже"
	if collapsed.has(to):
		return "Проход обрушен"
	if is_water(from, to):
		if not boat:
			return "По Чёрной воде — только на лодке"
		if not edge_ok(from, to):
			return "По Чёрной воде — только ночью"
	return ""


## Что открыто игроку (туман): посещённые, их соседи по тропам, лавки, появившиеся места.
func known() -> Dictionary:
	var out := {}
	var adj := adjacency()
	for lid: String in visited:
		if not present(lid):
			continue
		out[lid] = true
		for n: String in adj.get(lid, []):
			out[n] = true
	for lid2: String in doc.places():
		if doc.is_shop(lid2):
			out[lid2] = true
	return out


## Облик места при этих условиях (упрощённый порядок игры: вода → фаза → событие → шторм → вариант → обычный).
func place_state(lid: String, variant: String = "") -> String:
	var have: Array = doc.states(lid)
	if flooded(lid) and have.has("flooded"):
		return "flooded"
	if collapsed.has(lid) and have.has("collapsed"):
		return "collapsed"
	if phase != "":
		var ps := str(doc.map.get("phase_states", {}).get(lid, {}).get(phase, ""))
		if ps != "" and have.has(ps):
			return ps
		for es: Dictionary in doc.map.get("event_states", []):
			if str(es.get("place", "")) == lid and Array(es.get("phase", [])).has(phase) and have.has(str(es.get("state", ""))):
				return str(es.state)
		if (phase == "storm" or phase == "ash_storm") and have.has("storm"):
			return "storm"
	if variant != "" and have.has(variant):
		return variant
	if have.has("dry"):
		return "dry"
	return str(have[0]) if not have.is_empty() else ""


## Метки по условиям (фаза, вариант): [{decal, place} | {decal, path}].
func decals() -> Array:
	var out: Array = []
	for key: String in ["place_decals", "path_decals"]:
		for d: Dictionary in doc.map.get(key, []):
			var ph: Array = d.get("phase", [])
			if phase != "" and not ph.is_empty() and not ph.has(phase):
				continue
			out.append(d)
	return out
