class_name GameIO
extends RefCounted
## Связь с папкой игры SunLess: открыть карту региона (ФТ-09), экспорт (ФТ-42…46), резервные копии (ФТ-11).

## Размеры текстур в игре (как tools/import_map_kit.py, ФТ-43).
const SIZES := {"base": Vector2i(3072, 1536), "place": Vector2i(512, 512), "decal": Vector2i(256, 256), "big": Vector2i(512, 512),
	"strip": Vector2i(512, 128), "tile": Vector2i(512, 512), "height": Vector2i(1536, 768), "tech": Vector2i(1024, 512),
	"token": Vector2i(256, 256)}
const QUALITY := {"base": 0.82}
const BACKUPS := "user://backups"


static var _names: Dictionary = {}


## Русское название места из locations.json игры (места из комплектов игры называются так же) — "" если нет.
static func game_place_name(game: String, lid: String) -> String:
	if game == "":
		return ""
	if not _names.has(game):
		var m := {}
		var locs: Variant = JsonX.read_file(game + "/data/locations.json")
		if locs is Array:
			for l: Dictionary in locs:
				m[str(l.get("id", ""))] = str(l.get("name", ""))
		var shops: Variant = JsonX.read_file(game + "/data/shops.json")
		if shops is Array:
			for s: Dictionary in shops:
				m[str(s.get("id", ""))] = str(s.get("name", ""))
		_names[game] = m
	return str(_names[game].get(lid, ""))


static func is_game_dir(dir: String) -> bool:
	return FileAccess.file_exists(dir + "/project.godot") and DirAccess.dir_exists_absolute(dir + "/data")


## Регионы игры: {регион: {map: есть ли карта-план, chapter, places: число мест}}.
static func regions(game: String) -> Dictionary:
	var out := {}
	var dir := game + "/data/maps"
	if DirAccess.dir_exists_absolute(dir):
		for f: String in DirAccess.get_files_at(dir):
			if f.get_extension() != "json":
				continue
			var m: Variant = JsonX.read_file(dir + "/" + f)
			if m is Dictionary and m.has("region"):
				out[str(m.region)] = {"map": true, "file": f, "chapter": "", "places": Dictionary(m.get("places", {})).size()}
	var locs: Variant = JsonX.read_file(game + "/data/locations.json")
	if locs is Array:
		for l: Dictionary in locs:
			var r := str(l.get("region", ""))
			if r == "":
				continue
			if not out.has(r):
				out[r] = {"map": false, "file": "", "chapter": "", "places": 0}
			if str(out[r].chapter) == "":
				out[r]["chapter"] = str(l.get("chapter", ""))
	return out


## Открыть карту региона из игры. Картинки берутся из пака «Из игры» (папка art/map/<регион>/ в библиотеке),
## поэтому экспорт без правок ничего в картинках не меняет.
static func open_region(game: String, region: String, lib: PackLibrary) -> MapDoc:
	var info: Dictionary = regions(game).get(region, {})
	var doc: MapDoc
	if bool(info.get("map", false)):
		var m: Variant = JsonX.read_file(game + "/data/maps/" + str(info.file))
		doc = MapDoc.new()
		doc.map = m
		doc.region = region
	else:
		doc = MapDoc.new_map(region)
	doc.game = game
	doc.chapter = str(info.get("chapter", ""))
	var locs: Variant = JsonX.read_file(game + "/data/locations.json")
	if locs is Array:
		for l: Dictionary in locs:
			if str(l.get("region", "")) == region:
				doc.locations[str(l.id)] = l
		# место другого региона на этой карте (у Академии — «Окраины» Города): запись тоже нужна проверкам
		for l2: Dictionary in locs:
			if doc.places().has(str(l2.get("id", ""))) and not doc.locations.has(str(l2.id)):
				doc.locations[str(l2.id)] = l2
	var shops: Variant = JsonX.read_file(game + "/data/shops.json")
	if shops is Array:
		for s: Dictionary in shops:
			if doc.places().has(str(s.get("id", ""))):
				doc.shops[str(s.id)] = s
	var art := game + "/art/map/" + region
	if lib != null and DirAccess.dir_exists_absolute(art):
		var p := lib.add(art, "game_" + region, "Из игры: " + region)
		_link_all(doc, p)
	_read_aspect(doc, lib)
	doc.editor["opened_from_game"] = true
	return doc


## Все текстуры карты — из пака «Из игры» (то, что там есть).
static func _link_all(doc: MapDoc, p: TexPack) -> void:
	for nm: String in needed(doc):
		var stem := str(nm).get_basename() if str(nm).get_extension() in ["png", "webp"] else str(nm)
		if p.textures.has(stem):
			doc.set_source(stem, p.id, stem)


static func _read_aspect(doc: MapDoc, lib: PackLibrary) -> void:
	var src := TexSource.new(doc, lib)
	var r := src.resolve("base")
	if r.from != "none":
		var p: TexPack = lib.get_pack(str(r.pack)) if r.from == "pack" else null
		if p != null:
			var e: Dictionary = p.textures[str(r.tex)]
			if int(e.get("h", 0)) > 0:
				doc.editor["aspect"] = float(e.w) / float(e.h)


