extends SceneTree
## Командная строка редактора — бэкенд агентского интерфейса (agent-harness, методика CLI-Anything).
## Все правила (правки, проверки, маршрут, экспорт, снимок) — те же классы, что в окне редактора.
##
##   godot --headless --path <редактор> -s res://cli/cli.gd -- <команда> [--ключ значение …]
##   снимок (render) — без --headless: холст рисует настоящий рендер Godot.
##
## Ответ — одна строка «@@SUNLESS_JSON@@{…}» в stdout: {ok: true, …} или {ok: false, error}.

const MARK := "@@SUNLESS_JSON@@"

var args: Dictionary = {}
var pos: Array = []
var lib: PackLibrary


func _init() -> void:
	_parse(OS.get_cmdline_user_args())
	lib = PackLibrary.new()
	lib.path_file = str(args.get("library", OS.get_environment("SUNLESS_MAP_LIBRARY")))
	if lib.path_file == "":
		lib.path_file = PackLibrary.FILE
	lib.load_file()
	_run.call_deferred()


func _parse(a: PackedStringArray) -> void:
	var i := 0
	while i < a.size():
		var s: String = a[i]
		if s.begins_with("--"):
			var k := s.substr(2)
			if "=" in k:
				args[k.get_slice("=", 0)] = k.substr(k.find("=") + 1)
			elif i + 1 < a.size() and not a[i + 1].begins_with("--"):
				args[k] = a[i + 1]
				i += 1
			else:
				args[k] = true
		else:
			pos.append(s)
		i += 1


func _out(d: Dictionary, code: int = 0) -> void:
	print(MARK + JSON.stringify(d))
	quit(code)


func _fail(msg: String) -> void:
	_out({"ok": false, "error": msg}, 1)


func _run() -> void:
	var cmd: String = pos[0] if not pos.is_empty() else "help"
	match cmd:
		"help":
			_out({"ok": true, "commands": ["new", "open-game", "regions", "info", "apply", "check", "route", "step", "tide",
				"export", "unused", "render", "game-snapshot", "pack-list", "pack-add", "pack-remove", "pack-check", "pack-textures", "pack-manifest"]})
		"regions":
			var g := _game()
			if g == "":
				return
			_out({"ok": true, "regions": GameIO.regions(g)})
		"new":
			_new()
		"open-game":
			_open_game()
		"info":
			var d := _doc()
			if d != null:
				_out({"ok": true, "info": _info(d)})
		"apply":
			_apply()
		"check":
			var d2 := _doc()
			if d2 != null:
				var rows := MapChecks.run(d2, TexSource.new(d2, lib))
				_out({"ok": true, "errors": MapChecks.errors(rows).size(), "warnings": rows.size() - MapChecks.errors(rows).size(), "rows": rows})
		"route":
			_route()
		"step":
			_step()
		"tide":
			_tide()
		"export":
			_export()
		"game-snapshot":
			var dg := _doc()
			if dg == null:
				return
			var outp := str(args.get("out", ""))
			if outp == "":
				_fail("нужен --out <файл.png>")
				return
			var r := GamePreview.run(dg, lib, str(args.get("camp", "")), outp)
			_out(r, 0 if bool(r.get("ok", false)) else 1)
		"unused":
			var d3 := _doc()
			if d3 != null:
				_out({"ok": true, "unused": GameIO.unused_files(d3)})
		"render":
			await _render()
		"pack-list":
			var out: Array = []
			for e: Dictionary in lib.entries:
				var p: TexPack = lib.get_pack(str(e.get("id", "")))
				if p != null:
					out.append({"id": p.id, "name": p.name, "path": p.root, "enabled": bool(e.get("enabled", true)), "version": p.version,
						"textures": p.textures.size(), "places": p.places().size(), "kinds": p.count_by_kind(), "manifest": p.has_manifest})
			_out({"ok": true, "packs": out})
		"pack-add":
			if pos.size() < 2:
				_fail("нужен путь к папке или .zip")
				return
			var p2 := lib.add(str(pos[1]), str(args.get("id", "")), str(args.get("name", "")))
			if p2 == null or not p2.errors.is_empty():
				_fail("пак не подключён: %s" % ("" if p2 == null else ", ".join(p2.errors)))
				return
			_out({"ok": true, "id": p2.id, "name": p2.name, "textures": p2.textures.size(), "places": p2.places().keys()})
		"pack-remove":
			lib.remove(str(pos[1]) if pos.size() > 1 else "")
			_out({"ok": true})
		"pack-check":
			var rows2: Array = []
			for p3: TexPack in ([lib.get_pack(str(pos[1]))] if pos.size() > 1 else lib.enabled_packs()):
				if p3 != null:
					rows2.append_array(PackCheck.check(p3, args.has("deep")))
			rows2.append_array(PackCheck.duplicates(lib.enabled_packs()))
			_out({"ok": true, "rows": rows2})
		"pack-textures":
			_pack_textures()
		"pack-manifest":
			var p4: TexPack = lib.get_pack(str(pos[1]) if pos.size() > 1 else "")
			if p4 == null:
				_fail("нет такого пака")
				return
			if args.has("save"):
				var err := p4.save_manifest()
				if err != "":
					_fail(err)
					return
			_out({"ok": true, "manifest": p4.manifest_to_save()})
		_:
			_fail("неизвестная команда %s" % cmd)


