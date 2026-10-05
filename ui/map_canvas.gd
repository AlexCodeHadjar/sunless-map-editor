class_name MapCanvas
extends Control
## Холст карты (ТЗ §4): основа в масштабе, места, тропы пунктиром как в игре, площадки, метки, точка ромба события.
## Масштаб — колесо мыши, сдвиг — средняя кнопка или пробел + левая. Инструменты и режимы — см. Tool и modes.

signal selection_changed
signal status(text: String)
signal delete_requested
signal hint(text: String)

enum Tool { SELECT, PLACE, PATH, SOCKET, DECAL, RUBBLE, ZONE, ERASER }

const TOOL_NAMES := {Tool.SELECT: "Выбор", Tool.PLACE: "Место", Tool.PATH: "Тропа", Tool.SOCKET: "Площадка", Tool.DECAL: "Метка",
	Tool.RUBBLE: "Завал", Tool.ZONE: "Зона", Tool.ERASER: "Ластик"}
const TOOL_HINTS := {
	Tool.SELECT: "Щёлкните место, тропу или площадку. Тащите место мышью, за уголок — меняйте размер. Shift — медленнее.",
	Tool.PLACE: "Щёлкните по карте — поставить место, выбранное в паке слева. Или просто перетащите облик места из пака.",
	Tool.PATH: "Щёлкните одно место, потом другое — тропа появится. Щелчок по двум уже связанным местам убирает тропу.",
	Tool.SOCKET: "Щёлкните по карте — новая площадка для появляющихся мест. Площадку можно тащить.",
	Tool.DECAL: "Перетащите метку из пака на место или на тропу. Щёлкните метку — её условия справа.",
	Tool.RUBBLE: "Щёлкните тропу — на ней появится точка завала (тропа может завалиться в игре).",
	Tool.ZONE: "Щёлкните место — оно станет центром зоны (охват — в шагах по тропам).",
	Tool.ERASER: "Щёлкните то, что нужно убрать: место, тропу, площадку, метку или завал."}

var doc: MapDoc
var src: TexSource
var cache: TexCache
var lib: PackLibrary
var sim: MapSim

var tool := Tool.SELECT
var modes := {"graph": false, "route": false, "tide": false, "fog": false, "step": false}
var layers := {"base": true, "water": true, "paths": true, "places": true, "labels": true, "sockets": true, "decals": true,
	"foot": true, "height": false}
var locked := {"places": false, "sockets": false, "paths": false}
var detailed := false
var preview_state := {}            ## место → облик для предпросмотра
var pack_pick := {}                ## выбранная в паке текстура {pack, tex}
var height_alpha := 0.5

var base_px := 1000.0              ## ширина основы на экране
var pan := Vector2.ZERO            ## левый верхний угол основы на экране
var sel := {}                      ## {kind: place|path|socket|decal|rubble, id}
var hover := {}
var path_from := ""
var route_from := ""
var route_to := ""
var step_from := ""

var _drag := {}
var _space := false
var _mouse := Vector2.ZERO
var _fitted := false
var _water_rect: ColorRect
var _water_mat: ShaderMaterial


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func() -> void:
		if not _fitted:
			fit())
	_water_rect = ColorRect.new()
	_water_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_rect.show_behind_parent = false
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://ui/shaders/water.gdshader")
	_water_rect.material = _water_mat
	_water_rect.visible = false
	add_child(_water_rect)


func setup(d: MapDoc, s: TexSource, c: TexCache, l: PackLibrary) -> void:
	doc = d
	src = s
	cache = c
	lib = l
	sim = MapSim.new(d)
	sel = {}
	path_from = ""
	route_from = ""
	route_to = ""
	preview_state = {}
	if not cache.loaded.is_connected(_on_tex_ready):
		cache.loaded.connect(_on_tex_ready)
	_fitted = false
	fit()
	queue_redraw()


func _on_tex_ready(_k: String) -> void:
	queue_redraw()


# --- координаты ----------------------------------------------------------------------------------

func aspect() -> float:
	return doc.base_aspect() if doc != null else 2.0


func base_rect() -> Rect2:
	return Rect2(pan, Vector2(base_px, base_px / aspect()))


func to_screen(p: Vector2) -> Vector2:
	return pan + Vector2(p.x * base_px, p.y * base_px / aspect())


func to_map(s: Vector2) -> Vector2:
	return Vector2((s.x - pan.x) / base_px, (s.y - pan.y) * aspect() / base_px)


func place_center(lid: String) -> Vector2:
	return to_screen(sim.anchor(lid) if sim != null else doc.at(lid))


func place_px(lid: String) -> float:
	return doc.size_of(lid) * base_px


func foot_point(lid: String) -> Vector2:
	return place_center(lid) + Vector2(0, place_px(lid) * float(doc.map.get("foot", 0.28)))


## Вписать основу в окно.
func fit() -> void:
	if size.x < 10 or doc == null:
		return
	base_px = minf(size.x * 0.96, size.y * 0.96 * aspect())
	pan = (size - Vector2(base_px, base_px / aspect())) / 2.0
	_fitted = true
	queue_redraw()


func zoom_at(factor: float, at: Vector2) -> void:
	var m := to_map(at)
	base_px = clampf(base_px * factor, 200.0, 20000.0)
	pan = at - Vector2(m.x * base_px, m.y * base_px / aspect())
	queue_redraw()


## Показать место в середине холста.
func focus_place(lid: String) -> void:
	if doc == null or not doc.places().has(lid):
		return
	var c := place_center(lid)
	pan += size / 2.0 - c
	queue_redraw()


func focus_point(p: Vector2) -> void:
	pan += size / 2.0 - to_screen(p)
	queue_redraw()


