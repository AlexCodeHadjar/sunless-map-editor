class_name MapChecks
extends RefCounted
## Проверки карты (ТЗ §6.1) — те же правила, что игра проверяет при запуске (content_validator.gd), плюс подсказки
## редактора. Строка отчёта: {level: error|warn, text (для человека), places: [id], path: [a, b], socket: n, code}.
## Ошибка — экспорт запрещён; предупреждение — можно.

const OVERLAP := 0.35
const LONG_PATH := 0.35


static func run(doc: MapDoc, src: TexSource) -> Array:
	var out: Array = []
	var nm := func(lid: String) -> String: return Words.q(doc.display_name(lid))
	var places: Dictionary = doc.places()
	var m: Dictionary = doc.map
	var row := func(level: String, code: String, text: String, extra: Dictionary = {}) -> void:
		var r := {"level": level, "code": code, "text": text, "places": [], "path": [], "socket": -1}
		r.merge(extra, true)
		out.append(r)

	# --- файлы основы, воды и тумана
	if src != null:
		if not src.exists(str(m.get("base", "base.webp")).get_basename()):
			row.call("error", "base", "Нет основы карты — перетащите основу из пака на холст")
		if m.has("height"):
			if not src.exists(str(m.height).get_basename()):
				row.call("error", "height", "Нет карты высот — без неё вода не нарисуется")
			if not src.exists(str(m.get("water", "water_tile.webp")).get_basename()):
				row.call("error", "water", "Нет плитки воды")
		if not src.exists(str(m.get("fog", "fog_tile.webp")).get_basename()):
			row.call("error", "fog", "Нет плитки тумана")

	# --- места и записи locations.json
	for lid: String in places:
		if not doc.locations.has(lid) and not doc.shops.has(lid):
			row.call("error", "no_location", "%s нет в списке мест игры (locations.json)" % nm.call(lid), {"places": [lid]})
		var sts: Array = places[lid].get("states", ["dry"])
		if src != null:
			for st: String in sts:
				if not src.exists("%s_%s" % [lid, st]):
					row.call("error", "no_state_file", "У %s нет картинки облика «%s»" % [nm.call(lid), Words.state(st)], {"places": [lid]})
		if not sts.is_empty() and not sts.has("dry"):
			row.call("warn", "no_dry", "У %s нет обычного облика (dry) — игра возьмёт «%s»" % [nm.call(lid), Words.state(str(sts[0]))], {"places": [lid]})
	# коды мест общие для всех регионов игры: наше место не должно совпасть с местом другого региона
	if doc.game != "":
		for lid6: String in doc.locations:
			var own := str(doc.locations[lid6].get("region", doc.region)) == doc.region
			var other := GameIO.game_location_region(doc.game, lid6)
			if own and other != "" and other != doc.region:
				row.call("error", "id_taken", "Код места «%s» уже занят в игре (%s) — экспорт перезаписал бы чужое место. Переименуйте: «Подробно» → «Код места»." % [lid6, other.trim_prefix("shop:")], {"places": [lid6]})
	for lid2: String in doc.locations:
		if str(doc.locations[lid2].get("region", doc.region)) == doc.region and not places.has(lid2):
			row.call("error", "no_point", "%s есть в списке мест, но не стоит на карте" % nm.call(lid2), {"places": [lid2]})
	for lid3: String in m.get("variants", {}):
		for v: String in m.variants[lid3]:
			if not Array(places.get(lid3, {}).get("states", [])).has(v):
				row.call("error", "variant", "Вариант «%s» у %s не в списке обликов" % [Words.state(v), nm.call(lid3)], {"places": [lid3]})

	# --- тропы
	var seen_pairs := {}
	for e: Array in doc.paths():
		if e.size() != 2:
			continue
		for lid4: String in e:
			if not places.has(lid4):
				row.call("error", "path_unknown", "Тропа ведёт в несуществующее место %s" % lid4, {"path": e})
		var key := "|".join([str(e[0]), str(e[1])] if str(e[0]) < str(e[1]) else [str(e[1]), str(e[0])])
		if seen_pairs.has(key):
			row.call("warn", "path_dup", "Тропа %s — %s проведена дважды" % [nm.call(str(e[0])), nm.call(str(e[1]))], {"path": e})
		seen_pairs[key] = true
		if places.has(str(e[0])) and places.has(str(e[1])):
			var a := _w(doc, doc.at(str(e[0])))
			var b := _w(doc, doc.at(str(e[1])))
			if a.distance_to(b) > LONG_PATH:
				row.call("warn", "path_long", "Очень длинная тропа %s — %s: может, соединили не то место?" % [nm.call(str(e[0])), nm.call(str(e[1]))], {"path": e})

	# --- связность (без тупиков), как dry_spine_errors в игре
	_spine(doc, row, nm)

	# --- появляющиеся места и площадки
	var sk: Array = doc.sockets()
	var groups: Dictionary = m.get("emerge_groups", {})
	for lid5: String in doc.locations:
		var l: Dictionary = doc.locations[lid5]
		if not bool(l.get("emerge", false)) or str(l.get("region", doc.region)) != doc.region:
			continue
		if sk.is_empty():
			row.call("error", "no_sockets", "Появляющемуся месту %s негде встать — поставьте площадки" % nm.call(lid5), {"places": [lid5]})
		var g := str(l.get("socket_group", ""))
		if g != "" and not groups.has(g):
			row.call("error", "no_group", "У %s группа площадок «%s», которой нет на карте" % [nm.call(lid5), g], {"places": [lid5]})
	for g2: String in groups:
		for i: Variant in Array(groups[g2].get("sockets", [])):
			if int(i) < 0 or int(i) >= sk.size():
				row.call("error", "socket_index", "Группа «%s» ссылается на площадку, которой нет" % g2, {"socket": int(i)})
	for i2: Variant in Array(m.get("ebb_sockets", [])):
		if int(i2) < 0 or int(i2) >= sk.size():
			row.call("error", "socket_index", "Площадки отлива ссылаются на площадку, которой нет", {"socket": int(i2)})

	# --- метки, названные в конфиге
	if src != null:
		for d: Dictionary in decal_names(m):
			if not src.exists(str(d.name)):
				row.call("error", "no_decal", "Нет картинки метки «%s» (%s)" % [d.name, d.where], d.get("extra", {}))

	# --- угрозы, зоны, подвижные угрозы: ссылки на места
	_refs(doc, row, nm)

	# --- высота места и карта высот (ФТ-25)
	if src != null and m.has("height"):
		_height_vs_map(doc, src, row, nm)

	# --- подсказки редактора
	# появляющиеся места стоят на площадках — их точка на карте не важна
	var ids := places.keys().filter(func(x: String) -> bool: return not doc.is_emerging(x))
	for i3 in ids.size():
		var a2: String = ids[i3]
		var ra := _rect(doc, a2)
		if ra.position.x < -0.001 or ra.position.y < -0.001 or ra.end.x > 1.001 or ra.end.y > 1.0 / doc.base_aspect() + 0.001:
			row.call("warn", "edge", "%s выходит за край основы" % nm.call(a2), {"places": [a2]})
		for j in range(i3 + 1, ids.size()):
			var b2: String = ids[j]
			var rb := _rect(doc, b2)
			var inter := ra.intersection(rb)
			if inter.has_area():
				var small := minf(ra.get_area(), rb.get_area())
				if small > 0.0 and inter.get_area() / small > OVERLAP:
					row.call("warn", "overlap", "%s и %s сильно налезают друг на друга" % [nm.call(a2), nm.call(b2)], {"places": [a2, b2]})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.level == "error" and y.level != "error")
	return out