## Имена текстур, которые нужны карте в игре: {имя: вид}. Имя без расширения, кроме карты высот.
static func needed(doc: MapDoc) -> Dictionary:
	var m: Dictionary = doc.map
	var out := {}
	out[str(m.get("base", "base.webp")).get_basename()] = "base"
	if m.has("height"):
		out[str(m.height).get_basename()] = "height"
		out[str(m.get("water", "water_tile.webp")).get_basename()] = "tile"
	out[str(m.get("fog", "fog_tile.webp")).get_basename()] = "tile"
	for lid: String in doc.places():
		for st: String in doc.states(lid):
			out["%s_%s" % [lid, st]] = "place"
	for d: Dictionary in MapChecks.decal_names(m):
		if not out.has(str(d.name)):
			out[str(d.name)] = "decal"
	for v: Variant in Dictionary(m.get("point_tex", {})).values():
		out[str(v)] = "place"
	var dm: Dictionary = m.get("decals", {})
	for dk: String in dm:
		if dk == "point":
			continue   # начало имён картинок точки угрозы (breach_signal, breach_open…) — не отдельная картинка
		var lst: Variant = dm[dk]
		for v2: Variant in (lst if lst is Array else [lst]):
			if v2 is String:
				out[str(v2)] = "decal"
	return out


# --- экспорт -------------------------------------------------------------------------------------

## План экспорта (показать перед записью, ФТ-44): [{file, rel, kind, status: new|changed|same|missing, data}].
## data — байты для записи (у same/missing пусто). Тяжёлая часть — перекодирование картинок.
static func plan(doc: MapDoc, lib: PackLibrary) -> Dictionary:
	var items: Array = []
	var errors: Array = []
	if not is_game_dir(doc.game):
		return {"items": [], "errors": ["Не выбрана папка игры (нужна папка с project.godot и data/)"]}
	# карта
	var map_rel := "data/maps/%s.json" % doc.region
	var map_text := JsonX.stringify(doc.map_for_game()) + "\n"
	items.append(_text_item(doc.game, map_rel, map_text, "json"))
	# места региона в locations.json
	var locs_rel := "data/locations.json"
	var locs: Variant = JsonX.read_file(doc.game + "/" + locs_rel)
	if not locs is Array:
		errors.append("Не прочитать data/locations.json: " + JsonX.last_error)
	else:
		var merged := merge_locations(locs, doc)
		items.append(_text_item(doc.game, locs_rel, JsonX.stringify(merged) + "\n", "json"))
	# лавки — только если в проекте менялись их записи
	if not doc.shops.is_empty():
		var shops: Variant = JsonX.read_file(doc.game + "/data/shops.json")
		if shops is Array:
			var changed := false
			for i in shops.size():
				var sid := str(shops[i].get("id", ""))
				if doc.shops.has(sid) and JsonX.stringify(shops[i]) != JsonX.stringify(doc.shops[sid]):
					shops[i] = doc.shops[sid]
					changed = true
			if changed:
				items.append(_text_item(doc.game, "data/shops.json", JsonX.stringify(shops) + "\n", "json"))
	# картинки
	var src := TexSource.new(doc, lib)
	var art_rel := "art/map/%s/" % doc.region
	var need := needed(doc)
	for nm: String in need:
		var kind: String = need[nm]
		var ext := "png" if kind in ["height", "tech"] else "webp"
		if nm == str(doc.map.get("height", "")).get_basename():
			ext = str(doc.map.get("height", "height.png")).get_extension()
		var rel := art_rel + nm + "." + ext
		var dest := doc.game + "/" + rel
		var r := src.resolve(nm)
		if r.from == "none":
			items.append({"file": dest, "rel": rel, "kind": kind, "status": "missing", "name": nm})
			continue
		if r.from == "game" or str(r.path) == dest:
			items.append({"file": dest, "rel": rel, "kind": kind, "status": "same", "name": nm})
			continue
		var p: TexPack = lib.get_pack(str(r.pack))
		var e: Dictionary = p.textures[str(r.tex)]
		if kind == "decal":
			kind = str(e.kind) if str(e.kind) in ["decal", "strip", "tile", "tech", "token"] else "decal"
			# как import_map_kit.py: большие метки (свечение зоны) — 512, обычные — 256; картинки без decal_ — как места
			if kind == "decal":
				if not nm.begins_with("decal_") and not nm.begins_with("ally_") and not nm.begins_with("party_"):
					kind = "place"
				elif int(e.get("w", 0)) >= 1024:
					kind = "big"
		var data := convert_image(p.image(str(r.tex)), kind, ext)
		if data.is_empty():
			errors.append("Не раскодировать картинку %s из пака %s" % [r.tex, p.name])
			continue
		var it := {"file": dest, "rel": rel, "kind": kind, "name": nm, "data": data}
		if not FileAccess.file_exists(dest):
			it["status"] = "new"
		elif FileAccess.get_file_as_bytes(dest) == data:
			it["status"] = "same"
			it.erase("data")
		else:
			it["status"] = "changed"
		items.append(it)
	return {"items": items, "errors": errors}


