class_name PackCheck
extends RefCounted
## Проверка пака (ФТ-03): размеры и пропорции, прозрачность, облик dry, битые файлы, дубли имён между паками.
## Строка отчёта: {level: error|warn, text, pack, name, file}.


static func check(pack: TexPack, deep: bool = false) -> Array:
	var out: Array = []
	for e: String in pack.errors:
		out.append({"level": "error", "text": e, "pack": pack.id, "name": "", "file": ""})
	if not pack.has_manifest:
		out.append({"level": "warn", "text": "нет pack.json — список текстур построен по папкам (можно сохранить манифест)", "pack": pack.id, "name": "", "file": ""})
	for nm: String in pack.textures:
		var e: Dictionary = pack.textures[nm]
		var w := int(e.get("w", 0))
		var h := int(e.get("h", 0))
		var row := func(level: String, text: String) -> void:
			out.append({"level": level, "text": "%s: %s" % [nm, text], "pack": pack.id, "name": nm, "file": str(e.get("file", ""))})
		if not bool(e.get("ok", true)) or w <= 0 or h <= 0:
			row.call("error", "битый или неизвестный файл")
			continue
		if not nm.is_valid_identifier() and not nm.replace("_", "a").is_valid_identifier():
			row.call("warn", "имя не латиницей с подчёркиваниями")
		var ratio := float(w) / float(h)
		match str(e.kind):
			"base":
				if absf(ratio - 2.0) > 0.02:
					row.call("error", "основа должна быть 2:1, а она %d×%d" % [w, h])
				if w < 2048:
					row.call("warn", "основа меньше 2048×1024 (%d×%d)" % [w, h])
			"height":
				if absf(ratio - 2.0) > 0.02:
					row.call("error", "карта высот должна быть 2:1, а она %d×%d" % [w, h])
				if e.has("gray") and not bool(e.gray):
					row.call("warn", "карта высот не серая — возьмётся красный канал")
			"place", "decal", "token":
				if absf(ratio - 1.0) > 0.02:
					row.call("error", "должна быть квадратной, а она %d×%d" % [w, h])
				if e.get("alpha", null) == false:
					row.call("error", "нет прозрачности — у виньеток и меток фон должен быть прозрачным")
			"strip":
				if ratio < 3.0:
					row.call("warn", "полоса должна быть вытянутой 4:1, а она %d×%d" % [w, h])
				if e.get("alpha", null) == false:
					row.call("warn", "у полосы нет прозрачности — края будут резкими")
			"tile":
				if absf(ratio - 1.0) > 0.02:
					row.call("warn", "плитка должна быть квадратной (%d×%d)" % [w, h])
		if deep and str(e.kind) in ["place", "decal", "token"]:
			var img := pack.image(nm)
			if img == null:
				row.call("error", "не раскодировать картинку")
				continue
			if img.detect_alpha() == Image.ALPHA_NONE:
				row.call("error", "картинка без прозрачных пикселей")
			else:
				var c := img.get_pixel(1, 1)
				if c.a > 0.5:
					row.call("warn", "угол непрозрачный — место не по центру или фон не убран")
	var pls := pack.places()
	for pl: String in pls:
		if not Array(pls[pl]).has("dry"):
			out.append({"level": "warn", "text": "место %s: нет облика dry (игра берёт его по умолчанию)" % pl, "pack": pack.id, "name": pl + "_" + str(pls[pl][0]), "file": ""})
	return out


## Одинаковые имена текстур в разных паках библиотеки (ФТ-05).
static func duplicates(packs: Array) -> Array:
	var owners := {}
	for p: TexPack in packs:
		for nm: String in p.textures:
			if not owners.has(nm):
				owners[nm] = []
			owners[nm].append(p.id)
	var out: Array = []
	for nm2: String in owners:
		if Array(owners[nm2]).size() > 1:
			out.append({"level": "warn", "text": "%s есть в паках: %s" % [nm2, ", ".join(owners[nm2])], "pack": "", "name": nm2, "file": ""})
	return out
