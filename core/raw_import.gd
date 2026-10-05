class_name RawImport
extends RefCounted
## Импорт «сырых» картинок из генерации (ФТ-06) в пак «Мои текстуры»: вид, имя места и облик, обрезка пустых краёв,
## место по центру квадрата, убрать пурпурный фон-хромакей; обрезка подставки у фишек (ФТ-07).

const PACK_ID := "my_textures"
const PACK_NAME := "Мои текстуры"
const SIDE := {"place": 1024, "decal": 512, "token": 512, "tile": 512}


static func pack_dir() -> String:
	return ProjectSettings.globalize_path("user://my_textures")


## Пурпурный фон (#FF00FF и близкие) → прозрачность с мягким краем.
static func remove_chroma(img: Image) -> Image:
	var out: Image = img.duplicate()
	out.convert(Image.FORMAT_RGBA8)
	for y in out.get_height():
		for x in out.get_width():
			var c: Color = out.get_pixel(x, y)
			# «пурпурность»: красный и синий высокие, зелёный низкий
			var m := minf(c.r, c.b) - c.g
			if m > 0.45:
				c.a = 0.0
			elif m > 0.25:
				c.a *= 1.0 - (m - 0.25) / 0.2
				c.r = c.g + (c.r - c.g) * 0.5
				c.b = c.g + (c.b - c.g) * 0.5
			out.set_pixel(x, y, c)
	return out


## Квадрат с картинкой по центру: пустые (прозрачные) края обрезаются, поле — margin от стороны.
static func center_square(img: Image, side: int, margin: float = 0.05) -> Image:
	var src: Image = img.duplicate()
	src.convert(Image.FORMAT_RGBA8)
	var used: Rect2i = src.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		used = Rect2i(Vector2i.ZERO, src.get_size())
	var part: Image = src.get_region(used)
	var inner := int(side * (1.0 - 2.0 * margin))
	var s := float(inner) / float(maxi(part.get_width(), part.get_height()))
	part.resize(maxi(1, int(part.get_width() * s)), maxi(1, int(part.get_height() * s)), Image.INTERPOLATE_LANCZOS)
	var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blend_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), (Vector2i(side, side) - part.get_size()) / 2)
	return out


## Обрезка подставки у фишки (как tools/clean_wanderer_tokens.py, упрощённо): нижняя часть картинки
## с землистыми (мало насыщенными тёмными) пикселями становится прозрачной. strength 0..1 — сколько снизу трогать.
static func cut_base(img: Image, strength: float = 0.5) -> Image:
	var out: Image = img.duplicate()
	out.convert(Image.FORMAT_RGBA8)
	var h: int = out.get_height()
	var from := int(h * (1.0 - 0.35 * clampf(strength, 0.0, 1.0)))
	for y in range(from, h):
		var k := float(y - from) / maxf(1.0, float(h - from))
		for x in out.get_width():
			var c: Color = out.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var sat: float = c.s
			if sat < 0.35 and c.v < 0.6:
				c.a *= clampf(1.0 - k * 1.6, 0.0, 1.0)
				out.set_pixel(x, y, c)
	return out


## Готовая картинка для пака по виду.
static func prepare(img: Image, kind: String, crop: bool, chroma: bool) -> Image:
	var im: Image = img.duplicate()
	if im.is_compressed():
		im.decompress()
	if chroma:
		im = remove_chroma(im)
	if kind in ["place", "decal", "token"] and crop:
		return center_square(im, SIDE[kind])
	return im


## Куда сохранить в пак: places/<место>/<облик>.png, decals/<имя>.png, base/…, tiles/…, tokens/…
static func rel_path(kind: String, name: String, state: String) -> String:
	match kind:
		"place":
			return "places/%s/%s.png" % [TexPack.slug(name), TexPack.slug(state)]
		"decal":
			var n := TexPack.slug(name)
			return "decals/%s.png" % (n if n.begins_with("decal_") else "decal_" + n)
		"strip":
			return "strips/%s.png" % TexPack.slug(name)
		"base":
			return "base/%s.png" % TexPack.slug(name)
		"height":
			return "base/height_%s.png" % TexPack.slug(name).trim_prefix("height_")
		"tile":
			return "tiles/%s.png" % TexPack.slug(name)
		"token":
			return "tokens/%s.png" % TexPack.slug(name)
	return "%s.png" % TexPack.slug(name)


## Сохранить в «Мои текстуры». Возвращает "" или текст ошибки.
static func save(img: Image, kind: String, name: String, state: String, dir: String = "") -> String:
	if dir == "":
		dir = pack_dir()
	var rel := rel_path(kind, name, state)
	var path := dir + "/" + rel
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if not FileAccess.file_exists(dir + "/pack.json"):
		JsonX.write_file(dir + "/pack.json", {"id": PACK_ID, "name": PACK_NAME, "version": 1})
	var err := img.save_png(path)
	return "" if err == OK else "не записать %s (%s)" % [path, error_string(err)]
