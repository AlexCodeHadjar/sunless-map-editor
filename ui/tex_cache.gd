class_name TexCache
extends Node
## Картинки для экрана: миниатюры паков и виньетки на холсте. Раскодирование и уменьшение — в фоне
## (WorkerThreadPool), готовая текстура приходит сигналом ready. Миниатюры кэшируются на диске (user://cache).

signal loaded(key: String)

const DISK := "user://cache"

var _tex: Dictionary = {}      ## ключ → Texture2D
var _wait: Dictionary = {}     ## ключ → id задачи
var _done: Array = []          ## [ключ, Image] — готово в фоне, ждёт главного потока
var _mutex := Mutex.new()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DISK))


## Текстура пака в размере px (по большей стороне). null — ещё грузится (придёт сигнал ready).
func pack_tex(pack: TexPack, nm: String, px: int) -> Texture2D:
	if pack == null or not pack.textures.has(nm):
		return null
	var e: Dictionary = pack.textures[nm]
	var stamp := "%s|%s|%d" % [pack.root, e.file, FileAccess.get_modified_time(pack.root if pack.is_zip else pack.root + "/" + str(e.file))]
	var key := "%s@%d" % [stamp.md5_text(), px]
	if _tex.has(key):
		return _tex[key]
	if not _wait.has(key):
		var disk := "%s/%s.webp" % [DISK, key.replace("@", "_")]
		_wait[key] = WorkerThreadPool.add_task(_load_job.bind(key, pack, nm, px, disk))
	return null


## Текстура карты по имени в игре (через TexSource).
func map_tex(src: TexSource, game_name: String, px: int) -> Texture2D:
	if src == null:
		return null
	var r := src.resolve(game_name)
	match str(r.from):
		"pack":
			return pack_tex(src.lib.get_pack(str(r.pack)), str(r.tex), px)
		"game":
			var key := "%s@%d" % [(str(r.path) + str(FileAccess.get_modified_time(str(r.path)))).md5_text(), px]
			if _tex.has(key):
				return _tex[key]
			if not _wait.has(key):
				var disk := "%s/%s.webp" % [DISK, key.replace("@", "_")]
				_wait[key] = WorkerThreadPool.add_task(_load_file_job.bind(key, str(r.path), px, disk))
			return null
	return null


func is_loading() -> bool:
	return not _wait.is_empty()


func _load_job(key: String, pack: TexPack, nm: String, px: int, disk: String) -> void:
	var img: Image = null
	if FileAccess.file_exists(disk):
		img = Image.load_from_file(disk)
	if img == null:
		img = pack.image(nm)
		img = _shrink(img, px)
		if img != null and px <= 256:
			img.save_webp(disk, false)
	_mutex.lock()
	_done.append([key, img])
	_mutex.unlock()


func _load_file_job(key: String, path: String, px: int, disk: String) -> void:
	var img: Image = null
	if FileAccess.file_exists(disk):
		img = Image.load_from_file(disk)
	if img == null:
		img = _shrink(Image.load_from_file(path), px)
		if img != null and px <= 256:
			img.save_webp(disk, false)
	_mutex.lock()
	_done.append([key, img])
	_mutex.unlock()


static func _shrink(img: Image, px: int) -> Image:
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var s := float(px) / float(maxi(w, h))
	if s < 1.0:
		img.resize(maxi(1, int(w * s)), maxi(1, int(h * s)), Image.INTERPOLATE_LANCZOS)
	return img


func _process(_d: float) -> void:
	if _done.is_empty():
		return
	_mutex.lock()
	var batch := _done.duplicate()
	_done.clear()
	_mutex.unlock()
	for it: Array in batch:
		var key: String = it[0]
		if _wait.has(key):
			WorkerThreadPool.wait_for_task_completion(_wait[key])
			_wait.erase(key)
		var img: Image = it[1]
		_tex[key] = ImageTexture.create_from_image(img) if img != null else null
		loaded.emit(key)


## Полная картинка карты высот как текстура (для воды в предпросмотре).
func full_tex(src: TexSource, game_name: String) -> Texture2D:
	var key := "full:" + game_name + ":" + src.stamp(game_name)
	if _tex.has(key):
		return _tex[key]
	var img := src.image(game_name)
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	_tex[key] = ImageTexture.create_from_image(img)
	return _tex[key]


func clear() -> void:
	_tex.clear()