# --- отрисовка -----------------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.BG.darkened(0.25))
	if doc == null:
		_center_text("Откройте карту из игры или создайте новый проект (меню «Файл»)")
		return
	var br := base_rect()
	var base_tex: Texture2D = null
	if layers.base:
		base_tex = cache.map_tex(src, str(doc.map.get("base", "base.webp")).get_basename(), 4096)
	if base_tex != null:
		draw_texture_rect(base_tex, br, false)
	else:
		_checker(br)
		if not src.exists(str(doc.map.get("base", "base.webp")).get_basename()):
			_text_at(br.get_center(), "Перетащите сюда основу из пака (вид «Основы»)", 20, UiTheme.DIM)
	_update_water(br)
	if layers.height and doc.map.has("height"):
		var ht := cache.map_tex(src, str(doc.map.height), 2048)
		if ht != null:
			draw_texture_rect(ht, br, false, Color(1, 1, 1, height_alpha))
	var dim: bool = modes.graph
	if dim:
		draw_rect(br, Color(0, 0, 0, 0.55))
	if layers.paths and not modes.graph:
		_draw_paths()
	if layers.places and not modes.graph:
		_draw_places()
	if layers.decals and not modes.graph:
		_draw_decals()
	if modes.graph:
		_draw_graph()
	if modes.fog:
		_draw_fog()
	if layers.labels and not modes.graph:
		_draw_labels()
	if layers.sockets:
		_draw_sockets()
	if layers.foot and not modes.graph and not modes.route:
		_draw_feet()
	_draw_rubble()
	if modes.route:
		_draw_route()
	if modes.step:
		_draw_step()
	_draw_selection()
	if tool == Tool.PATH and path_from != "" and doc.places().has(path_from):
		_dashed(place_center(path_from), _mouse, UiTheme.ACCENT, 3.0, 12.0)


func _center_text(t: String) -> void:
	_text_at(size / 2.0, t, 20, UiTheme.DIM)


func _text_at(c: Vector2, t: String, fs: int, col: Color, outline: bool = true) -> void:
	var f := UiTheme.font()
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := c + Vector2(-w / 2.0, fs * 0.35)
	if outline:
		draw_string_outline(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.9))
	draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _checker(r: Rect2) -> void:
	draw_rect(r, Color(0.2, 0.21, 0.23))
	var cell := 64.0
	var y := r.position.y
	var row := 0
	while y < r.end.y:
		var x := r.position.x + (cell if row % 2 == 1 else 0.0)
		while x < r.end.x:
			var c := Rect2(Vector2(x, y), Vector2(cell, cell)).intersection(r)
			draw_rect(c, Color(0.24, 0.25, 0.27))
			x += cell * 2.0
		y += cell
		row += 1


## Вода прилива поверх основы — тот же шейдер, что в игре (карта высот, уровень).
func _update_water(br: Rect2) -> void:
	var show: bool = layers.water and doc.map.has("height") and (modes.tide or layers.water)
	if not show:
		_water_rect.visible = false
		return
	var ht := cache.full_tex(src, str(doc.map.height)) if src.exists(str(doc.map.height)) else null
	var wt := cache.map_tex(src, str(doc.map.get("water", "water_tile.webp")).get_basename(), 512)
	if ht == null or wt == null:
		_water_rect.visible = false
		return
	_water_rect.visible = true
	_water_rect.position = br.position
	_water_rect.size = br.size
	var lv: Dictionary = doc.map.get("levels", {})
	var normal := float(lv.get("normal", 55))
	var level := normal
	if modes.tide:
		level = float(lv.get(sim.tide, normal)) if sim.tide != "normal" else normal
	_water_mat.set_shader_parameter("height_tex", ht)
	_water_mat.set_shader_parameter("water_tex", wt)
	_water_mat.set_shader_parameter("level", level)
	_water_mat.set_shader_parameter("normal_level", normal)
	_water_mat.set_shader_parameter("aspect", aspect())


## Тропа как в игре: изогнутый пунктир тушью, концы отступают от виньеток.
func curve_points(a: Vector2, b: Vector2, sa: float, sb: float) -> PackedVector2Array:
	var dir := (b - a).normalized()
	a += dir * sa * 0.3
	b -= dir * sb * 0.3
	var mid := (a + b) / 2.0 + Vector2(-dir.y, dir.x) * a.distance_to(b) * 0.08
	var pts := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	return pts


func _draw_ink(pts: PackedVector2Array, ink: Color, w: float) -> void:
	for i in 24:
		if i % 2 == 1:
			continue
		draw_line(pts[i], pts[i + 1], Color(0, 0, 0, 0.45), w * 2.0, true)
		draw_line(pts[i], pts[i + 1], ink, w, true)


func _all_edges() -> Array:
	## [пара, вид]: path | water | storm(N) — для отрисовки
	var out: Array = []
	for e: Array in doc.paths():
		out.append([e, "path"])
	for e2: Array in doc.map.get("water_paths", []):
		out.append([e2, "water"])
	var sets: Array = doc.map.get("path_sets", {}).get("sets", [])
	for i in sets.size():
		if i == posmod(sim.path_set, sets.size()):
			for e3: Array in sets[i]:
				out.append([e3, "storm"])
	return out


func _draw_paths() -> void:
	var w := clampf(base_px / 1000.0, 1.5, 4.0)
	for it: Array in _all_edges():
		var e: Array = it[0]
		var a := str(e[0])
		var b := str(e[1])
		if not doc.places().has(a) or not doc.places().has(b):
			continue
		if not sim.present(a) or not sim.present(b):
			continue
		var ink := Color(0.86, 0.84, 0.78, 0.75)
		if it[1] == "water":
			ink = Color(0.45, 0.7, 1.0, 0.85)
		elif it[1] == "storm":
			ink = Color(1.0, 0.62, 0.3, 0.85)
		if modes.tide and (sim.flooded(a) or sim.flooded(b)):
			ink = Color(0.62, 0.78, 0.92, 0.35)
		var pts := curve_points(place_center(a), place_center(b), place_px(a), place_px(b))
		var selp: bool = sel.get("kind", "") == "path" and MapDoc.same_pair(Array(sel.id), a, b)
		if selp:
			draw_polyline(pts, Color(UiTheme.ACCENT, 0.5), w * 5.0, true)
		_draw_ink(pts, ink, w)


