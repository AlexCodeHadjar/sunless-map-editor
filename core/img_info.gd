class_name ImgInfo
extends RefCounted
## Размер и прозрачность картинки по заголовку файла — без раскодирования (быстро для сотен текстур пака).
## Возвращает {w, h, alpha, ok}; alpha: true — есть канал прозрачности, false — нет, null — неизвестно.


static func from_bytes(head: PackedByteArray) -> Dictionary:
	if head.size() >= 26 and head[0] == 0x89 and head[1] == 0x50 and head[2] == 0x4E and head[3] == 0x47:
		var w := _be32(head, 16)
		var h := _be32(head, 20)
		var ct := head[25]
		# 4 — серый с альфой, 6 — RGBA; 3 — палитра (прозрачность может быть в tRNS — считаем «да»)
		return {"w": w, "h": h, "alpha": ct == 4 or ct == 6 or ct == 3, "ok": true, "format": "png", "bits": head[24], "gray": ct == 0 or ct == 4}
	if head.size() >= 30 and head.slice(0, 4).get_string_from_ascii() == "RIFF" and head.slice(8, 12).get_string_from_ascii() == "WEBP":
		var fourcc := head.slice(12, 16).get_string_from_ascii()
		if fourcc == "VP8X":
			var w2 := 1 + (head[24] | (head[25] << 8) | (head[26] << 16))
			var h2 := 1 + (head[27] | (head[28] << 8) | (head[29] << 16))
			return {"w": w2, "h": h2, "alpha": (head[20] & 0x10) != 0, "ok": true, "format": "webp"}
		if fourcc == "VP8L":
			var b0 := head[21]
			var b1 := head[22]
			var b2 := head[23]
			var b3 := head[24]
			var w3 := 1 + (b0 | ((b1 & 0x3F) << 8))
			var h3 := 1 + ((b1 >> 6) | (b2 << 2) | ((b3 & 0x0F) << 10))
			return {"w": w3, "h": h3, "alpha": ((b3 >> 4) & 1) == 1, "ok": true, "format": "webp"}
		if fourcc == "VP8 ":
			var w4 := (head[26] | (head[27] << 8)) & 0x3FFF
			var h4 := (head[28] | (head[29] << 8)) & 0x3FFF
			return {"w": w4, "h": h4, "alpha": false, "ok": true, "format": "webp"}
	if head.size() >= 4 and head[0] == 0xFF and head[1] == 0xD8:
		var i := 2
		while i + 9 < head.size():
			if head[i] != 0xFF:
				i += 1
				continue
			var marker := head[i + 1]
			var seg := (head[i + 2] << 8) | head[i + 3]
			if marker >= 0xC0 and marker <= 0xCF and marker != 0xC4 and marker != 0xC8 and marker != 0xCC:
				return {"w": (head[i + 7] << 8) | head[i + 8], "h": (head[i + 5] << 8) | head[i + 6], "alpha": false, "ok": true, "format": "jpg"}
			i += 2 + seg
		return {"w": 0, "h": 0, "alpha": false, "ok": false, "format": "jpg"}
	return {"w": 0, "h": 0, "alpha": null, "ok": false, "format": ""}


static func from_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"w": 0, "h": 0, "alpha": null, "ok": false, "format": ""}
	# у JPEG размер может лежать дальше начала — читаем побольше
	var n := mini(f.get_length(), 65536 if path.get_extension().to_lower() in ["jpg", "jpeg"] else 64)
	var head := f.get_buffer(n)
	f.close()
	return from_bytes(head)


static func _be32(b: PackedByteArray, o: int) -> int:
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


## Раскодировать картинку из байтов по расширению.
static func decode(data: PackedByteArray, ext: String) -> Image:
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match ext.to_lower():
		"png":
			err = img.load_png_from_buffer(data)
		"webp":
			err = img.load_webp_from_buffer(data)
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(data)
	if err != OK:
		# на случай неверного расширения — попробовать все
		for fn: Callable in [img.load_png_from_buffer, img.load_webp_from_buffer, img.load_jpg_from_buffer]:
			if fn.call(data) == OK:
				return img
		return null
	return img
