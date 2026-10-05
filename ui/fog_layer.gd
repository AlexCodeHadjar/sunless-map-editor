class_name FogLayer
extends Node
## Туман неизвестного как в игре (SleeperMap: sleeper_fog + sleeper_fog_mask): открыты круги вокруг известных мест,
## середины треугольников из открытых соседей и коридоры между ними. Маска считается в своей текстуре и только при изменениях;
## сам туман рисуется в свою текстуру (texture()), холст кладёт её между местами и подписями.

const REVEAL_R := 0.17

var _vp: SubViewport
var _mask: ColorRect
var _fog_vp: SubViewport
var _fog: ColorRect
var material: ShaderMaterial
var _last: Array = []


func texture() -> Texture2D:
	return _fog_vp.get_texture()


func _ready() -> void:
	var fm := ShaderMaterial.new()
	fm.shader = load("res://ui/shaders/fog.gdshader")
	material = fm
	_fog_vp = SubViewport.new()
	_fog_vp.disable_3d = true
	_fog_vp.transparent_bg = true
	_fog_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_fog_vp)
	_fog = ColorRect.new()
	_fog.material = fm
	_fog_vp.add_child(_fog)
	_vp = SubViewport.new()
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	_mask = ColorRect.new()
	var mm := ShaderMaterial.new()
	mm.shader = load("res://ui/shaders/fog_mask.gdshader")
	_mask.material = mm
	_vp.add_child(_mask)
	fm.set_shader_parameter("mask", _vp.get_texture())


## known — открытые места, centers — их точки в долях основы, links — тропы сейчас.
func update(rect: Rect2, aspect: float, fog_tex: Texture2D, known: Array, centers: Dictionary, links: Array) -> void:
	var fm := material
	fm.set_shader_parameter("fog_tex", fog_tex)
	fm.set_shader_parameter("aspect", aspect)
	var vs := Vector2i(clampi(int(rect.size.x / 2.0), 16, 2048), clampi(int(rect.size.y / 2.0), 8, 1024))
	if _vp.size != vs:
		_vp.size = vs
		_mask.size = Vector2(vs)
		_fog_vp.size = vs
		_fog.size = Vector2(vs)
		_last = []
	var pairs := {}
	for pr: Array in links:
		if known.has(pr[0]) and known.has(pr[1]):
			pairs[_key(str(pr[0]), str(pr[1]))] = [str(pr[0]), str(pr[1])]
	for i in known.size():
		for j in range(i + 1, known.size()):
			var pa: Vector2 = centers[known[i]]
			var pb: Vector2 = centers[known[j]]
			if Vector2((pa.x - pb.x) * aspect, pa.y - pb.y).length() < REVEAL_R * 3.0:
				pairs[_key(known[i], known[j])] = [known[i], known[j]]
	var nb := {}
	for pr2: Array in pairs.values():
		for k in 2:
			if not nb.has(pr2[k]):
				nb[pr2[k]] = []
			(nb[pr2[k]] as Array).append(pr2[1 - k])
	var holes := PackedVector4Array()
	for lid: String in known:
		if holes.size() < 40:
			var a: Vector2 = centers[lid]
			holes.append(Vector4(a.x, a.y, REVEAL_R, 1.0))
	for pr3: Array in pairs.values():
		var x: String = pr3[0] if str(pr3[0]) < str(pr3[1]) else pr3[1]
		var y: String = pr3[1] if str(pr3[0]) < str(pr3[1]) else pr3[0]
		for z: String in nb.get(x, []):
			if z > y and (nb.get(y, []) as Array).has(z) and holes.size() < 48:
				var c: Vector2 = (Vector2(centers[x]) + Vector2(centers[y]) + Vector2(centers[z])) / 3.0
				var rr := 0.0
				for v: String in [x, y, z]:
					var pv: Vector2 = centers[v]
					rr = maxf(rr, Vector2((pv.x - c.x) * aspect, pv.y - c.y).length())
				holes.append(Vector4(c.x, c.y, minf(rr * 0.85, REVEAL_R * 2.5), 1.0))
	var segs := PackedVector4Array()
	var sw := PackedVector2Array()
	for pr4: Array in pairs.values():
		if segs.size() >= 64:
			break
		var p0: Vector2 = centers[pr4[0]]
		var p1: Vector2 = centers[pr4[1]]
		segs.append(Vector4(p0.x, p0.y, p1.x, p1.y))
		sw.append(Vector2(REVEAL_R * 0.75, 1.0))
	if _last != [holes, segs, sw]:
		_last = [holes, segs, sw]
		var mm := _mask.material as ShaderMaterial
		mm.set_shader_parameter("aspect", aspect)
		mm.set_shader_parameter("holes", holes)
		mm.set_shader_parameter("hole_count", holes.size())
		mm.set_shader_parameter("segs", segs)
		mm.set_shader_parameter("seg_w", sw)
		mm.set_shader_parameter("seg_count", segs.size())
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


static func _key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a