# --- проект --------------------------------------------------------------------------------------

func _game() -> String:
	var g := str(args.get("game", OS.get_environment("SUNLESS_GAME")))
	if g == "" or g == "true":
		var sib := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir() + "/SunLess"
		g = sib if GameIO.is_game_dir(sib) else ""
	if not GameIO.is_game_dir(g):
		_fail("не найдена папка игры (--game или SUNLESS_GAME): %s" % g)
		return ""
	return GameIO.norm(g)


func _doc() -> MapDoc:
	var p := str(args.get("project", ""))
	if p == "" or not FileAccess.file_exists(p):
		_fail("нет файла проекта (--project): %s" % p)
		return null
	var d := MapDoc.load_project(p)
	if d == null:
		_fail("проект не читается: " + JsonX.last_error)
		return null
	for pk: Dictionary in d.packs:
		if lib.get_pack(str(pk.get("id", ""))) == null and str(pk.get("path", "")) != "":
			var path := str(pk.path)
			if DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(path):
				lib.add(path, str(pk.id))
	if args.has("game") and str(args.game) != "true":
		d.game = GameIO.norm(str(args.game))
	return d


func _save(d: MapDoc) -> bool:
	var used := {}
	for k: String in d.textures:
		used[str(d.source(k).get("pack", ""))] = true
	var packs: Array = []
	for pid: String in used:
		var p: TexPack = lib.get_pack(pid)
		if p != null:
			packs.append({"id": pid, "version": p.version, "path": p.root})
	d.packs = packs
	var err := d.save()
	if err != "":
		_fail(err)
		return false
	return true


func _info(d: MapDoc) -> Dictionary:
	var src := TexSource.new(d, lib)
	var places := {}
	for lid: String in d.places():
		var missing: Array = []
		for st: String in d.states(lid):
			if not src.exists("%s_%s" % [lid, st]):
				missing.append(st)
		places[lid] = {"name": d.display_name(lid), "at": d.place(lid).get("at"), "size": d.size_of(lid), "states": d.states(lid),
			"height": d.height_of(lid), "shop": d.is_shop(lid), "emerge": d.is_emerging(lid), "paths": d.path_places(lid), "missing_states": missing,
			"camp": d.loc(lid).get("camp", {})}
	return {"region": d.region, "chapter": d.chapter, "game": d.game, "project": d.path, "base": src.resolve("base"),
		"has_water": d.map.has("height"), "places": places, "paths": d.paths(), "sockets": d.sockets(),
		"water_paths": d.map.get("water_paths", []), "params": {"view_top": d.map.get("view_top"), "foot": d.map.get("foot"), "zoom": d.map.get("zoom", 1.15)},
		"unknown_fields": d.unknown_fields().keys(), "packs": d.packs}


func _new() -> void:
	var out := str(args.get("out", args.get("project", "")))
	if out == "":
		_fail("нужен --out <файл.mapproj>")
		return
	var region := TexPack.slug(str(args.get("region", "new_region")))
	var d := MapDoc.new_map(region)
	d.chapter = str(args.get("chapter", region))
	if args.has("game"):
		d.game = GameIO.norm(str(args.game))
	else:
		var sib := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir() + "/SunLess"
		d.game = sib if GameIO.is_game_dir(sib) else ""
	d.path = out
	if _save(d):
		_out({"ok": true, "project": out, "region": region})


