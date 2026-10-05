class_name PackPanel
extends VBoxContainer
## Паки слева (ФТ-01, 02): список паков, виды текстур, поиск по имени и тегам, миниатюры — перетаскиваются на холст,
## крупный предпросмотр на шахматке или на основе карты.

signal picked(pack_id: String, tex: String)
signal add_folder
signal add_zip
signal check_pack(pack_id: String)
signal message(text: String)

const ALL := "*"
const KIND_ORDER := ["place", "decal", "strip", "base", "height", "tile", "token", "tech"]

var lib: PackLibrary
var cache: TexCache
var canvas: MapCanvas

var _packs: ItemList
var _kinds: OptionButton
var _search: LineEdit
var _grid: ItemList
var _preview: TexturePreview
var _info: Label
var _items: Array = []   ## [pack_id, tex] по номеру в сетке
var _pack_ids: Array = []
var _refresh_queued := false


func setup(l: PackLibrary, c: TexCache, cv: MapCanvas) -> void:
	lib = l
	cache = c
	canvas = cv
	lib.changed.connect(refresh_packs)
	cache.loaded.connect(func(_k: String) -> void: _queue_grid())
	refresh_packs()


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(UiTheme.header("Паки текстур"))
	var row := HBoxContainer.new()
	row.add_child(UiTheme.button("＋ Папка", "Подключить папку с текстурами (пак). Файлы пака не меняются.", func() -> void: add_folder.emit()))
	row.add_child(UiTheme.button("＋ Архив", "Подключить пак в .zip", func() -> void: add_zip.emit()))
	add_child(row)
	_packs = ItemList.new()
	_packs.custom_minimum_size = Vector2(0, 130)
	_packs.tooltip_text = "Подключённые паки. Выберите пак — справа внизу его текстуры. «Все паки» — искать везде."
	_packs.item_selected.connect(func(_i: int) -> void: _fill_grid())
	add_child(_packs)
	var row2 := HBoxContainer.new()
	row2.add_child(UiTheme.button("Вкл/выкл", "Выключенный пак не участвует в карте и поиске", _toggle_pack))
	row2.add_child(UiTheme.button("Проверить", "Размеры, прозрачность, облик dry, битые файлы", func() -> void:
		var pid := _current_pack()
		if pid != "" and pid != ALL:
			check_pack.emit(pid)))
	row2.add_child(UiTheme.button("Убрать", "Убрать пак из библиотеки (файлы не удаляются)", _remove_pack))
	add_child(row2)
	var row3 := HBoxContainer.new()
	_kinds = OptionButton.new()
	_kinds.tooltip_text = "Какие текстуры показать"
	_kinds.add_item("Все виды")
	_kinds.set_item_metadata(0, "")
	for k: String in KIND_ORDER:
		_kinds.add_item(TexPack.KIND_NAMES[k])
		_kinds.set_item_metadata(_kinds.item_count - 1, k)
	_kinds.select(1)
	_kinds.item_selected.connect(func(_i: int) -> void: _fill_grid())
	row3.add_child(_kinds)
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск…"
	_search.tooltip_text = "Поиск по имени и тегам"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _fill_grid())
	row3.add_child(_search)
	add_child(row3)
	_grid = ItemList.new()
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.max_columns = 0
	_grid.icon_mode = ItemList.ICON_MODE_TOP
	_grid.fixed_icon_size = Vector2i(88, 88)
	_grid.fixed_column_width = 104
	_grid.same_column_width = true
	_grid.max_text_lines = 2
	_grid.add_theme_font_size_override("font_size", 12)
	_grid.item_selected.connect(_on_pick)
	_grid.set_drag_forwarding(_drag_data, Callable(), Callable())
	_grid.tooltip_text = "Перетащите на карту: облик места — новое место (или новый облик, если бросить на место), основу — основа карты, метку — на место или тропу"
	add_child(_grid)
	_preview = TexturePreview.new()
	_preview.custom_minimum_size = Vector2(0, 190)
	add_child(_preview)
	var pr := HBoxContainer.new()
	var on_base := CheckBox.new()
	on_base.text = "на основе карты"
	on_base.tooltip_text = "Показать картинку поверх основы текущей карты — видно, подходит ли свет и ракурс"
	on_base.toggled.connect(func(v: bool) -> void:
		_preview.on_base = v
		_preview.queue_redraw())
	pr.add_child(on_base)
	add_child(pr)
	_info = UiTheme.label("", 12, UiTheme.DIM, true)
	add_child(_info)


