class_name TexPack
extends RefCounted
## Пак текстур (ТЗ §3): папка или .zip с манифестом pack.json. Если манифеста нет — он строится по папкам
## и именам файлов (auto_manifest), и его можно сохранить.
##
## Текстура пака: {name, kind, file, place, state, w, h, alpha, tags}
##   name  — имя, по которому её ищет карта игры (<место>_<облик>, decal_…, base);
##   kind  — base | height | place | decal | strip | tile | token | tech;
##   file  — путь внутри пака (через «/»).

const KINDS := ["base", "height", "place", "decal", "strip", "tile", "token", "tech"]
const KIND_NAMES := {"base": "Основы", "height": "Карты высот", "place": "Места", "decal": "Метки", "strip": "Полосы",
	"tile": "Плитки", "token": "Фишки", "tech": "Служебные"}
const IMAGE_EXT := ["png", "webp", "jpg", "jpeg"]
## Папки, которые не являются текстурами пака: превью, справка, копии с хромакеем.
const SKIP_DIRS := ["chroma", "reference", "previews", "preview", ".git", ".godot", "__pycache__"]
## Облики мест, которые встречаются в картах игры: по ним плоские имена делятся на «место_облик».
const STATES := ["abandoned", "active", "alarm", "awake", "banner", "barricaded", "beacon", "blood", "boat_ready", "bonfire",
	"breached", "broken", "buried", "burned", "burning", "busy", "charmed", "cleared", "closed", "closed_night", "collapsed",
	"cracked", "crowded", "damaged", "dim", "dormant", "dry", "dry_b", "dry_c", "dug", "empty", "fight", "flooded", "found",
	"fresh", "fresh_graves", "glowing", "hidden", "hunted", "infested", "leak", "lit", "lockdown", "molting", "night_glow",
	"occupied", "old", "open", "opened", "overcrowded", "picked", "ravaged", "red", "repair", "restored", "ruined", "sealed",
	"siege", "signal", "silt", "statues_moved", "storm", "temporary", "wrath"]

var id := ""
var name := ""
var version := 1
var region := ""
var style := ""
var root := ""            ## путь к папке или .zip
var is_zip := false
var has_manifest := false  ## pack.json был в паке
var manifest: Dictionary = {}
var textures: Dictionary = {}   ## имя → запись
var preview := ""          ## файл обложки внутри пака
var errors: Array = []

var _zip: ZIPReader
var _zip_prefix := ""
var _img_cache: Dictionary = {}


## Открыть пак по пути (папка или .zip). Ошибки — в errors, пак всё равно возвращается.
static func open(path: String) -> TexPack:
	var p := TexPack.new()
	p.root = path.replace("\\", "/").trim_suffix("/")
	p.is_zip = p.root.get_extension().to_lower() == "zip"
	p._scan()
	return p


func files() -> PackedStringArray:
	var out := PackedStringArray()
	if is_zip:
		if _zip == null:
			return out
		for f: String in _zip.get_files():
			if f.ends_with("/") or not f.begins_with(_zip_prefix):
				continue
			out.append(f.substr(_zip_prefix.length()))
		return out
	_walk(root, "", out)
	return out


func _walk(dir: String, rel: String, out: PackedStringArray) -> void:
	for f: String in DirAccess.get_files_at(dir):
		out.append(rel + f)
	for d: String in DirAccess.get_directories_at(dir):
		_walk(dir + "/" + d, rel + d + "/", out)


func read_bytes(file: String) -> PackedByteArray:
	if is_zip:
		if _zip == null or not _zip.file_exists(_zip_prefix + file):
			return PackedByteArray()
		return _zip.read_file(_zip_prefix + file)
	if not FileAccess.file_exists(root + "/" + file):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(root + "/" + file)


## Полный путь файла на диске ("" — файл внутри zip).
func disk_path(file: String) -> String:
	return "" if is_zip else root + "/" + file


