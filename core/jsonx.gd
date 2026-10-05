class_name JsonX
extends RefCounted
## JSON в формате игры: целые остаются целыми (55, а не 55.0), порядок ключей сохраняется,
## запись — как у Python json.dumps(ensure_ascii=False, indent=1) + перевод строки LF в конце.
## Встроенный JSON Godot читает все числа как дробные — для файлов игры это давало бы лишние изменения.

var _s: String
var _i: int
var error := ""


## Разобрать текст. При ошибке — null и текст ошибки в last_error.
static var last_error := ""


static func parse(text: String) -> Variant:
	var p := JsonX.new()
	p._s = text
	p._i = 0
	p._ws()
	var v: Variant = p._value()
	p._ws()
	if p.error == "" and p._i < p._s.length():
		p.error = "лишние символы в позиции %d" % p._i
	last_error = p.error
	return null if p.error != "" else v


static func read_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		last_error = "нет файла " + path
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.begins_with("﻿"):
		text = text.substr(1)
	return parse(text)


## Текст в формате игры (отступ 1 пробел).
static func stringify(v: Variant, indent: int = 1) -> String:
	var parts := PackedStringArray()
	_emit(v, 0, indent, parts)
	return "".join(parts)


## Записать через временный файл (сбой не портит прежний файл). Возвращает "" или текст ошибки.
static func write_file(path: String, v: Variant, indent: int = 1) -> String:
	return write_text(path, stringify(v, indent) + "\n")


static func write_text(path: String, text: String) -> String:
	return write_bytes(path, text.to_utf8_buffer())


static func write_bytes(path: String, data: PackedByteArray) -> String:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var e0 := DirAccess.make_dir_recursive_absolute(dir)
		if e0 != OK:
			return "не создать папку %s (%s)" % [dir, error_string(e0)]
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "не записать %s (%s)" % [tmp, error_string(FileAccess.get_open_error())]
	f.store_buffer(data)
	f.close()
	var e := DirAccess.rename_absolute(tmp, path)
	if e != OK:
		DirAccess.remove_absolute(tmp)
		return "не переименовать %s → %s (%s)" % [tmp, path, error_string(e)]
	return ""


## Глубокая копия с сохранением порядка ключей.
static func copy(v: Variant) -> Variant:
	if v is Dictionary or v is Array:
		return v.duplicate(true)
	return v


# --- запись --------------------------------------------------------------------------------------

static func _emit(v: Variant, level: int, indent: int, out: PackedStringArray) -> void:
	match typeof(v):
		TYPE_NIL:
			out.append("null")
		TYPE_BOOL:
			out.append("true" if v else "false")
		TYPE_INT:
			out.append(str(v))
		TYPE_FLOAT:
			out.append(num(float(v)))
		TYPE_STRING, TYPE_STRING_NAME:
			out.append(quote(str(v)))
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.is_empty():
				out.append("{}")
				return
			var pad := "\n" + " ".repeat(indent * (level + 1))
			out.append("{")
			var first := true
			for k: Variant in d:
				out.append(("" if first else ",") + pad)
				first = false
				out.append(quote(str(k)) + ": ")
				_emit(d[k], level + 1, indent, out)
			out.append("\n" + " ".repeat(indent * level) + "}")
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			var a: Array = Array(v)
			if a.is_empty():
				out.append("[]")
				return
			var pad2 := "\n" + " ".repeat(indent * (level + 1))
			out.append("[")
			for i in a.size():
				out.append(("" if i == 0 else ",") + pad2)
				_emit(a[i], level + 1, indent, out)
			out.append("\n" + " ".repeat(indent * level) + "]")
		TYPE_VECTOR2:
			_emit([v.x, v.y], level, indent, out)
		_:
			out.append(quote(str(v)))


## Дробное как у Python repr: кратчайшая запись, 1.0 — с точкой.
static func num(x: float) -> String:
	if is_nan(x) or is_inf(x):
		return "null"
	var s := var_to_str(x)
	if s.ends_with(".0") or "." in s or "e" in s:
		return s
	return s + ".0"