func _open_game() -> void:
	var g := _game()
	if g == "":
		return
	var region := str(args.get("region", pos[1] if pos.size() > 1 else ""))
	var out := str(args.get("out", ""))
	if region == "" or out == "":
		_fail("нужны --region и --out")
		return
	var d := GameIO.open_region(g, region, lib)
	d.path = out
	if _save(d):
		_out({"ok": true, "project": out, "places": d.places().size(), "paths": d.paths().size()})


# --- правки пакетом ------------------------------------------------------------------------------

## apply --project P --ops '<JSON-массив>' | --ops-file F: каждая операция — те же функции MapDoc, что в окне.
func _apply() -> void:
	var d := _doc()
	if d == null:
		return
	var raw := str(args.get("ops", ""))
	if args.has("ops-file"):
		raw = FileAccess.get_file_as_string(str(args["ops-file"]))
	var ops: Variant = JsonX.parse(raw)
	if ops is Dictionary:
		ops = [ops]
	if not ops is Array:
		_fail("ops — JSON-массив операций: " + JsonX.last_error)
		return
	var results: Array = []
	for op: Dictionary in ops:
		var r := apply_op(d, op, lib)
		if r.has("error"):
			_fail("операция %s: %s" % [op.get("op", "?"), r.error])
			return
		results.append(r)
	if _save(d):
		_out({"ok": true, "applied": results.size(), "results": results})


static func _v2(a: Variant) -> Vector2:
	if a is Array and a.size() == 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2(-1, -1)