static func errors(rows: Array) -> Array:
	return rows.filter(func(r: Dictionary) -> bool: return r.level == "error")


## Точка в «единицах ширины основы» (по вертикали — с учётом пропорций).
static func _w(doc: MapDoc, p: Vector2) -> Vector2:
	return Vector2(p.x, p.y / doc.base_aspect())


static func _rect(doc: MapDoc, lid: String) -> Rect2:
	var c := _w(doc, doc.at(lid))
	var s := doc.size_of(lid)
	return Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s))


static func _spine(doc: MapDoc, row: Callable, nm: Callable) -> void:
	var m: Dictionary = doc.map
	var places: Dictionary = doc.places()
	var all: Array = []
	var dry: Array = []
	for lid: String in places:
		if doc.shops.has(lid):
			all.append(lid)
			dry.append(lid)
		elif doc.locations.has(lid) and not doc.is_emerging(lid):
			all.append(lid)
			if doc.height_of(lid) == "high":
				dry.append(lid)
	var sets: Array = m.get("path_sets", {}).get("sets", [])
	var union: Array = []
	for st: Array in sets:
		union.append_array(st)
	var water: Array = m.get("water_paths", [])
	var under_rubble: Array = []
	for rid: String in m.get("rubble", {}):
		under_rubble.append(m.rubble[rid].get("pair", []))
	var fragile: Array = Dictionary(m.get("fragile", {})).keys()
	var paths: Array = doc.paths()
	# места без единой тропы — сразу видно
	var linked := {}
	for e: Array in paths + union + water:
		for x: String in e:
			linked[x] = true
	for lid2: String in all:
		if not linked.has(lid2):
			row.call("error", "isolated", "К %s не ведёт ни одна тропа" % nm.call(lid2), {"places": [lid2]})
	var bad := MapGraph.unreachable(all, paths + union + water)
	if not bad.is_empty() and bad.size() < all.size():
		_report(doc, row, nm, bad, "Не всё связано тропами: %s не дойти от %s", all[0], "spine_all")
	var land: Array = all.filter(func(lid: String) -> bool:
		for e: Array in paths + union:
			if e.has(lid):
				return true
		return false)
	var solid: Array = land.filter(func(lid: String) -> bool: return not fragile.has(lid))
	for i in maxi(1, sets.size()):
		var edges: Array = paths + (Array(sets[i]) if not sets.is_empty() else [])
		var what := " (сеть троп бури %d)" % (i + 1) if not sets.is_empty() else ""
		var bad2 := MapGraph.unreachable(land, edges)
		if not bad2.is_empty():
			_report(doc, row, nm, bad2, "Сухие места не связаны" + what + ": %s не дойти от %s", land[0], "spine_land")
		if not fragile.is_empty() or not under_rubble.is_empty():
			var bad3 := MapGraph.unreachable(solid, edges, under_rubble)
			if not bad3.is_empty():
				_report(doc, row, nm, bad3, "Без хрупкого моста и под завалами" + what + ": %s не дойти от %s", solid[0], "spine_solid")
	if not m.has("height"):
		return
	var bad4 := MapGraph.unreachable(dry, paths)
	if not bad4.is_empty():
		_report(doc, row, nm, bad4, "Сухой хребет: в прилив %s не дойти от %s только по высотам и лавкам", dry[0], "spine_dry")
	for lid3: String in dry:
		var deg := 0
		for e2: Array in paths:
			if str(e2[0]) == lid3 or str(e2[1]) == lid3:
				deg += 1
		if deg < 2 and not doc.shops.has(lid3):
			row.call("error", "spine_deg", "Тупик: у высоты %s одна тропа — нужно не меньше двух" % nm.call(lid3), {"places": [lid3]})


