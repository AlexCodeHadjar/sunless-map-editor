class_name GameView
extends Window
## Режим «Игра» (ФТ-40): окно 16:9 — карта, как игрок увидит её при старте главы: основа закрывает окно с запасом zoom,
## сверху спрятано view_top, ромбы событий в точках foot, фигура у лагеря, туман вокруг неизвестного.
## Мышью карту можно сдвигать в пределах запаса — как в игре.

var canvas: MapCanvas
var camp := ""
var _drag := {}


static func open_for(parent: Node, doc: MapDoc, src: TexSource, cache: TexCache, lib: PackLibrary, camp_id: String, fog: bool) -> GameView:
	var w := GameView.new()
	w.title = "Как увидит игрок — 1920×1080 (уменьшено)"
	w.size = Vector2i(1280, 720)
	w.min_size = Vector2i(640, 360)
	w.close_requested.connect(w.queue_free)
	parent.add_child(w)
	w.build(doc, src, cache, lib, camp_id, fog)
	w.popup_centered()
	return w


func build(doc: MapDoc, src: TexSource, cache: TexCache, lib: PackLibrary, camp_id: String, fog: bool) -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	canvas = MapCanvas.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.game_mode = true
	add_child(canvas)
	canvas.setup(doc, src, cache, lib)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camp = camp_id
	canvas.step_from = ""
	canvas.camp = camp
	canvas.layers.sockets = false
	canvas.layers.foot = false
	if fog and camp != "":
		canvas.sim.visited = [camp]
		canvas.modes.fog = true
	size_changed.connect(_layout)
	_layout.call_deferred()


## Как SleeperMap._fit + set_pan при старте: основа ≥ окна × zoom, по центру, сверху спрятано view_top.
func _layout() -> void:
	canvas.game_layout(Vector2(size))


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = {"start": ev.position, "pan": canvas.pan} if ev.pressed else {}
	elif ev is InputEventMouseMotion and not _drag.is_empty():
		var view := Vector2(size)
		var bs := Vector2(canvas.base_px, canvas.base_px / canvas.doc.base_aspect())
		var lo := view - bs
		var p: Vector2 = Vector2(_drag.pan) + (ev.position - Vector2(_drag.start))
		canvas.pan = Vector2(clampf(p.x, minf(lo.x, 0.0), 0.0), clampf(p.y, minf(lo.y, 0.0), 0.0))
		canvas.queue_redraw()