func state_for(lid: String) -> String:
	if preview_state.has(lid) and doc.states(lid).has(preview_state[lid]):
		return preview_state[lid]
	if sim != null and (sim.phase != "" or sim.tide != "normal" or not sim.collapsed.is_empty()):
		return sim.place_state(lid)
	var sts := doc.states(lid)
	return "dry" if sts.has("dry") else (str(sts[0]) if not sts.is_empty() else "")


func _draw_places() -> void:
	for lid: String in doc.places():
		if not sim.present(lid):
			continue
		var c := place_center(lid)
		var px := place_px(lid)
		var r := Rect2(c - Vector2(px, px) / 2.0, Vector2(px, px))
		if not r.intersects(Rect2(Vector2.ZERO, size)):
			continue
		var st := state_for(lid)
		if st == "":
			continue   # место нарисовано на основе (states пустой)
		var nm := "%s_%s" % [lid, st]
		var tex := cache.map_tex(src, nm, 512 if px > 220 else 256)
		var tint := Color.WHITE
		if modes.fog and not sim.known().has(lid):
			tint = Color(1, 1, 1, 0.35)
		if tex != null:
			draw_texture_rect(tex, r, false, tint)
		elif not src.exists(nm):
			_dashed_rect(r.grow(-px * 0.18), UiTheme.ERROR)
			_text_at(c, "нет картинки", 13, UiTheme.ERROR)
		if modes.tide and sim.maybe_flooded(lid):
			draw_arc(c, px * 0.42, 0, TAU, 48, Color(0.55, 0.8, 1.0, 0.8), 3.0, true)