static func _report(doc: MapDoc, row: Callable, nm: Callable, bad: Array, fmt: String, first: String, code: String) -> void:
	var names := bad.slice(0, 4).map(func(x: String) -> String: return nm.call(x))
	var more := "" if bad.size() <= 4 else " и ещё %d" % (bad.size() - 4)
	row.call("error", code, fmt % [", ".join(names) + more, nm.call(first)], {"places": bad})


## Все имена меток из конфига (как _validate_marks в игре) + картинки точек угроз.
static func decal_names(m: Dictionary) -> Array:
	var out: Array = []
	var add := func(n: Variant, where: String, extra: Dictionary = {}) -> void:
		if str(n) != "":
			out.append({"name": str(n), "where": where, "extra": extra})
	for key: String in ["place_decals", "path_decals"]:
		for d: Dictionary in m.get(key, []):
			var ex := {"places": [str(d.place)]} if d.has("place") else ({"path": d.path} if d.has("path") else {})
			add.call(d.get("decal", ""), "метка у места" if key == "place_decals" else "полоса на тропе", ex)
	for k: String in Dictionary(m.get("mod_decals", {})):
		add.call(m.mod_decals[k], "модификатор «%s»" % k)
	for k2: String in Dictionary(m.get("traces", {})):
		if k2 != "graves":
			add.call(m.traces[k2], "след «%s»" % k2)
	for key2: String in ["haze", "edge_glow", "storm_band"]:
		var d2: Dictionary = m.get(key2, {})
		if not d2.is_empty():
			add.call(d2.get("tex", d2.get("decal", "")), "погода")
	for zid: String in Dictionary(m.get("zones", {})):
		var z: Dictionary = m.zones[zid]
		for key3: String in ["decal", "mark", "spread"]:
			if z.has(key3):
				add.call(z[key3], "зона «%s»" % z.get("name", zid))
	for mid: String in Dictionary(m.get("movers", {})):
		var mv: Dictionary = m.movers[mid]
		for key4: String in ["token", "tracks"]:
			if mv.has(key4):
				add.call(mv[key4], "угроза «%s»" % mv.get("name", mid))
		for t: Variant in Array(mv.get("nest_tex", [])):
			add.call(t, "логово «%s»" % mv.get("name", mid))
	for v: Variant in Dictionary(m.get("rubble_tex", {})).values():
		add.call(v, "завал")
	return out