## Одна операция над проектом. {…} или {error}.
static func apply_op(d: MapDoc, op: Dictionary, lib: PackLibrary) -> Dictionary:
	var kind := str(op.get("op", ""))
	var lid := str(op.get("id", ""))
	var need_place := func() -> String: return "" if d.places().has(lid) else "нет места %s" % lid
	match kind:
		"place.add":
			var p: TexPack = lib.get_pack(str(op.get("pack", "")))
			if p == null:
				return {"error": "нет пака %s" % op.get("pack", "")}
			var srcp := str(op.get("place", ""))
			if srcp == "" and op.has("tex"):
				srcp = str(p.textures.get(str(op.tex), {}).get("place", ""))
			var sts: Array = Array(op.get("states", p.places().get(srcp, [])))
			if sts.is_empty():
				return {"error": "в паке %s нет места %s" % [p.id, srcp]}
			var at := _v2(op.get("at"))
			if at.x < 0:
				return {"error": "нужно at: [x, y] в долях основы"}
			var nid := d.free_id(str(op.get("id", srcp)))
			var title := str(op.get("name", p.place_name(srcp)))
			if title == "":
				title = GameIO.game_place_name(d.game, srcp)
			if title == "":
				title = srcp.replace("_", " ").capitalize()
			var sz := float(op.get("size", 0.12))
			d.add_place(nid, at, sz, sts, title)
			for st: String in sts:
				d.set_source("%s_%s" % [nid, st], p.id, "%s_%s" % [srcp, st])
			return {"id": nid, "name": title, "states": sts}
		"place.move":
			var e1: String = need_place.call()
			if e1 != "":
				return {"error": e1}
			d.move_place(lid, _v2(op.get("at")))
			return {"id": lid, "at": d.place(lid).at}
		"place.resize":
			var e2: String = need_place.call()
			if e2 != "":
				return {"error": e2}
			d.set_size(lid, float(op.get("size", 0.12)))
			return {"id": lid, "size": d.size_of(lid)}
		"place.remove":
			var e3: String = need_place.call()
			if e3 != "":
				return {"error": e3}
			d.remove_place(lid)
			return {"removed": lid}
		"place.rename":
			var err := d.rename_place(lid, str(op.get("to", "")))
			return {"error": err} if err != "" else {"id": TexPack.slug(str(op.to))}
		"place.set":
			var e4: String = need_place.call()
			if e4 != "":
				return {"error": e4}
			if not d.locations.has(lid) and not d.shops.has(lid):
				d.locations[lid] = d.new_location(lid, lid, d.at(lid))
			var rec: Dictionary = d.shops[lid] if d.shops.has(lid) else d.locations[lid]
			for key: String in ["name", "height", "text", "socket_group", "chapter"]:
				if op.has(key):
					if op[key] == null or str(op[key]) == "":
						rec.erase(key)
					else:
						rec[key] = op[key]
			if op.has("emerge"):
				if bool(op.emerge):
					rec["emerge"] = true
				else:
					rec.erase("emerge")
			if op.has("camp"):
				if op.camp == null or op.camp is bool and not op.camp:
					rec.erase("camp")
				else:
					var camp: Dictionary = rec.get("camp", {"rest": 10, "beds": 0, "danger": 0.2, "services": []})
					if op.camp is Dictionary:
						for ck: String in op.camp:
							camp[ck] = op.camp[ck]
					rec["camp"] = camp
			return {"id": lid, "record": rec}
		"state.add":
			var e5: String = need_place.call()
			if e5 != "":
				return {"error": e5}
			var p2: TexPack = lib.get_pack(str(op.get("pack", "")))
			if p2 == null or not p2.textures.has(str(op.get("tex", ""))):
				return {"error": "нет текстуры %s в паке %s" % [op.get("tex", ""), op.get("pack", "")]}
			var st2 := str(op.get("state", p2.textures[str(op.tex)].get("state", "")))
			d.add_state(lid, st2, p2.id, str(op.tex))
			return {"id": lid, "states": d.states(lid)}
		"state.remove":
			d.remove_state(lid, str(op.get("state", "")))
			return {"id": lid, "states": d.states(lid)}
		"state.default":
			d.make_default_state(lid, str(op.get("state", "")))
			return {"id": lid, "states": d.states(lid)}
		"path.add", "path.remove":
			var a := str(op.get("a", ""))
			var b := str(op.get("b", ""))
			if str(op.get("kind", "path")) == "water":
				if not d.map.has("water_paths"):
					d.map["water_paths"] = []
				var has_w: bool = Array(d.map.water_paths).any(func(e: Array) -> bool: return MapDoc.same_pair(e, a, b))
				if kind == "path.add" and not has_w:
					d.map.water_paths.append([a, b])
				elif kind == "path.remove":
					d.map["water_paths"] = Array(d.map.water_paths).filter(func(e: Array) -> bool: return not MapDoc.same_pair(e, a, b))
				return {"water_path": [a, b]}
			var has := d.has_path(a, b)
			if (kind == "path.add") != has:
				var err2 := d.toggle_path(a, b)
				if err2 != "":
					return {"error": err2}
			return {"path": [a, b], "exists": d.has_path(a, b)}
		"socket.add":
			return {"index": d.add_socket(_v2(op.get("at")))}
		"socket.move":
			d.move_socket(int(op.get("index", -1)), _v2(op.get("at")))
			return {"index": int(op.get("index", -1))}
		"socket.remove":
			d.remove_socket(int(op.get("index", -1)))
			return {"sockets": d.sockets().size()}
		"base.set", "height.set", "tile.set":
			var p3: TexPack = lib.get_pack(str(op.get("pack", "")))
			var tex := str(op.get("tex", ""))
			if p3 == null or not p3.textures.has(tex):
				return {"error": "нет текстуры %s в паке %s" % [tex, op.get("pack", "")]}
			if kind == "base.set":
				d.set_source("base", p3.id, tex)
				d.map["base"] = "base.webp"
				var e: Dictionary = p3.textures[tex]
				if int(e.get("h", 0)) > 0:
					d.editor["aspect"] = float(e.w) / float(e.h)
			elif kind == "height.set":
				d.set_source("height", p3.id, tex)
				d.map["height"] = "height.png"
				if not d.map.has("water"):
					d.map["water"] = "water_tile.webp"
				if not d.map.has("levels"):
					d.map["levels"] = {"normal": 55, "warn": 68, "flood": 115, "storm": 140}
			else:
				var slot := "water" if str(op.get("slot", "fog")) == "water" else "fog"
				d.set_source(slot + "_tile", p3.id, tex)
				d.map[slot] = slot + "_tile.webp"
			return {"set": kind, "tex": tex}
		"decal.add":
			var p4: TexPack = lib.get_pack(str(op.get("pack", "")))
			var dn := str(op.get("decal", op.get("tex", "")))
			if p4 == null or not p4.textures.has(str(op.get("tex", dn))):
				return {"error": "нет метки %s в паке %s" % [dn, op.get("pack", "")]}
			d.set_source(dn, p4.id, str(op.get("tex", dn)))
			var rec2 := {"decal": dn}
			var key2 := "place_decals"
			if op.has("path"):
				rec2["path"] = op.path
				key2 = "path_decals"
			else:
				rec2["place"] = str(op.get("place", ""))
			for ck2: String in ["phase", "from_day", "open", "variant", "flag"]:
				if op.has(ck2):
					rec2[ck2] = op[ck2]
			if not d.map.has(key2):
				d.map[key2] = []
			d.map[key2].append(rec2)
			return {key2: rec2}
		"map.set":
			var k := str(op.get("key", ""))
			if k in ["places", "paths", "region"]:
				return {"error": "%s меняется своими операциями" % k}
			if op.get("value") == null:
				d.map.erase(k)
			else:
				d.map[k] = op.value
			return {"key": k}
		"chapter.set":
			d.chapter = str(op.get("chapter", ""))
			return {"chapter": d.chapter}
	return {"error": "неизвестная операция %s" % kind}


