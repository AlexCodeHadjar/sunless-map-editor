class_name JsonTree
extends Tree
## Таблица свойств любого JSON-поля карты (угрозы-точки и т.п., ФТ-33): ключ — значение, вложенное раскрывается,
## значения правятся двойным щелчком (число, строка, true/false или JSON). Изменение уходит в on_change(путь, значение).

var on_change: Callable
var _data: Variant


func _ready() -> void:
	columns = 2
	column_titles_visible = true
	set_column_title(0, "Поле")
	set_column_title(1, "Значение")
	set_column_expand_ratio(0, 2)
	set_column_expand_ratio(1, 3)
	hide_root = true
	item_edited.connect(_on_edited)
	custom_minimum_size = Vector2(0, 260)


func show_data(data: Variant, cb: Callable) -> void:
	on_change = cb
	_data = data
	clear()
	var root := create_item()
	_fill(root, data, [])


func _fill(parent: TreeItem, v: Variant, path: Array) -> void:
	if v is Dictionary:
		for k: Variant in v:
			_add(parent, str(k), v[k], path + [k])
	elif v is Array:
		for i in v.size():
			_add(parent, "#%d" % (i + 1), v[i], path + [i])


func _add(parent: TreeItem, key: String, v: Variant, path: Array) -> void:
	var it := create_item(parent)
	it.set_text(0, key)
	it.set_metadata(0, path)
	if v is Dictionary or v is Array:
		it.set_text(1, ("{%d}" if v is Dictionary else "[%d]") % v.size())
		it.set_custom_color(1, UiTheme.DIM)
		it.collapsed = path.size() > 1
		# короткий список чисел/строк — правится одной строкой
		if v is Array and v.size() <= 4 and v.all(func(x: Variant) -> bool: return not (x is Dictionary or x is Array)):
			it.set_text(1, JSON.stringify(v))
			it.set_editable(1, true)
			it.set_custom_color(1, UiTheme.TEXT)
			return
		_fill(it, v, path)
	else:
		it.set_text(1, JSON.stringify(v) if not v is String else str(v))
		it.set_editable(1, true)


func _on_edited() -> void:
	var it := get_edited()
	if it == null or not on_change.is_valid():
		return
	var txt := it.get_text(1).strip_edges()
	var val: Variant = JsonX.parse(txt)
	if val == null and txt != "null":
		val = txt   # не JSON — строка
	on_change.call(it.get_metadata(0), val)


## Записать значение по пути в словарь/массив.
static func set_path(root: Variant, path: Array, value: Variant) -> void:
	var cur: Variant = root
	for i in path.size() - 1:
		cur = cur[path[i]]
	cur[path[-1]] = value