## Ссылки на места в угрозах, зонах, подвижных угрозах, местности (то, что игра проверяет или на чём упадёт).
static func _refs(doc: MapDoc, row: Callable, nm: Callable) -> void:
	var m: Dictionary = doc.map
	var places: Dictionary = doc.places()
	var need := func(lid: Variant, what: String) -> void:
		if str(lid) != "" and str(lid) != "camp" and str(lid) != "noise" and not places.has(str(lid)):
			row.call("error", "ref", "%s ссылается на место %s, которого нет на карте" % [what, lid])
	for zid: String in Dictionary(m.get("zones", {})):
		need.call(m.zones[zid].get("center", ""), "Зона «%s»" % m.zones[zid].get("name", zid))
	for mid: String in Dictionary(m.get("movers", {})):
		var mv: Dictionary = m.movers[mid]
		need.call(mv.get("start", ""), "Угроза «%s»" % mv.get("name", mid))
		if not str(mv.get("target", "")) in ["camp", "noise", "patrol"]:   # цель — лагерь, шум боя или патруль
			need.call(mv.get("target", ""), "Угроза «%s»" % mv.get("name", mid))
		for p: Variant in Array(mv.get("patrol", [])):
			need.call(p, "Патруль «%s»" % mv.get("name", mid))
	for rid: String in Dictionary(m.get("rubble", {})):
		for p2: Variant in Array(m.rubble[rid].get("pair", [])):
			need.call(p2, "Завал %s" % rid)
	for lid: String in Dictionary(m.get("fragile", {})):
		need.call(lid, "Хрупкий проход")
	for rk: Dictionary in m.get("risky", []):
		for p3: Variant in Array(rk.get("pair", [])):
			need.call(p3, "Опасный спуск")
	for e: Array in m.get("water_paths", []):
		for p4: Variant in e:
			need.call(p4, "Водная тропа")
	for st: Array in m.get("path_sets", {}).get("sets", []):
		for e2: Array in st:
			for p5: Variant in e2:
				need.call(p5, "Тропа бури")
	for lid2: String in Dictionary(m.get("phase_states", {})):
		need.call(lid2, "Облик по фазе")
	for es: Dictionary in m.get("event_states", []):
		need.call(es.get("place", ""), "Облик события")
	var t: Dictionary = m.get("threat", {})
	if not t.is_empty():
		if str(t.get("kind", "breach")) == "breach":
			need.call(t.get("target", ""), "Цель роя")
		if t.has("center"):
			need.call(t.center, "Центр угрозы")
		for pid: String in Dictionary(t.get("points", {})):
			var p6: Dictionary = t.points[pid]
			for key: String in ["near", "enter"]:
				if p6.has(key) and not doc.locations.has(str(p6[key])) and not places.has(str(p6[key])):
					row.call("error", "ref", "Точка угрозы %s: нет места %s" % [pid, p6[key]])
			if Array(p6.get("at", [])).size() != 2:
				row.call("error", "ref", "Точка угрозы %s без положения на карте" % pid)
		for key2: String in ["swarm", "fire"]:
			for lid3: String in Dictionary(t.get(key2, {})):
				need.call(lid3, "Угроза (%s)" % key2)


## Высота места в locations.json и вода на картинке совпадают: низина ниже прилива, высота — выше.
static func _height_vs_map(doc: MapDoc, src: TexSource, row: Callable, nm: Callable) -> void:
	var img := src.image(str(doc.map.height).get_basename())
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var flood := float(doc.map.get("levels", {}).get("flood", 115))
	for lid: String in doc.places():
		if doc.is_emerging(lid) or doc.is_shop(lid):
			continue
		var at := doc.at(lid)
		var px := Vector2i(clampi(int(at.x * img.get_width()), 0, img.get_width() - 1), clampi(int(at.y * img.get_height()), 0, img.get_height() - 1))
		var h := img.get_pixelv(px).r * 255.0
		match doc.height_of(lid):
			"low":
				if h > flood + 3.0:
					row.call("warn", "height_map", "%s — низина, но на карте высот стоит выше прилива: вода её не зальёт" % nm.call(lid), {"places": [lid]})
			"high":
				if h < flood:
					row.call("warn", "height_map", "%s — высота, но на карте высот она под водой в прилив" % nm.call(lid), {"places": [lid]})