func _head(file: String) -> PackedByteArray:
	if is_zip:
		var b := read_bytes(file)
		return b
	var f := FileAccess.open(root + "/" + file, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var n := mini(f.get_length(), 65536 if file.get_extension().to_lower() in ["jpg", "jpeg"] else 64)
	var h := f.get_buffer(n)
	f.close()
	return h


func _scan() -> void:
	errors.clear()
	textures.clear()
	if is_zip:
		_zip = ZIPReader.new()
		var err := _zip.open(root)
		if err != OK:
			errors.append("не открыть архив %s (%s)" % [root, error_string(err)])
			_zip = null
			return
		# архив с одной папкой внутри — пак внутри неё
		var tops := {}
		for f: String in _zip.get_files():
			tops[f.split("/")[0]] = true
		if tops.size() == 1 and not _zip.file_exists("pack.json"):
			var top: String = tops.keys()[0]
			if Array(_zip.get_files()).any(func(x: String) -> bool: return x.begins_with(top + "/")):
				_zip_prefix = top + "/"
	elif not DirAccess.dir_exists_absolute(root):
		errors.append("нет папки " + root)
		return
	var raw: PackedByteArray = read_bytes("pack.json")
	if raw.size() > 0:
		var m: Variant = JsonX.parse(raw.get_string_from_utf8())
		if m is Dictionary:
			manifest = m
			has_manifest = true
		else:
			errors.append("pack.json: " + JsonX.last_error)
	if not has_manifest:
		manifest = auto_manifest()
	_apply_manifest()


## Имя пака по умолчанию — по имени папки или архива (латиница, подчёркивания).
func default_id() -> String:
	var base := root.get_file().get_basename() if is_zip else root.get_file()
	return slug(base)


static func slug(s: String) -> String:
	var tr := {"а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z", "и": "i", "й": "i",
		"к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h",
		"ц": "c", "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya"}
	var out := ""
	for ch in s.to_lower():
		if tr.has(ch):
			out += tr[ch]
		elif (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		else:
			out += "_"
	while "__" in out:
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_")
	return out if out != "" else "pack"


## Манифест по папкам и именам файлов (ТЗ §3.1). Раскладка:
##   base/ — основы (height* — карта высот); places/<место>/<облик>.png; decals/; strips/; tiles/; tokens/<id>_<1-4>.png;
##   иначе (плоская папка) — по имени: base*, height*, *_tile, decal_*, <место>_<облик>.
func auto_manifest() -> Dictionary:
	var tex := {}
	var flat: Array = []   # [имя, файл, info] — кандидаты в «место_облик»
	var cover := ""
	var seen_names := {}
	for f: String in files():
		var ext := f.get_extension().to_lower()
		if not ext in IMAGE_EXT:
			continue
		var parts := f.split("/")
		if Array(parts.slice(0, parts.size() - 1)).any(func(d: String) -> bool: return d.to_lower() in SKIP_DIRS):
			continue
		var stem := f.get_file().get_basename()
		if parts.size() == 1 and (stem.to_lower() in ["preview", "cover"] or stem.to_lower().begins_with("preview_")):
			cover = f
			continue
		var info := ImgInfo.from_bytes(_head(f))
		var dirs: Array = Array(parts.slice(0, parts.size() - 1)).map(func(d: String) -> String: return d.to_lower())
		var e := {"file": f}
		if dirs.has("places") and dirs.size() >= dirs.find("places") + 2:
			var place: String = parts[dirs.find("places") + 1]
			var st := stem.trim_prefix(place + "_") if stem.begins_with(place + "_") else stem
			e.merge({"kind": "place", "place": place, "state": st})
			_put(tex, seen_names, place + "_" + st, e)
			continue
		if dirs.has("tokens"):
			e["kind"] = "token"
			_put(tex, seen_names, stem, e)
			continue
		if dirs.has("tiles"):
			e["kind"] = "tile"
			_put(tex, seen_names, stem, e)
			continue
		if dirs.has("strips") or dirs.has("roads"):
			e["kind"] = "strip"
			_put(tex, seen_names, stem, e)
			continue
		if dirs.has("decals"):
			e["kind"] = "strip" if int(info.w) >= 3 * maxi(1, int(info.h)) else "decal"
			_put(tex, seen_names, stem, e)
			continue
		if dirs.has("base"):
			e["kind"] = "height" if "height" in stem.to_lower() else "base"
			_put(tex, seen_names, stem, e)
			continue
		var k := guess_kind(stem, info)
		if k == "":
			flat.append([stem, f, info])
			continue
		e["kind"] = k
		_put(tex, seen_names, stem, e)
	# плоские имена: место — у кого есть <место>_dry; иначе — по известному облику в конце имени
	var places := {}
	for it: Array in flat:
		var stem2: String = it[0]
		if stem2.ends_with("_dry"):
			places[stem2.trim_suffix("_dry")] = true
	var rest: Array = []
	for it: Array in flat:
		var stem3: String = it[0]
		var best := ""
		for pl: String in places:
			if stem3.begins_with(pl + "_") and pl.length() > best.length():
				best = pl
		if best == "":
			rest.append(it)
			continue
		_put(tex, seen_names, stem3, {"file": it[1], "kind": "place", "place": best, "state": stem3.substr(best.length() + 1)})
	# по словарю обликов: два и больше файлов с общим началом и известным концом — облики одного места
	var groups := {}
	for it: Array in rest:
		var sp := split_state(it[0])
		if sp.is_empty():
			continue
		if not groups.has(sp[0]):
			groups[sp[0]] = []
		groups[sp[0]].append([it, sp[1]])
	for it: Array in rest:
		var stem4: String = it[0]
		var sp2 := split_state(stem4)
		# известный облик в конце имени — облик места (даже одиночный: centurion_gate_molting дополняет место другого пака)
		if not sp2.is_empty():
			_put(tex, seen_names, stem4, {"file": it[1], "kind": "place", "place": sp2[0], "state": sp2[1]})
		else:
			var info2: Dictionary = it[2]
			var k2 := "strip" if int(info2.w) >= 3 * maxi(1, int(info2.h)) else "decal"
			_put(tex, seen_names, stem4, {"file": it[1], "kind": k2})
	var m := {"id": default_id(), "name": root.get_file().get_basename() if is_zip else root.get_file(), "version": 1}
	if cover != "":
		m["preview"] = cover
	m["textures"] = tex
	return m


## Повтор имени (base.png и base.webp) — берём PNG (без потерь), остальное помним как дубль.
func _put(tex: Dictionary, seen: Dictionary, nm: String, e: Dictionary) -> void:
	if tex.has(nm):
		var old_ext := str(tex[nm]["file"]).get_extension().to_lower()
		var new_ext := str(e["file"]).get_extension().to_lower()
		if old_ext == "png" or new_ext != "png":
			return
	tex[nm] = e
	seen[nm] = true


## Вид текстуры по имени (плоская папка). "" — кандидат в облик места.
static func guess_kind(stem: String, info: Dictionary) -> String:
	var s := stem.to_lower()
	if s == "base" or s.begins_with("base_") or s.ends_with("_base"):
		return "base"
	if s.begins_with("height") or s.ends_with("_height") or s.begins_with("height_"):
		return "height"
	if s in ["zones", "districts", "height_zones"] or s.ends_with("_mask") or s.ends_with("_zones"):
		return "tech"
	if s.begins_with("tile_") or s.ends_with("_tile") or s == "crimson_haze" or s.ends_with("_haze"):
		return "tile"
	if s.begins_with("token_") or s.begins_with("decal_token_"):
		return "decal" if s.begins_with("decal_") else "token"
	if s.begins_with("decal_") or s.begins_with("ally_") or s.begins_with("party_") or s.begins_with("road_") or s.ends_with("_strip"):
		return "strip" if int(info.get("w", 0)) >= 3 * maxi(1, int(info.get("h", 1))) else "decal"
	if int(info.get("w", 0)) >= 3 * maxi(1, int(info.get("h", 1))):
		return "strip"
	if int(info.get("w", 0)) >= 2000 and int(info.get("w", 0)) >= 2 * int(info.get("h", 1)) - 2:
		return "base"
	return ""


## «coral_maze_dry_b» → ["coral_maze", "dry_b"] по словарю обликов; [] — не делится.
static func split_state(stem: String) -> Array:
	var best: Array = []
	for st: String in STATES:
		if stem.ends_with("_" + st) and stem.length() > st.length() + 1:
			if best.is_empty() or st.length() > str(best[1]).length():
				best = [stem.substr(0, stem.length() - st.length() - 1), st]
	return best


func _apply_manifest() -> void:
	id = str(manifest.get("id", default_id()))
	if id == "":
		id = default_id()
	name = str(manifest.get("name", id))
	version = int(manifest.get("version", 1))
	region = str(manifest.get("region", ""))
	style = str(manifest.get("style", ""))
	preview = str(manifest.get("preview", ""))
	if preview == "":
		for f: String in ["preview.png", "preview.webp", "preview.jpg"]:
			if not read_bytes(f).is_empty():
				preview = f
				break
	var tex: Dictionary = manifest.get("textures", {})
	if tex.is_empty():
		# манифест по ТЗ без списка текстур — список строится по папкам, поля манифеста дополняют его
		tex = auto_manifest().get("textures", {})
	for nm: String in tex:
		var e: Dictionary = Dictionary(tex[nm]).duplicate()
		e["name"] = nm
		if not e.has("kind"):
			e["kind"] = "decal"
		if not e.has("w"):
			var info := ImgInfo.from_bytes(_head(str(e.get("file", ""))))
			e["w"] = info.w
			e["h"] = info.h
			e["alpha"] = info.alpha
			e["ok"] = info.ok
		textures[nm] = e
	# places из манифеста: теги, названия, облик по умолчанию
	var mp: Dictionary = manifest.get("places", {})
	for pl: String in mp:
		for st: String in Array(mp[pl].get("states", [])):
			var nm2 := pl + "_" + st
			if textures.has(nm2):
				textures[nm2]["place"] = pl
				textures[nm2]["state"] = st
				textures[nm2]["kind"] = "place"
	for key: String in ["decals", "strips", "tokens"]:
		var md: Dictionary = manifest.get(key, {})
		for nm3: String in md:
			if textures.has(nm3) and md[nm3] is Dictionary:
				textures[nm3]["tags"] = md[nm3].get("tags", [])
				textures[nm3]["text"] = md[nm3].get("text", "")


## Места пака: {место: [облики]} (облики в порядке: dry первым).
func places() -> Dictionary:
	var out := {}
	for nm: String in textures:
		var e: Dictionary = textures[nm]
		if e.kind != "place":
			continue
		var pl := str(e.get("place", ""))
		if not out.has(pl):
			out[pl] = []
		out[pl].append(str(e.get("state", "")))
	for pl: String in out:
		var a: Array = out[pl]
		a.sort()
		if a.has("dry"):
			a.erase("dry")
			a.push_front("dry")
	return out


## Облик места по умолчанию: из манифеста, dry или первый.
func default_state(place: String) -> String:
	var d := str(manifest.get("places", {}).get(place, {}).get("default", ""))
	var st: Array = places().get(place, [])
	if d != "" and st.has(d):
		return d
	return "dry" if st.has("dry") else (str(st[0]) if not st.is_empty() else "dry")


func place_name(place: String) -> String:
	return str(manifest.get("places", {}).get(place, {}).get("name", ""))


func tags_of(nm: String) -> Array:
	var e: Dictionary = textures.get(nm, {})
	var out: Array = Array(e.get("tags", []))
	if e.get("kind", "") == "place":
		out.append_array(manifest.get("places", {}).get(str(e.get("place", "")), {}).get("tags", []))
	return out


func count_by_kind() -> Dictionary:
	var out := {}
	for k: String in KINDS:
		out[k] = 0
	for nm: String in textures:
		var k2 := str(textures[nm].kind)
		out[k2] = int(out.get(k2, 0)) + 1
	return out


## Полная картинка текстуры (кэш на время сеанса для небольших; основы не кэшируются).
func image(nm: String) -> Image:
	if _img_cache.has(nm):
		return _img_cache[nm]
	var e: Dictionary = textures.get(nm, {})
	if e.is_empty():
		return null
	var f := str(e.file)
	var img := ImgInfo.decode(read_bytes(f), f.get_extension())
	if img != null and img.get_width() <= 1024:
		_img_cache[nm] = img
	return img


func file_bytes(nm: String) -> PackedByteArray:
	var e: Dictionary = textures.get(nm, {})
	return PackedByteArray() if e.is_empty() else read_bytes(str(e.file))


## Отпечаток содержимого (для «только изменённое» и обновлений пака).
func file_hash(nm: String) -> String:
	var b := file_bytes(nm)
	if b.is_empty():
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(b)
	return ctx.finish().hex_encode()


## Манифест для сохранения (pack.json по ТЗ + список textures, чтобы разбор имён не повторялся).
func manifest_to_save() -> Dictionary:
	var m := {"id": id, "name": name, "version": version}
	if region != "":
		m["region"] = region
	if style != "":
		m["style"] = style
	if preview != "":
		m["preview"] = preview
	var pl := {}
	var pls := places()
	for p: String in pls:
		pl[p] = {"states": pls[p], "default": default_state(p)}
		var nm := place_name(p)
		if nm != "":
			pl[p]["name"] = nm
	m["places"] = pl
	var tex := {}
	for nm2: String in textures:
		var e: Dictionary = textures[nm2]
		var o := {"kind": e.kind, "file": e.file}
		if e.has("place"):
			o["place"] = e.place
			o["state"] = e.state
		if not Array(e.get("tags", [])).is_empty():
			o["tags"] = e.tags
		tex[nm2] = o
	m["textures"] = tex
	return m


## Записать pack.json в папку пака (у архива — нельзя). "" или текст ошибки.
func save_manifest() -> String:
	if is_zip:
		return "манифест внутри .zip не сохранить — распакуйте пак в папку"
	var err := JsonX.write_file(root + "/pack.json", manifest_to_save())
	if err == "":
		has_manifest = true
		manifest = manifest_to_save()
	return err
