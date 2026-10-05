class_name TexSource
extends RefCounted
## Откуда берётся текстура карты (имя в игре → файл): из пака, указанного в проекте; из папки игры
## art/map/<регион>/ (карта, открытая из игры); или из любого подключённого пака с тем же именем.

var doc: MapDoc
var lib: PackLibrary


func _init(d: MapDoc, l: PackLibrary) -> void:
	doc = d
	lib = l


## {from: pack|game|none, pack, tex, path}
func resolve(game_name: String) -> Dictionary:
	var s := doc.source(game_name)
	if s.has("game_file") and FileAccess.file_exists(str(s.game_file)):
		return {"from": "game", "pack": "", "tex": game_name, "path": str(s.game_file)}
	if not s.is_empty():
		var p: TexPack = lib.get_pack(str(s.get("pack", ""))) if lib != null else null
		if p != null and p.textures.has(str(s.get("tex", ""))):
			return {"from": "pack", "pack": p.id, "tex": str(s.tex), "path": p.disk_path(str(p.textures[str(s.tex)].file))}
	var gp := game_file(game_name)
	if gp != "":
		return {"from": "game", "pack": "", "tex": game_name, "path": gp}
	# общая плитка тумана всех карт-планов (import_map_kit.py копирует её из Берега в каждый регион)
	if s.is_empty() and game_name == "fog_tile" and doc.game != "":
		var common := "%s/art/map/forgotten_shore/fog_tile.webp" % doc.game
		if FileAccess.file_exists(common):
			return {"from": "game", "pack": "", "tex": game_name, "path": common}
	if lib != null and s.is_empty():
		for pid: String in lib.find(game_name):
			var p2: TexPack = lib.get_pack(pid)
			return {"from": "pack", "pack": pid, "tex": game_name, "path": p2.disk_path(str(p2.textures[game_name].file))}
	return {"from": "none", "pack": str(s.get("pack", "")), "tex": str(s.get("tex", game_name)), "path": ""}


func exists(game_name: String) -> bool:
	return resolve(game_name).from != "none"


## Файл в папке картинок региона игры ("" — нет). Имя может быть с расширением (height.png).
func game_file(game_name: String) -> String:
	if doc.game == "" or doc.region == "":
		return ""
	var dir := "%s/art/map/%s/" % [doc.game, doc.region]
	if game_name.get_extension() != "":
		return dir + game_name if FileAccess.file_exists(dir + game_name) else ""
	for ext: String in ["webp", "png"]:
		if FileAccess.file_exists(dir + game_name + "." + ext):
			return dir + game_name + "." + ext
	return ""


## Картинка (полная) или null.
func image(game_name: String) -> Image:
	var r := resolve(game_name)
	match str(r.from):
		"pack":
			return lib.get_pack(str(r.pack)).image(str(r.tex))
		"game":
			return Image.load_from_file(str(r.path))
	return null


## Отпечаток источника — для кэша миниатюр и «только изменённое».
func stamp(game_name: String) -> String:
	var r := resolve(game_name)
	match str(r.from):
		"pack":
			var p: TexPack = lib.get_pack(str(r.pack))
			var e: Dictionary = p.textures[str(r.tex)]
			if p.is_zip:
				return "%s|%s|%d" % [p.root, e.file, FileAccess.get_modified_time(p.root)]
			var f := p.disk_path(str(e.file))
			return "%s|%d" % [f, FileAccess.get_modified_time(f)]
		"game":
			return "%s|%d" % [r.path, FileAccess.get_modified_time(str(r.path))]
	return ""