func _draw_decals() -> void:
	var offs := [Vector2(0.24, -0.2), Vector2(-0.27, 0.16), Vector2(0.2, 0.22), Vector2(-0.22, -0.22), Vector2(0.0, 0.3)]
	var slot := {}
	for d: Dictionary in sim.decals():
		var nm := str(d.get("decal", ""))
		var tex := cache.map_tex(src, nm, 256)
		if d.has("path"):
			var pr: Array = d.path
			if pr.size() != 2 or not doc.places().has(str(pr[0])) or not doc.places().has(str(pr[1])):
				continue
			var a := place_center(str(pr[0]))
			var b := place_center(str(pr[1]))
			if tex != null:
				var ln := a.distance_to(b) * 0.62
				draw_set_transform((a + b) / 2.0, (b - a).angle(), Vector2.ONE)
				draw_texture_rect(tex, Rect2(-ln / 2.0, -ln * 0.125, ln, ln * 0.25), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			continue
		var lid := str(d.get("place", ""))
		if not doc.places().has(lid) or not sim.present(lid):
			continue
		var c := place_center(lid)
		var sz := place_px(lid)
		var i := int(slot.get(lid, 0))
		slot[lid] = i + 1
		if tex == null:
			continue
		if tex.get_width() >= 3 * tex.get_height():
			var w := sz * 0.7
			draw_texture_rect(tex, Rect2(c + Vector2(-w / 2.0, -sz * 0.22), Vector2(w, w * 0.25)), false, Color(1, 1, 1, 0.8))
			continue
		var o: Vector2 = offs[i % offs.size()]
		var ds := sz * 0.3
		var rr := Rect2(c + o * sz - Vector2(ds, ds) / 2.0, Vector2(ds, ds))
		draw_texture_rect(tex, rr, false)
		if sel.get("kind", "") == "decal" and sel.get("id") == d:
			draw_rect(rr, UiTheme.ACCENT, false, 2.0)


func _draw_labels() -> void:
	var fs := int(clampf(base_px / 110.0, 11.0, 20.0))
	for lid: String in doc.places():
		if not sim.present(lid):
			continue
		var p := foot_point(lid) + Vector2(0, fs * 1.4)
		var col := Color(0.78, 0.9, 1.0) if (modes.tide and sim.flooded(lid)) else Color.WHITE
		_text_at(p, doc.display_name(lid), fs, col)
		if detailed:
			_text_at(p + Vector2(0, fs * 1.1), lid, maxi(10, fs - 4), UiTheme.DIM)


func _draw_feet() -> void:
	for lid: String in doc.places():
		if not sim.present(lid):
			continue
		var f := foot_point(lid)
		var s := 7.0
		var pts := PackedVector2Array([f + Vector2(0, -s), f + Vector2(s, 0), f + Vector2(0, s), f + Vector2(-s, 0)])
		draw_colored_polygon(pts, Color(0.95, 0.8, 0.45, 0.85))
		pts.append(pts[0])
		draw_polyline(pts, Color(0, 0, 0, 0.8), 1.5, true)


func _draw_sockets() -> void:
	var sk: Array = doc.sockets()
	for i in sk.size():
		var c := to_screen(Vector2(float(sk[i][0]), float(sk[i][1])))
		var on: bool = sel.get("kind", "") == "socket" and int(sel.id) == i
		draw_circle(c, 11.0, Color(0.1, 0.12, 0.16, 0.75))
		draw_arc(c, 11.0, 0, TAU, 32, UiTheme.ACCENT if on else Color(0.75, 0.85, 1.0), 2.5, true)
		_text_at(c + Vector2(0, -1), str(i + 1), 12, Color.WHITE, false)
		var used := _socket_user(i)
		if used != "":
			_text_at(c + Vector2(0, 20), used, 11, UiTheme.DIM)


## Какое появляющееся место стоит на площадке в предпросмотре.
func _socket_user(i: int) -> String:
	for lid: String in sim.emerged:
		if int(sim.emerged[lid]) == i:
			return doc.display_name(lid)
	return ""


func _draw_rubble() -> void:
	var rb: Dictionary = doc.map.get("rubble", {})
	for rid: String in rb:
		var at: Array = rb[rid].get("at", [])
		if at.size() != 2:
			continue
		var c := to_screen(Vector2(float(at[0]), float(at[1])))
		var blocked: bool = sim.rubble_blocked.get(rid, false)
		draw_rect(Rect2(c - Vector2(9, 9), Vector2(18, 18)), Color(0.35, 0.25, 0.2, 0.9) if blocked else Color(0.25, 0.25, 0.25, 0.6))
		draw_rect(Rect2(c - Vector2(9, 9), Vector2(18, 18)), UiTheme.ACCENT if sel.get("id", "") == rid else Color(0.9, 0.7, 0.5), false, 2.0)
		_text_at(c + Vector2(0, 20), "завал", 11, Color(0.9, 0.7, 0.5))


func _draw_graph() -> void:
	var edges: Array = _all_edges()
	for it: Array in edges:
		var e: Array = it[0]
		if not doc.places().has(str(e[0])) or not doc.places().has(str(e[1])):
			continue
		var col := Color(1, 1, 1, 0.8)
		if it[1] == "water":
			col = Color(0.45, 0.7, 1.0, 0.9)
		elif it[1] == "storm":
			col = Color(1.0, 0.62, 0.3, 0.9)
		var selp: bool = sel.get("kind", "") == "path" and MapDoc.same_pair(Array(sel.id), str(e[0]), str(e[1]))
		draw_line(place_center(str(e[0])), place_center(str(e[1])), UiTheme.ACCENT if selp else col, 4.0 if selp else 2.5, true)
	var perm := doc.permanent()
	var comps := MapGraph.components(perm, doc.paths() + Array(doc.map.get("water_paths", [])) + _union_sets())
	var main_comp: Array = comps[0] if not comps.is_empty() else []
	var from := str(sel.id) if sel.get("kind", "") == "place" else ""
	var dist := MapGraph.distances(MapGraph.adjacency(doc.paths() + _union_sets()), from) if from != "" else {}
	var fs := 13
	for lid: String in doc.places():
		var c := place_center(lid)
		var h := "shop" if doc.is_shop(lid) else doc.height_of(lid)
		var col2: Color = UiTheme.HEIGHT_COLORS.get(h, UiTheme.HEIGHT_COLORS[""])
		var r := 15.0
		if doc.is_emerging(lid):
			draw_arc(c, r, 0, TAU, 32, col2, 2.5, true)
		else:
			draw_circle(c, r, col2)
		var lonely := doc.path_places(lid).is_empty() and not doc.is_emerging(lid)
		if lonely or (not doc.is_emerging(lid) and not main_comp.has(lid)):
			draw_arc(c, r + 5, 0, TAU, 32, UiTheme.ERROR, 3.0, true)
		if from == lid:
			draw_arc(c, r + 5, 0, TAU, 32, UiTheme.ACCENT, 3.0, true)
		if dist.has(lid):
			_text_at(c, str(dist[lid]), 14, Color.BLACK, false)
		_text_at(c + Vector2(0, r + fs + 2), doc.display_name(lid), fs, Color.WHITE)
	# легенда
	var y := 14.0
	for k: String in ["low", "mid", "high", "shop"]:
		draw_circle(Vector2(18, y + 6), 7, UiTheme.HEIGHT_COLORS[k])
		draw_string(UiTheme.font(), Vector2(32, y + 11), {"low": "низина", "mid": "средняя высота", "high": "высота", "shop": "лавка"}[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		y += 20
	draw_arc(Vector2(18, y + 6), 8, 0, TAU, 24, UiTheme.ERROR, 2.5, true)
	draw_string(UiTheme.font(), Vector2(32, y + 11), "не связано с остальной картой", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


func _union_sets() -> Array:
	var out: Array = []
	for st: Array in doc.map.get("path_sets", {}).get("sets", []):
		out.append_array(st)
	return out


func _draw_route() -> void:
	if route_from == "" or not doc.places().has(route_from):
		return
	var dist := sim.distances(route_from)
	for lid: String in doc.places():
		if not sim.present(lid):
			continue
		var c := place_center(lid) + Vector2(place_px(lid) * 0.28, -place_px(lid) * 0.28)
		var txt := str(dist[lid]) if dist.has(lid) else "×"
		draw_circle(c, 13, Color(0.08, 0.08, 0.1, 0.9) if dist.has(lid) else Color(0.4, 0.1, 0.1, 0.9))
		_text_at(c, txt, 14, UiTheme.ACCENT if dist.has(lid) else Color.WHITE, false)
	var camp := place_center(route_from)
	draw_arc(camp, place_px(route_from) * 0.45, 0, TAU, 48, UiTheme.ACCENT, 3.0, true)
	_text_at(camp + Vector2(0, -place_px(route_from) * 0.45 - 12), "лагерь", 14, UiTheme.ACCENT)
	if route_to != "" and doc.places().has(route_to):
		var path := sim.route(route_from, route_to)
		var prev := route_from
		for p: String in path:
			_dashed(place_center(prev), place_center(p), UiTheme.ACCENT, 4.0, 14.0)
			prev = p
		draw_arc(place_center(route_to), place_px(route_to) * 0.45, 0, TAU, 48, Color(1, 1, 1, 0.9), 2.5, true)


func _draw_step() -> void:
	if step_from == "" or not doc.places().has(step_from):
		return
	var c0 := place_center(step_from)
	draw_arc(c0, place_px(step_from) * 0.45, 0, TAU, 48, Color(1.0, 0.8, 0.42), 4.0, true)
	_text_at(c0 + Vector2(0, -place_px(step_from) * 0.45 - 12), "фигура", 14, Color(1.0, 0.8, 0.42))
	for n: String in sim.neighbors(step_from):
		var c := place_center(n)
		var why := sim.why_not(step_from, n)
		var r := place_px(n) * 0.42
		if why == "":
			draw_arc(c, r, 0, TAU, 48, UiTheme.SILVER, 4.0, true)
		else:
			draw_arc(c, r, 0, TAU, 48, Color(0.55, 0.08, 0.1), 4.0, true)
			_text_at(c + Vector2(0, r + 14), why, 12, Color(1.0, 0.6, 0.6))


func _draw_fog() -> void:
	var kn := sim.known()
	var br := base_rect()
	# туман — дымка поверх основы; открытое — светлые круги (как маска игры, упрощённо)
	draw_rect(br, Color(0.08, 0.08, 0.1, 0.55))
	for lid: String in kn:
		if not doc.places().has(lid):
			continue
		var c := place_center(lid)
		var rr := 0.17 * br.size.y
		for k in 4:
			draw_circle(c, rr * (1.0 - k * 0.18), Color(0.85, 0.82, 0.75, 0.05))
		if sim.visited.has(lid):
			draw_arc(c, place_px(lid) * 0.45, 0, TAU, 48, UiTheme.OK, 3.0, true)
	for e: Array in sim.links():
		if kn.has(str(e[0])) and kn.has(str(e[1])):
			draw_line(place_center(str(e[0])), place_center(str(e[1])), Color(0.85, 0.82, 0.75, 0.12), 0.1 * br.size.y, true)


func _draw_selection() -> void:
	var k := str(sel.get("kind", ""))
	if k == "place" and doc.places().has(str(sel.id)):
		var lid := str(sel.id)
		var c := place_center(lid)
		var px := place_px(lid)
		var r := Rect2(c - Vector2(px, px) / 2.0, Vector2(px, px))
		_dashed_rect(r, UiTheme.ACCENT)
		draw_rect(Rect2(r.end - Vector2(7, 7), Vector2(14, 14)), UiTheme.ACCENT)
	if k == "" and hover.get("kind", "") == "place" and doc.places().has(str(hover.id)):
		var c2 := place_center(str(hover.id))
		draw_arc(c2, place_px(str(hover.id)) * 0.4, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
	if tool == Tool.PATH and path_from != "" and doc.places().has(path_from):
		draw_arc(place_center(path_from), place_px(path_from) * 0.4, 0, TAU, 48, UiTheme.ACCENT, 3.0, true)


func _dashed(a: Vector2, b: Vector2, col: Color, w: float, dash: float) -> void:
	var ln := a.distance_to(b)
	if ln < 1.0:
		return
	var dir := (b - a) / ln
	var d := 0.0
	while d < ln:
		draw_line(a + dir * d, a + dir * minf(d + dash, ln), col, w, true)
		d += dash * 2.0


func _dashed_rect(r: Rect2, col: Color) -> void:
	_dashed(r.position, Vector2(r.end.x, r.position.y), col, 2.0, 8.0)
	_dashed(Vector2(r.end.x, r.position.y), r.end, col, 2.0, 8.0)
	_dashed(r.end, Vector2(r.position.x, r.end.y), col, 2.0, 8.0)
	_dashed(Vector2(r.position.x, r.end.y), r.position, col, 2.0, 8.0)


# --- попадание мышью -----------------------------------------------------------------------------

func place_at(p: Vector2) -> String:
	var best := ""
	var bd := INF
	for lid: String in doc.places():
		if not sim.present(lid):
			continue
		var c := place_center(lid)
		var d := c.distance_to(p)
		var lim := maxf(place_px(lid) * 0.4, 14.0)
		if modes.graph:
			lim = 18.0
		if d < lim and d < bd:
			bd = d
			best = lid
	return best


func socket_at(p: Vector2) -> int:
	var sk: Array = doc.sockets()
	for i in range(sk.size() - 1, -1, -1):
		if to_screen(Vector2(float(sk[i][0]), float(sk[i][1]))).distance_to(p) < 13.0:
			return i
	return -1


func path_at(p: Vector2) -> Array:
	var best: Array = []
	var bd := 9.0
	for e: Array in doc.paths():
		var a := str(e[0])
		var b := str(e[1])
		if not doc.places().has(a) or not doc.places().has(b):
			continue
		var pts := curve_points(place_center(a), place_center(b), place_px(a), place_px(b))
		if modes.graph:
			pts = PackedVector2Array([place_center(a), place_center(b)])
		for i in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			if q.distance_to(p) < bd:
				bd = q.distance_to(p)
				best = [a, b]
	return best


func rubble_at(p: Vector2) -> String:
	var rb: Dictionary = doc.map.get("rubble", {})
	for rid: String in rb:
		var at: Array = rb[rid].get("at", [])
		if at.size() == 2 and to_screen(Vector2(float(at[0]), float(at[1]))).distance_to(p) < 12.0:
			return rid
	return ""


func decal_at(p: Vector2) -> Dictionary:
	var offs := [Vector2(0.24, -0.2), Vector2(-0.27, 0.16), Vector2(0.2, 0.22), Vector2(-0.22, -0.22), Vector2(0.0, 0.3)]
	var slot := {}
	for d: Dictionary in sim.decals():
		if d.has("path"):
			continue
		var lid := str(d.get("place", ""))
		if not doc.places().has(lid):
			continue
		var i := int(slot.get(lid, 0))
		slot[lid] = i + 1
		var sz := place_px(lid)
		var c: Vector2 = place_center(lid) + offs[i % offs.size()] * sz
		if c.distance_to(p) < sz * 0.15:
			return d
	return {}


func _handle_hit(p: Vector2) -> bool:
	if sel.get("kind", "") != "place" or not doc.places().has(str(sel.id)):
		return false
	var lid := str(sel.id)
	var px := place_px(lid)
	var corner := place_center(lid) + Vector2(px, px) / 2.0
	return corner.distance_to(p) < 12.0


func _foot_hit(p: Vector2) -> String:
	if not layers.foot:
		return ""
	for lid: String in doc.places():
		if foot_point(lid).distance_to(p) < 9.0:
			return lid
	return ""


# --- ввод ----------------------------------------------------------------------------------------

func _gui_input(ev: InputEvent) -> void:
	if doc == null:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		_mouse = mb.position
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_at(1.15, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_at(1.0 / 1.15, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and _space):
			if mb.pressed:
				_drag = {"what": "pan", "start": mb.position, "pan": pan}
			else:
				_drag = {}
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			if mb.pressed:
				_press(mb.position, mb.shift_pressed, mb.double_click)
			else:
				_release()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			path_from = ""
			if tool != Tool.SELECT:
				set_tool(Tool.SELECT)
			queue_redraw()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		_mouse = mm.position
		_motion(mm.position, mm.shift_pressed)
	elif ev is InputEventKey:
		var k := ev as InputEventKey
		if k.keycode == KEY_SPACE:
			_space = k.pressed
			mouse_default_cursor_shape = Control.CURSOR_DRAG if _space else Control.CURSOR_ARROW
			accept_event()
			return
		if not k.pressed:
			return
		match k.keycode:
			KEY_ESCAPE:
				if not _drag.is_empty() and _drag.get("what", "") != "pan":
					doc.cancel()
				_drag = {}
				path_from = ""
				sel = {}
				selection_changed.emit()
				queue_redraw()
				accept_event()
			KEY_DELETE, KEY_BACKSPACE:
				if not sel.is_empty():
					delete_requested.emit()
				accept_event()
			KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
				_nudge(k.keycode, k.shift_pressed)
				accept_event()


func _press(p: Vector2, shift: bool, dbl: bool) -> void:
	match tool:
		Tool.SELECT:
			if modes.route:
				var lid0 := place_at(p)
				if lid0 != "":
					if route_from == "" or dbl:
						route_from = lid0
						route_to = ""
					else:
						route_to = lid0
					_route_status()
					queue_redraw()
					return
			if modes.step:
				var lid1 := place_at(p)
				if lid1 != "":
					if step_from == "" or not sim.neighbors(step_from).has(lid1):
						step_from = lid1
						status.emit("Фигура стоит на «%s». Серебром — куда можно шагнуть, тёмно-красным — нельзя." % doc.display_name(lid1))
					else:
						var why := sim.why_not(step_from, lid1)
						if why == "":
							step_from = lid1
							if not sim.visited.has(lid1):
								sim.visited.append(lid1)
							status.emit("Фигура перешла на «%s» (полдня)." % doc.display_name(lid1))
						else:
							status.emit(why)
					queue_redraw()
					return
			if _handle_hit(p) and not locked.places:
				var lid := str(sel.id)
				doc.begin("Размер места")
				_drag = {"what": "resize", "id": lid, "start": p, "size": doc.size_of(lid), "slow": shift}
				return
			var fh := _foot_hit(p)
			if fh != "" and not modes.graph:
				doc.begin("Точка ромба события")
				_drag = {"what": "foot", "id": fh}
				return
			var si := socket_at(p) if layers.sockets else -1
			if si >= 0:
				_select({"kind": "socket", "id": si})
				if not locked.sockets:
					doc.begin("Сдвинуть площадку")
					_drag = {"what": "socket", "id": si, "start": p, "at": to_map(p)}
				return
			var rid := rubble_at(p)
			if rid != "":
				_select({"kind": "rubble", "id": rid})
				doc.begin("Сдвинуть завал")
				_drag = {"what": "rubble", "id": rid}
				return
			var dc := decal_at(p) if layers.decals and not modes.graph else {}
			if not dc.is_empty():
				_select({"kind": "decal", "id": dc})
				return
			var lid2 := place_at(p)
			if lid2 != "":
				_select({"kind": "place", "id": lid2})
				if not locked.places:
					doc.begin("Сдвинуть место")
					_drag = {"what": "move", "id": lid2, "start": p, "at": doc.at(lid2), "slow": shift}
				return
			var pa := path_at(p)
			if not pa.is_empty():
				_select({"kind": "path", "id": pa})
				return
			_select({})
			_drag = {"what": "pan", "start": p, "pan": pan}
		Tool.PLACE:
			emit_signal("hint", "place_click")
			_place_from_pick(to_map(p))
		Tool.PATH:
			var lid3 := place_at(p)
			if lid3 == "":
				path_from = ""
				status.emit("Щёлкните по месту, чтобы начать тропу.")
			elif path_from == "":
				path_from = lid3
				status.emit("Тропа от «%s» — теперь щёлкните второе место." % doc.display_name(lid3))
			else:
				var a := path_from
				var had := doc.has_path(a, lid3)
				var err: String = doc.edit("Убрать тропу" if had else "Тропа", func() -> String: return doc.toggle_path(a, lid3))
				if err != "":
					status.emit(err.capitalize())
				else:
					status.emit(("Тропа убрана: «%s» — «%s»" if had else "Тропа: «%s» — «%s»") % [doc.display_name(a), doc.display_name(lid3)])
				path_from = lid3 if not had else ""
			queue_redraw()
		Tool.SOCKET:
			var si2 := socket_at(p)
			if si2 >= 0:
				_select({"kind": "socket", "id": si2})
				doc.begin("Сдвинуть площадку")
				_drag = {"what": "socket", "id": si2, "start": p, "at": to_map(p)}
			else:
				var m := to_map(p)
				var n: int = doc.edit("Площадка", func() -> int: return doc.add_socket(m))
				_select({"kind": "socket", "id": n})
				status.emit("Площадка %d поставлена." % (n + 1))
		Tool.RUBBLE:
			var pa2 := path_at(p)
			if pa2.is_empty():
				status.emit("Щёлкните по тропе — завал ставится на тропу.")
				return
			var m2 := to_map(p)
			var rid2: String = doc.edit("Завал", func() -> String:
				if not doc.map.has("rubble"):
					doc.map["rubble"] = {}
				var n2 := 1
				while doc.map.rubble.has("R%d" % n2):
					n2 += 1
				doc.map.rubble["R%d" % n2] = {"at": [MapDoc.r3(m2.x), MapDoc.r3(m2.y)], "pair": pa2}
				return "R%d" % n2)
			_select({"kind": "rubble", "id": rid2})
		Tool.ZONE:
			var lid4 := place_at(p)
			if lid4 == "":
				return
			var zid: String = doc.edit("Зона", func() -> String:
				if not doc.map.has("zones"):
					doc.map["zones"] = {}
				var n3 := 1
				while doc.map.zones.has("zone%d" % n3):
					n3 += 1
				doc.map.zones["zone%d" % n3] = {"name": "Новая зона", "center": lid4, "radius": {"default": 1}, "color": [1.0, 0.3, 0.2]}
				return "zone%d" % n3)
			_select({"kind": "zone", "id": zid})
			status.emit("Зона с центром в «%s» — настройте её справа." % doc.display_name(lid4))
		Tool.ERASER:
			_erase_at(p)
		Tool.DECAL:
			var dc2 := decal_at(p)
			if not dc2.is_empty():
				_select({"kind": "decal", "id": dc2})
			else:
				status.emit(TOOL_HINTS[Tool.DECAL])


func _erase_at(p: Vector2) -> void:
	var si := socket_at(p)
	if si >= 0:
		doc.edit("Убрать площадку", func() -> void: doc.remove_socket(si))
		status.emit("Площадка убрана, номера остальных пересчитаны.")
		return
	var rid := rubble_at(p)
	if rid != "":
		doc.edit("Убрать завал", func() -> void: doc.map.rubble.erase(rid))
		return
	var dc := decal_at(p)
	if not dc.is_empty():
		doc.edit("Убрать метку", func() -> void: doc.map.place_decals.erase(dc))
		return
	var lid := place_at(p)
	if lid != "":
		_select({"kind": "place", "id": lid})
		delete_requested.emit()
		return
	var pa := path_at(p)
	if not pa.is_empty():
		doc.edit("Убрать тропу", func() -> void: doc.toggle_path(str(pa[0]), str(pa[1])))
		status.emit("Тропа убрана.")


func _motion(p: Vector2, shift: bool) -> void:
	var w := str(_drag.get("what", ""))
	match w:
		"pan":
			pan = Vector2(_drag.pan) + (p - Vector2(_drag.start))
			queue_redraw()
		"move":
			var k := 0.25 if shift else 1.0
			var dm := (p - Vector2(_drag.start)) * k
			var to := Vector2(_drag.at) + Vector2(dm.x / base_px, dm.y * aspect() / base_px)
			doc.move_place(str(_drag.id), to)
			queue_redraw()
			_coords(to)
		"resize":
			var lid := str(_drag.id)
			var c := place_center(lid)
			var half := maxf(absf(p.x - c.x), absf(p.y - c.y))
			var target := (half * 2.0) / base_px
			if shift:
				target = float(_drag.size) + (target - float(_drag.size)) * 0.25
			doc.set_size(lid, target)
			status.emit("Размер: %s" % Words.place_size(doc.size_of(lid)))
			queue_redraw()
		"socket":
			doc.move_socket(int(_drag.id), to_map(p))
			queue_redraw()
		"rubble":
			var m := to_map(p)
			doc.map.rubble[str(_drag.id)]["at"] = [MapDoc.r3(m.x), MapDoc.r3(m.y)]
			queue_redraw()
		"foot":
			var lid2 := str(_drag.id)
			var f := clampf((p.y - place_center(lid2).y) / maxf(place_px(lid2), 1.0), 0.0, 0.5)
			doc.map["foot"] = snappedf(f, 0.01)
			queue_redraw()
		_:
			var h := {}
			var lid3 := place_at(p)
			if lid3 != "":
				h = {"kind": "place", "id": lid3}
			if h != hover:
				hover = h
				queue_redraw()
			if _handle_hit(p):
				mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
			elif _foot_hit(p) != "":
				mouse_default_cursor_shape = Control.CURSOR_VSIZE
			elif not _space:
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if lid3 != "" else Control.CURSOR_ARROW
			if tool == Tool.PATH and path_from != "":
				queue_redraw()
			_coords(to_map(p))
			tooltip_text = _tip(p)


func _tip(p: Vector2) -> String:
	if _foot_hit(p) != "":
		return "Ромб события — сюда игра ставит значок события. Тяните вверх-вниз: меняется для всех мест."
	if _handle_hit(p):
		return "Тяните уголок — размер места (Shift — медленнее)"
	var lid := place_at(p)
	if lid != "":
		var t := doc.display_name(lid)
		var h := doc.height_of(lid)
		if h != "":
			t += " — " + str(Words.HEIGHT_SHORT.get(h, h))
		return t
	var si := socket_at(p)
	if si >= 0:
		return "Площадка %d — сюда встают появляющиеся места" % (si + 1)
	return ""


func _coords(m: Vector2) -> void:
	if detailed:
		status.emit("x %.3f  y %.3f" % [m.x, m.y])


func _release() -> void:
	var w := str(_drag.get("what", ""))
	if w in ["move", "resize", "socket", "foot", "rubble"]:
		doc.commit()
		if w == "move":
			status.emit("«%s» сдвинуто." % doc.display_name(str(_drag.id)))
	_drag = {}
	queue_redraw()


func _nudge(key: int, shift: bool) -> void:
	if sel.get("kind", "") != "place" or locked.places:
		return
	var lid := str(sel.id)
	var st := 0.01 if shift else 0.001
	var d: Vector2 = {KEY_LEFT: Vector2(-st, 0), KEY_RIGHT: Vector2(st, 0), KEY_UP: Vector2(0, -st), KEY_DOWN: Vector2(0, st)}[key]
	doc.edit("Сдвинуть место", func() -> void: doc.move_place(lid, doc.at(lid) + d))
	queue_redraw()


func _select(s: Dictionary) -> void:
	sel = s
	selection_changed.emit()
	queue_redraw()


func select_place(lid: String) -> void:
	_select({"kind": "place", "id": lid} if lid != "" else {})


func select_thing(s: Dictionary) -> void:
	_select(s)


func set_tool(t: Tool) -> void:
	tool = t
	path_from = ""
	status.emit(TOOL_HINTS.get(t, ""))
	queue_redraw()


func _route_status() -> void:
	if route_from == "":
		return
	if route_to == "":
		status.emit("Лагерь — «%s». Числа — шагов до каждого места. Щёлкните цель (двойной щелчок — сменить лагерь)." % doc.display_name(route_from))
		return
	var path := sim.route(route_from, route_to)
	if path.is_empty():
		var wet := sim.route(route_from, route_to, false)
		status.emit("До «%s» не дойти%s." % [doc.display_name(route_to), " — путь отрезан водой или нужна лодка" if not wet.is_empty() else " — нет троп"])
		return
	var names := [doc.display_name(route_from)]
	for p: String in path:
		names.append(doc.display_name(p))
	status.emit("От «%s» до «%s» — %s: %s" % [doc.display_name(route_from), doc.display_name(route_to), Words.steps(path.size()), " → ".join(names)])


func route_text() -> String:
	return ""


# --- перетаскивание из пака ----------------------------------------------------------------------

func _can_drop_data(_p: Vector2, data: Variant) -> bool:
	return doc != null and data is Dictionary and data.get("type", "") == "tex"


func _drop_data(p: Vector2, data: Variant) -> void:
	var pk: TexPack = lib.get_pack(str(data.pack))
	if pk == null:
		return
	var nm := str(data.tex)
	var e: Dictionary = pk.textures.get(nm, {})
	var m := to_map(p)
	match str(e.get("kind", "")):
		"place":
			var target := place_at(p)
			if target != "":
				var st := str(e.state)
				doc.edit("Облик места", func() -> void: doc.add_state(target, st, pk.id, nm))
				preview_state[target] = st
				_select({"kind": "place", "id": target})
				status.emit("У «%s» новый облик: %s." % [doc.display_name(target), Words.state(st)])
			else:
				var lid := add_place_from_pack(pk, str(e.place), m)
				preview_state[lid] = str(e.state)
				_select({"kind": "place", "id": lid})
		"base":
			doc.edit("Основа", func() -> void:
				doc.set_source("base", pk.id, nm)
				doc.map["base"] = "base.webp"
				if int(e.get("h", 0)) > 0:
					doc.editor["aspect"] = float(e.w) / float(e.h))
			fit()
			status.emit("Основа карты — «%s» из пака «%s»." % [nm, pk.name])
		"height":
			doc.edit("Карта высот", func() -> void:
				doc.set_source("height", pk.id, nm)
				doc.map["height"] = "height.png"
				if not doc.map.has("water"):
					doc.map["water"] = "water_tile.webp"
				if not doc.map.has("levels"):
					doc.map["levels"] = {"normal": 55, "warn": 68, "flood": 115, "storm": 140})
			status.emit("Карта высот подключена — на карте появилась вода.")
		"tile":
			var slot := "water_tile" if "water" in nm else "fog_tile"
			doc.edit("Плитка", func() -> void:
				doc.set_source(slot, pk.id, nm)
				doc.map["water" if slot == "water_tile" else "fog"] = slot + ".webp")
			status.emit("Плитка %s — «%s»." % ["воды" if slot == "water_tile" else "тумана", nm])
		"decal", "strip", "token":
			var lid2 := place_at(p)
			var pa := path_at(p)
			if lid2 != "":
				doc.edit("Метка у места", func() -> void:
					if not doc.map.has("place_decals"):
						doc.map["place_decals"] = []
					doc.map.place_decals.append({"decal": nm, "place": lid2})
					doc.set_source(nm, pk.id, nm))
				status.emit("Метка у «%s» — условия (фаза, день) настраиваются справа." % doc.display_name(lid2))
			elif not pa.is_empty():
				doc.edit("Полоса на тропе", func() -> void:
					if not doc.map.has("path_decals"):
						doc.map["path_decals"] = []
					doc.map.path_decals.append({"decal": nm, "path": pa})
					doc.set_source(nm, pk.id, nm))
				status.emit("Полоса на тропе.")
			else:
				status.emit("Метку кладут на место или на тропу.")
		_:
			status.emit("Эту картинку нельзя положить на карту.")
	queue_redraw()


## Новое место из места пака: все облики, размер — как у соседей, название — из манифеста или по id.
func add_place_from_pack(pk: TexPack, src_place: String, m: Vector2) -> String:
	var lid := doc.free_id(src_place)
	var sts: Array = pk.places().get(src_place, ["dry"])
	var sz := 0.12
	if not doc.places().is_empty():
		var sum := 0.0
		for x: String in doc.places():
			sum += doc.size_of(x)
		sz = sum / doc.places().size()
	var title := pk.place_name(src_place)
	if title == "":
		title = GameIO.game_place_name(doc.game, src_place)
	if title == "":
		title = src_place.replace("_", " ").capitalize()
	doc.edit("Новое место", func() -> void:
		doc.add_place(lid, m, sz, sts, title)
		for st: String in sts:
			doc.set_source("%s_%s" % [lid, st], pk.id, "%s_%s" % [src_place, st]))
	status.emit("Новое место «%s». Название, высоту и лагерь можно настроить справа." % title)
	return lid


func _place_from_pick(m: Vector2) -> void:
	if pack_pick.is_empty():
		status.emit("Сначала выберите облик места в паке слева (или перетащите его на карту).")
		return
	var pk: TexPack = lib.get_pack(str(pack_pick.pack))
	if pk == null:
		return
	var e: Dictionary = pk.textures.get(str(pack_pick.tex), {})
	if str(e.get("kind", "")) != "place":
		status.emit("Выбранная картинка — не место. Выберите облик места в паке.")
		return
	var lid := add_place_from_pack(pk, str(e.place), m)
	_select({"kind": "place", "id": lid})