func refresh_packs() -> void:
	if _packs == null or lib == null:
		return
	var keep := _current_pack()
	_packs.clear()
	_pack_ids = [ALL]
	_packs.add_item("Все паки")
	for e: Dictionary in lib.entries:
		var pid := str(e.get("id", ""))
		var p: TexPack = lib.get_pack(pid)
		if p == null:
			continue
		var cnt := p.count_by_kind()
		var on := bool(e.get("enabled", true))
		var text := "%s%s — мест %d, меток %d" % ["" if on else "(выкл) ", p.name, p.places().size(), int(cnt.decal) + int(cnt.strip)]
		_packs.add_item(text)
		_packs.set_item_tooltip(_packs.item_count - 1, "%s\n%s\nверсия %d%s" % [p.name, p.root, p.version, ("\n" + p.style) if p.style != "" else ""])
		if not on:
			_packs.set_item_custom_fg_color(_packs.item_count - 1, UiTheme.DIM)
		_pack_ids.append(pid)
	var idx := maxi(0, _pack_ids.find(keep))
	_packs.select(idx)
	_fill_grid()


func _current_pack() -> String:
	if _packs == null:
		return ""
	var s := _packs.get_selected_items()
	if s.is_empty() or s[0] >= _pack_ids.size():
		return ALL
	return _pack_ids[s[0]]


func select_pack(pid: String) -> void:
	var i := _pack_ids.find(pid)
	if i >= 0:
		_packs.select(i)
		_fill_grid()


func _toggle_pack() -> void:
	var pid := _current_pack()
	if pid == "" or pid == ALL:
		return
	lib.set_enabled(pid, not lib.is_enabled(pid))
	if canvas != null:
		canvas.queue_redraw()


func _remove_pack() -> void:
	var pid := _current_pack()
	if pid == "" or pid == ALL:
		return
	lib.remove(pid)
	message.emit("Пак убран из библиотеки. Файлы на диске не тронуты.")


func _queue_grid() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_update_icons.call_deferred()


func _update_icons() -> void:
	_refresh_queued = false
	for i in _items.size():
		if i >= _grid.item_count:
			break
		if _grid.get_item_icon(i) == null:
			var it: Array = _items[i]
			var t := cache.pack_tex(lib.get_pack(it[0]), it[1], 128)
			if t != null:
				_grid.set_item_icon(i, t)
	_preview.queue_redraw()


func _fill_grid() -> void:
	if _grid == null or lib == null:
		return
	_grid.clear()
	_items.clear()
	var pid := _current_pack()
	var kind := str(_kinds.get_item_metadata(_kinds.selected))
	var q := _search.text.strip_edges().to_lower()
	var packs: Array = lib.enabled_packs() if pid == ALL else ([lib.get_pack(pid)] if lib.get_pack(pid) != null else [])
	for p: TexPack in packs:
		var names := p.textures.keys()
		names.sort()
		for nm: String in names:
			var e: Dictionary = p.textures[nm]
			if kind != "" and str(e.kind) != kind:
				continue
			if q != "" and not (nm.to_lower().contains(q) or " ".join(p.tags_of(nm)).to_lower().contains(q) or p.place_name(str(e.get("place", ""))).to_lower().contains(q)):
				continue
			var label := nm
			if str(e.kind) == "place":
				var pn := p.place_name(str(e.place))
				label = "%s\n%s" % [pn if pn != "" else str(e.place).replace("_", " "), Words.state(str(e.state))]
			else:
				label = nm.trim_prefix("decal_").replace("_", " ")
			var i := _grid.add_item(label, cache.pack_tex(p, nm, 128))
			_grid.set_item_tooltip(i, "%s\n%s · %d×%d · пак «%s»" % [nm, Words.KINDS.get(str(e.kind), e.kind), int(e.get("w", 0)), int(e.get("h", 0)), p.name])
			_items.append([p.id, nm])
	_info.text = "Текстур: %d" % _items.size()


func _on_pick(i: int) -> void:
	if i < 0 or i >= _items.size():
		return
	var it: Array = _items[i]
	var p: TexPack = lib.get_pack(it[0])
	_preview.set_tex(cache, p, it[1], canvas)
	var e: Dictionary = p.textures[it[1]]
	_info.text = "%s — %s, %d×%d, пак «%s»" % [it[1], Words.KINDS.get(str(e.kind), e.kind), int(e.w), int(e.h), p.name]
	picked.emit(it[0], it[1])


func _drag_data(at: Vector2) -> Variant:
	var i := _grid.get_item_at_position(at, true)
	if i < 0 or i >= _items.size():
		return null
	var it: Array = _items[i]
	var tr := TextureRect.new()
	tr.texture = _grid.get_item_icon(i)
	tr.custom_minimum_size = Vector2(72, 72)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.modulate = Color(1, 1, 1, 0.8)
	_grid.set_drag_preview(tr)
	return {"type": "tex", "pack": it[0], "tex": it[1]}
