class_name TexturePreview
extends Control
## Крупный предпросмотр текстуры: прозрачность видна на шахматке; «на основе» — поверх основы текущей карты.

var on_base := false
var _cache: TexCache
var _pack: TexPack
var _name := ""
var _canvas: MapCanvas


func set_tex(c: TexCache, p: TexPack, nm: String, cv: MapCanvas) -> void:
	_cache = c
	_pack = p
	_name = nm
	_canvas = cv
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.09, 0.095, 0.11))
	if _pack == null:
		draw_string(UiTheme.font(), Vector2(10, size.y / 2), "Выберите текстуру — она будет видна здесь крупно", HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 13, UiTheme.DIM)
		return
	var tex := _cache.pack_tex(_pack, _name, 512)
	var fit := r
	if tex != null:
		var ts := tex.get_size()
		var s := minf(size.x / ts.x, size.y / ts.y)
		fit = Rect2((size - ts * s) / 2.0, ts * s)
	if on_base and _canvas != null and _canvas.doc != null:
		var base := _cache.map_tex(_canvas.src, "base", 4096)
		if base != null:
			# кусок основы вокруг середины карты в масштабе места среднего размера
			var bs := base.get_size()
			var cut := bs.x * 0.14
			draw_texture_rect_region(base, fit, Rect2(bs / 2.0 - Vector2(cut, cut * fit.size.y / maxf(fit.size.x, 1)) / 2.0, Vector2(cut, cut * fit.size.y / maxf(fit.size.x, 1))))
	else:
		var cell := 12.0
		var y := fit.position.y
		var row := 0
		while y < fit.end.y:
			var x := fit.position.x + (cell if row % 2 == 1 else 0.0)
			while x < fit.end.x:
				draw_rect(Rect2(Vector2(x, y), Vector2(cell, cell)).intersection(fit), Color(0.32, 0.33, 0.36))
				x += cell * 2.0
			y += cell
			row += 1
	if tex != null:
		draw_texture_rect(tex, fit, false)