static func quote(s: String) -> String:
	var b := PackedStringArray(["\""])
	for i in s.length():
		var c := s.unicode_at(i)
		match c:
			0x22:
				b.append("\\\"")
			0x5C:
				b.append("\\\\")
			0x0A:
				b.append("\\n")
			0x0D:
				b.append("\\r")
			0x09:
				b.append("\\t")
			0x08:
				b.append("\\b")
			0x0C:
				b.append("\\f")
			_:
				if c < 0x20:
					b.append("\\u%04x" % c)
				else:
					b.append(String.chr(c))
	b.append("\"")
	return "".join(b)


# --- разбор --------------------------------------------------------------------------------------

func _ws() -> void:
	while _i < _s.length():
		var c := _s.unicode_at(_i)
		if c == 0x20 or c == 0x0A or c == 0x0D or c == 0x09:
			_i += 1
		else:
			break


func _fail(msg: String) -> Variant:
	if error == "":
		# строка и столбец — для понятной ошибки
		var line := _s.substr(0, _i).count("\n") + 1
		error = "%s (строка %d)" % [msg, line]
	_i = _s.length()
	return null


func _value() -> Variant:
	if _i >= _s.length():
		return _fail("неожиданный конец")
	var c := _s[_i]
	match c:
		"{":
			return _object()
		"[":
			return _array()
		"\"":
			return _string()
		"t":
			return _word("true", true)
		"f":
			return _word("false", false)
		"n":
			return _word("null", null)
	return _number()


func _word(w: String, v: Variant) -> Variant:
	if _s.substr(_i, w.length()) == w:
		_i += w.length()
		return v
	return _fail("непонятное слово")


func _object() -> Variant:
	var d := {}
	_i += 1
	_ws()
	if _i < _s.length() and _s[_i] == "}":
		_i += 1
		return d
	while error == "":
		_ws()
		if _i >= _s.length() or _s[_i] != "\"":
			return _fail("ожидался ключ")
		var k: String = _string()
		_ws()
		if _i >= _s.length() or _s[_i] != ":":
			return _fail("ожидалось «:»")
		_i += 1
		_ws()
		d[k] = _value()
		_ws()
		if _i < _s.length() and _s[_i] == ",":
			_i += 1
			continue
		if _i < _s.length() and _s[_i] == "}":
			_i += 1
			return d
		return _fail("ожидалось «,» или «}»")
	return null


func _array() -> Variant:
	var a: Array = []
	_i += 1
	_ws()
	if _i < _s.length() and _s[_i] == "]":
		_i += 1
		return a
	while error == "":
		_ws()
		a.append(_value())
		_ws()
		if _i < _s.length() and _s[_i] == ",":
			_i += 1
			continue
		if _i < _s.length() and _s[_i] == "]":
			_i += 1
			return a
		return _fail("ожидалось «,» или «]»")
	return null


func _string() -> Variant:
	_i += 1
	var start := _i
	var parts := PackedStringArray()
	while _i < _s.length():
		var c := _s[_i]
		if c == "\"":
			parts.append(_s.substr(start, _i - start))
			_i += 1
			return "".join(parts)
		if c == "\\":
			parts.append(_s.substr(start, _i - start))
			_i += 1
			if _i >= _s.length():
				break
			var e := _s[_i]
			match e:
				"n":
					parts.append("\n")
				"t":
					parts.append("\t")
				"r":
					parts.append("\r")
				"b":
					parts.append(String.chr(8))
				"f":
					parts.append(String.chr(12))
				"u":
					var code := _s.substr(_i + 1, 4).hex_to_int()
					_i += 4
					# суррогатная пара
					if code >= 0xD800 and code < 0xDC00 and _s.substr(_i + 1, 2) == "\\u":
						var lo := _s.substr(_i + 3, 4).hex_to_int()
						code = 0x10000 + ((code - 0xD800) << 10) + (lo - 0xDC00)
						_i += 6
					parts.append(String.chr(code))
				_:
					parts.append(e)
			_i += 1
			start = _i
			continue
		_i += 1
	return _fail("незакрытая строка")


func _number() -> Variant:
	var start := _i
	var is_float := false
	if _i < _s.length() and _s[_i] == "-":
		_i += 1
	while _i < _s.length():
		var c := _s[_i]
		if c >= "0" and c <= "9":
			_i += 1
		elif c == "." or c == "e" or c == "E" or c == "+" or c == "-":
			is_float = true
			_i += 1
		else:
			break
	var t := _s.substr(start, _i - start)
	if t == "" or t == "-":
		return _fail("непонятный символ «%s»" % _s.substr(start, 1))
	return t.to_float() if is_float else t.to_int()