# --- симуляция -----------------------------------------------------------------------------------

func _sim(d: MapDoc) -> MapSim:
	var s := MapSim.new(d)
	s.boat = args.has("boat")
	s.tide = str(args.get("tide", "normal"))
	s.phase = str(args.get("phase", "")) if str(args.get("phase", "")) != "true" else ""
	s.path_set = int(args.get("path-set", 0))
	return s


func _route() -> void:
	var d := _doc()
	if d == null:
		return
	var s := _sim(d)
	var a := str(args.get("from", ""))
	var b := str(args.get("to", ""))
	if not d.places().has(a):
		_fail("нет места --from %s" % a)
		return
	var dist := s.distances(a)
	var res := {"ok": true, "from": a, "distances": dist}
	if b != "":
		var path := s.route(a, b)
		res["to"] = b
		res["path"] = path
		res["steps"] = path.size() if not path.is_empty() else -1
		res["names"] = ([a] + path).map(func(x: String) -> String: return d.display_name(x)) if not path.is_empty() else []
		if path.is_empty():
			res["wet_path"] = s.route(a, b, false)
	_out(res)


func _step() -> void:
	var d := _doc()
	if d == null:
		return
	var s := _sim(d)
	var a := str(args.get("from", ""))
	var out := {}
	for n: String in s.neighbors(a):
		out[n] = s.why_not(a, n)
	_out({"ok": true, "from": a, "neighbors": out})


func _tide() -> void:
	var d := _doc()
	if d == null:
		return
	var s := _sim(d)
	var under: Array = []
	var maybe: Array = []
	for lid: String in d.places():
		if s.flooded(lid):
			under.append(lid)
		elif s.maybe_flooded(lid):
			maybe.append(lid)
	var land := d.permanent().filter(func(l: String) -> bool: return not s.flooded(l))
	var bad := MapGraph.unreachable(land, s.links().filter(func(e: Array) -> bool: return land.has(e[0]) and land.has(e[1])))
	_out({"ok": true, "tide": s.tide, "flooded": under, "maybe": maybe, "dry_connected": bad.is_empty(), "cut_off": bad})


# --- экспорт -------------------------------------------------------------------------------------

func _export() -> void:
	var d := _doc()
	if d == null:
		return
	var rows := MapChecks.run(d, TexSource.new(d, lib))
	if not MapChecks.errors(rows).is_empty() and not args.has("force"):
		_out({"ok": false, "error": "в карте есть ошибки — экспорт запрещён", "rows": MapChecks.errors(rows)}, 1)
		return
	var pl := GameIO.plan(d, lib)
	if not pl.errors.is_empty():
		_fail("; ".join(pl.errors))
		return
	var items: Array = pl.items.map(func(it: Dictionary) -> Dictionary: return {"rel": it.rel, "status": it.status, "kind": it.kind})
	if args.has("dry-run"):
		_out({"ok": true, "dry_run": true, "items": items})
		return
	var res := GameIO.write(d, pl.items)
	var out := {"ok": res.errors.is_empty(), "written": res.written, "backup": res.backup, "errors": res.errors, "items": items}
	if args.has("reimport") and not res.written.is_empty():
		var o: Array = []
		out["reimport_code"] = OS.execute(OS.get_executable_path(), GameIO.reimport_args(d.game), o, true)
	_out(out, 0 if res.errors.is_empty() else 1)