static func _text_item(game: String, rel: String, text: String, kind: String) -> Dictionary:
	var dest := game + "/" + rel
	var data := text.to_utf8_buffer()
	var it := {"file": dest, "rel": rel, "kind": kind, "name": rel.get_file(), "data": data}
	if not FileAccess.file_exists(dest):
		it["status"] = "new"
	elif FileAccess.get_file_as_bytes(dest) == data:
		it["status"] = "same"
		it.erase("data")
	else:
		it["status"] = "changed"
	return it


## Записи мест региона заменяются на месте (по id), удалённые — убираются, новые — после последней записи
## региона. Чужие записи не трогаются (ФТ-42).
static func merge_locations(locs: Array, doc: MapDoc) -> Array:
	var out: Array = []
	var placed := {}
	var last_idx := -1
	var anchor := -1
	for l: Dictionary in locs:
		var lid := str(l.get("id", ""))
		if str(l.get("region", "")) == doc.region or doc.locations.has(lid):
			if doc.locations.has(lid):
				out.append(doc.locations[lid])
				placed[lid] = true
				last_idx = out.size() - 1
			elif anchor < 0:
				anchor = out.size()
			continue
		out.append(l)
	if last_idx < 0 and anchor >= 0:
		last_idx = anchor - 1
	var fresh: Array = []
	for lid2: String in doc.locations:
		if not placed.has(lid2):
			fresh.append(doc.locations[lid2])
	if last_idx < 0 and anchor < 0:
		out.append_array(fresh)
	else:
		for i in fresh.size():
			out.insert(last_idx + 1 + i, fresh[i])
	return out


## Картинка → байты файла игры нужного размера.
static func convert_image(img: Image, kind: String, ext: String) -> PackedByteArray:
	if img == null:
		return PackedByteArray()
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	var sz: Vector2i = SIZES.get(kind, SIZES.place)
	if kind == "height":
		img.convert(Image.FORMAT_RGBA8)
		img.resize(sz.x, sz.y, Image.INTERPOLATE_CUBIC)
		img.convert(Image.FORMAT_L8)
		return img.save_png_to_buffer()
	if kind == "tech":
		img.convert(Image.FORMAT_RGB8)
		img.resize(sz.x, sz.y, Image.INTERPOLATE_NEAREST)
		return img.save_png_to_buffer()
	if img.get_size() != sz:
		if img.detect_alpha() != Image.ALPHA_NONE:
			img.convert(Image.FORMAT_RGBA8)
		img.resize(sz.x, sz.y, Image.INTERPOLATE_LANCZOS)
	if ext == "png":
		return img.save_png_to_buffer()
	return img.save_webp_to_buffer(true, float(QUALITY.get(kind, 0.85)))


## Записать план: резервные копии прежних файлов, запись через временный файл. {written: [], backup, errors: []}
static func write(doc: MapDoc, plan_items: Array) -> Dictionary:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var bdir := ProjectSettings.globalize_path("%s/%s/%s" % [BACKUPS, doc.region, stamp])
	var written: Array = []
	var errors: Array = []
	for it: Dictionary in plan_items:
		if not str(it.status) in ["new", "changed"]:
			continue
		if it.status == "changed":
			var bpath := bdir + "/" + str(it.rel) + ".bak"
			DirAccess.make_dir_recursive_absolute(bpath.get_base_dir())
			var e0 := DirAccess.copy_absolute(str(it.file), bpath)
			if e0 != OK:
				errors.append("Не сделать резервную копию %s — файл не записан" % it.rel)
				continue
		var err := JsonX.write_bytes(str(it.file), it.data)
		if err != "":
			errors.append(err)
		else:
			written.append(str(it.rel))
	return {"written": written, "backup": bdir if DirAccess.dir_exists_absolute(bdir) else "", "errors": errors}


## Картинки в art/map/<регион>/, которые карта больше не использует (ФТ-45).
static func unused_files(doc: MapDoc) -> Array:
	var dir := "%s/art/map/%s" % [doc.game, doc.region]
	if not DirAccess.dir_exists_absolute(dir):
		return []
	var need := needed(doc)
	var out: Array = []
	for f: String in DirAccess.get_files_at(dir):
		var ext := f.get_extension().to_lower()
		if not ext in ["webp", "png"]:
			continue
		if not need.has(f.get_basename()):
			out.append(f)
	return out


## Обновить импорт картинок в игре (иначе игра не увидит новые файлы): Godot той же версии, без окна.
static func reimport_args(game: String) -> PackedStringArray:
	return PackedStringArray(["--headless", "--path", game, "--import"])


## Проверка игрой: тесты данных игры (content_validator) и «без тупиков».
static func game_test_args(game: String, only: String = "test_content") -> PackedStringArray:
	return PackedStringArray(["--headless", "--path", game, "-s", "res://tests/run_tests.gd", "--", "--only=" + only])