func _pack_textures() -> void:
	var p: TexPack = lib.get_pack(str(pos[1]) if pos.size() > 1 else "")
	if p == null:
		_fail("нет такого пака")
		return
	var kind := str(args.get("kind", ""))
	var out: Array = []
	var names := p.textures.keys()
	names.sort()
	for nm: String in names:
		var e: Dictionary = p.textures[nm]
		if kind != "" and str(e.kind) != kind:
			continue
		var r := {"name": nm, "kind": e.kind, "w": e.get("w", 0), "h": e.get("h", 0)}
		if e.has("place"):
			r["place"] = e.place
			r["state"] = e.state
		out.append(r)
	_out({"ok": true, "pack": p.id, "places": p.places(), "textures": out})


# --- снимок --------------------------------------------------------------------------------------

## render --project P --out file.png [--width 1600] [--mode plain|graph|route|tide|fog|step] [--from A --to B]
## [--select ID] [--labels false] [--phase night] [--tide flood]. Рисует тот же холст, что окно редактора.
func _render() -> void:
	var d := _doc()
	if d == null:
		return
	if DisplayServer.get_name() == "headless":
		_fail("снимку нужен рендер — запускайте без --headless")
		return
	var out := str(args.get("out", ""))
	if out == "":
		_fail("нужен --out <файл.png>")
		return
	var w := int(args.get("width", 1600))
	var aspect := d.base_aspect()
	var h := int(w / aspect) if not args.has("height") else int(args.height)
	if str(args.get("mode", "")) == "game":
		h = int(w * 9.0 / 16.0)
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	var cache := TexCache.new()
	root.add_child(cache)
	var holder := Control.new()
	holder.theme = UiTheme.make()
	holder.size = Vector2(w, h)
	vp.add_child(holder)
	var cv := MapCanvas.new()
	cv.size = Vector2(w, h)
	holder.add_child(cv)
	cv.setup(d, TexSource.new(d, lib), cache, lib)
	cv.base_px = float(w)
	cv.pan = Vector2(0, (h - w / aspect) / 2.0)
	var mode := str(args.get("mode", "plain"))
	if mode in cv.modes:
		cv.modes[mode] = true
	if mode == "game":
		# как окно игры: основа ≥ окна × zoom, сверху спрятано view_top, фигура у лагеря (--from), туман
		cv.game_mode = true
		cv.camp = str(args.get("from", ""))
		cv.layers.sockets = false
		cv.game_layout(Vector2(w, h))
		if cv.camp != "":
			cv.modes.fog = true
			cv.sim.visited = [cv.camp]
	cv.sim.boat = args.has("boat")
	cv.sim.tide = str(args.get("tide", "normal"))
	if mode == "tide" and cv.sim.tide == "normal":
		cv.sim.tide = "flood"
	cv.sim.phase = str(args.get("phase", "")) if str(args.get("phase", "")) != "true" else ""
	cv.route_from = str(args.get("from", ""))
	cv.route_to = str(args.get("to", ""))
	cv.step_from = str(args.get("from", ""))
	if args.has("visited"):
		cv.sim.visited = Array(str(args.visited).split(","))
	if args.has("select"):
		cv.select_place(str(args.select))
	for k: String in ["labels", "sockets", "foot", "decals"]:
		if args.has(k):
			cv.layers[k] = str(args[k]) != "false"
	cv.layers.foot = args.has("foot") and str(args.foot) != "false"
	cv.queue_redraw()
	# дождаться всех картинок (раскодирование в фоне)
	var t := 0
	while t < 300:
		await process_frame
		t += 1
		if t > 5 and not cache.is_loading():
			break
	cv.queue_redraw()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := img.save_png(out)
	if err != OK:
		_fail("не записать %s" % out)
		return
	_out({"ok": true, "out": out, "width": img.get_width(), "height": img.get_height(), "mode": mode})
