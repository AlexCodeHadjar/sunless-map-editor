class_name PropsPanel
extends TabContainer
## Справа: свойства выделенного, параметры карты, слои, проверки, «Дополнительно».
## Всё словами и ползунками — числа (доли основы, уровни воды) остаются под капотом; видны только в режиме «Подробно».

signal focus_place(lid: String)
signal focus_thing(sel: Dictionary)
signal run_checks
signal message(text: String)

var doc: MapDoc
var canvas: MapCanvas
var cache: TexCache
var lib: PackLibrary

var _props: VBoxContainer
var _map: VBoxContainer
var _layers: VBoxContainer
var _checks_box: VBoxContainer
var _checks_list: ItemList
var _checks_sum: Label
var _extra: TextEdit
var _rows: Array = []
var _rebuild_queued := false


func _ready() -> void:
	custom_minimum_size = Vector2(340, 0)
	_props = _tab("Свойства")
	_map = _tab("Карта")
	_layers = _tab("Слои")
	_checks_box = VBoxContainer.new()
	_checks_box.name = "Проверки"
	add_child(_checks_box)
	var top := HBoxContainer.new()
	top.add_child(UiTheme.button("Проверить карту", "Те же проверки, что игра делает при запуске (F7)", func() -> void: run_checks.emit()))
	_checks_box.add_child(top)
	_checks_sum = UiTheme.label("Проверка ещё не запускалась", 14, UiTheme.DIM, true)
	_checks_box.add_child(_checks_sum)
	_checks_list = ItemList.new()
	_checks_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_checks_list.max_text_lines = 3
	_checks_list.add_theme_font_size_override("font_size", 13)
	_checks_list.item_selected.connect(_on_check_pick)
	_checks_list.tooltip_text = "Щёлкните строку — виноватое место или тропа выделится на карте"
	_checks_box.add_child(_checks_list)
	var ex := VBoxContainer.new()
	ex.name = "Дополнительно"
	add_child(ex)
	ex.add_child(UiTheme.label("Поля карты, которые редактор пока не показывает в своих панелях. Они сохраняются в игру как были. Менять — только если знаете, что делаете.", 13, UiTheme.DIM, true))
	_extra = TextEdit.new()
	_extra.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_extra.add_theme_font_size_override("font_size", 13)
	ex.add_child(_extra)
	ex.add_child(UiTheme.button("Применить", "Записать эти поля в карту (можно отменить Ctrl+Z)", _apply_extra))


func _tab(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return v


func setup(d: MapDoc, cv: MapCanvas, c: TexCache, l: PackLibrary) -> void:
	doc = d
	canvas = cv
	cache = c
	lib = l
	if not doc.changed.is_connected(_on_doc_changed):
		doc.changed.connect(_on_doc_changed)
	rebuild()


func _on_doc_changed(_w: String) -> void:
	queue_rebuild()


func queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	if doc == null:
		return
	_build_props()
	_build_map()
	_build_layers()
	_extra.text = JsonX.stringify(doc.unknown_fields(), 1) if not doc.unknown_fields().is_empty() else "{}"


func _clear(box: Container) -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()


# --- общие поля ----------------------------------------------------------------------------------

## Ползунок со словом вместо числа. setter(value) вызывается внутри правки (отмена одним шагом).
func _slider(box: Container, title: String, tip: String, lo: float, hi: float, step: float, val: float, word: Callable, setter: Callable, label: String) -> HSlider:
	var l := UiTheme.label(title, 14)
	l.tooltip_text = tip
	box.add_child(l)
	var row := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.tooltip_text = tip
	var w := UiTheme.label(word.call(val), 14, UiTheme.ACCENT)
	w.custom_minimum_size = Vector2(130, 0)
	var num := UiTheme.label("", 12, UiTheme.DIM)
	if canvas.detailed:
		num.text = str(snappedf(val, step))
	var dragging := [false]
	s.drag_started.connect(func() -> void:
		dragging[0] = true
		doc.begin(label))
	s.drag_ended.connect(func(_c: bool) -> void:
		dragging[0] = false
		doc.commit())
	s.value_changed.connect(func(v: float) -> void:
		w.text = word.call(v)
		if canvas.detailed:
			num.text = str(snappedf(v, step))
		if dragging[0]:
			setter.call(v)
			canvas.queue_redraw()
		else:
			doc.edit(label, func() -> void: setter.call(v)))
	row.add_child(s)
	row.add_child(w)
	if canvas.detailed:
		row.add_child(num)
	box.add_child(row)
	return s


func _sep(box: Container) -> void:
	box.add_child(HSeparator.new())


# --- свойства выделенного ------------------------------------------------------------------------

func _build_props() -> void:
	_clear(_props)
	var sel: Dictionary = canvas.sel
	match str(sel.get("kind", "")):
		"place":
			if doc.places().has(str(sel.id)):
				_place_props(str(sel.id))
				return
		"path":
			_path_props(Array(sel.id))
			return
		"socket":
			_socket_props(int(sel.id))
			return
		"decal":
			_decal_props(sel.id)
			return
		"rubble":
			_rubble_props(str(sel.id))
			return
		"zone":
			_zone_props(str(sel.id))
			return
	_props.add_child(UiTheme.header("Ничего не выделено"))
	_props.add_child(UiTheme.label("Щёлкните место на карте, чтобы увидеть его свойства.\n\nКак собрать карту:\n1. Перетащите основу из пака на холст.\n2. Перетащите облики мест — появятся места.\n3. Инструмент «Тропа» (T): щёлкните два места.\n4. Проверка (F7) и экспорт в игру (Ctrl+E).", 14, UiTheme.DIM, true))
	_props.add_child(UiTheme.label("Мест на карте: %d, троп: %d" % [doc.places().size(), doc.paths().size()], 14, UiTheme.TEXT))


func _place_props(lid: String) -> void:
	var is_shop := doc.is_shop(lid)
	_props.add_child(UiTheme.header("Лавка" if is_shop else "Место"))
	# название
	var name_edit := LineEdit.new()
	name_edit.text = doc.display_name(lid)
	name_edit.tooltip_text = "Подпись места на карте (как увидит игрок)"
	name_edit.text_submitted.connect(func(t: String) -> void: _set_name(lid, t))
	name_edit.focus_exited.connect(func() -> void: _set_name(lid, name_edit.text))
	_props.add_child(UiTheme.label("Название", 14))
	_props.add_child(name_edit)
	if canvas.detailed:
		var row := HBoxContainer.new()
		var idl := LineEdit.new()
		idl.text = lid
		idl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		idl.tooltip_text = "Код места в файлах игры (латиница). Меняется везде: тропы, метки, зоны, картинки."
		row.add_child(idl)
		row.add_child(UiTheme.button("Переименовать", "", func() -> void:
			var err: String = doc.edit("Переименовать место", func() -> String: return doc.rename_place(lid, idl.text))
			if err != "":
				message.emit(err)
			else:
				canvas.select_place(TexPack.slug(idl.text))))
		_props.add_child(UiTheme.label("Код места", 13, UiTheme.DIM))
		_props.add_child(row)
	# облики
	_sep(_props)
	_props.add_child(UiTheme.label("Как выглядит", 14))
	_props.add_child(UiTheme.label("Щёлкните картинку — так место будет видно на холсте. Новый облик: перетащите картинку из пака прямо на место.", 12, UiTheme.DIM, true))
	var flow := HFlowContainer.new()
	var cur := canvas.state_for(lid)
	for st: String in doc.states(lid):
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = st == cur
		b.icon = cache.map_tex(canvas.src, "%s_%s" % [lid, st], 128)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(92, 104)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.text = Words.state(st)
		b.add_theme_font_size_override("font_size", 11)
		b.clip_text = true
		var src_info := canvas.src.resolve("%s_%s" % [lid, st])
		b.tooltip_text = "%s\n%s" % [Words.state(st), "нет картинки!" if src_info.from == "none" else ("из пака «%s»" % _pack_name(str(src_info.pack)) if src_info.from == "pack" else "из папки игры")]
		if src_info.from == "none":
			b.modulate = Color(1, 0.6, 0.6)
		b.pressed.connect(func() -> void:
			canvas.preview_state[lid] = st
			canvas.queue_redraw()
			queue_rebuild())
		flow.add_child(b)
	_props.add_child(flow)
	var srow := HBoxContainer.new()
	srow.add_child(UiTheme.button("Сделать обычным", "Этот облик игра покажет, когда ничего особенного не происходит", func() -> void:
		doc.edit("Облик по умолчанию", func() -> void: doc.make_default_state(lid, cur))))
	srow.add_child(UiTheme.button("Убрать облик", "Убрать выбранный облик из места (картинка в паке остаётся)", func() -> void:
		if doc.states(lid).size() <= 1:
			message.emit("У места должен остаться хотя бы один облик.")
			return
		doc.edit("Убрать облик", func() -> void: doc.remove_state(lid, cur))
		canvas.preview_state.erase(lid)))
	_props.add_child(srow)
	if not doc.states(lid).has("dry"):
		_props.add_child(UiTheme.label("⚠ Нет обычного облика (dry) — игра покажет первый в списке.", 12, UiTheme.WARN, true))
	# размер
	_sep(_props)
	_slider(_props, "Размер на карте", "Ширина картинки места на основе. Тяните — или тяните уголок места на холсте.", 0.05, 0.3, 0.005,
		doc.size_of(lid), func(v: float) -> String: return Words.place_size(v), func(v: float) -> void: doc.set_size(lid, v), "Размер места")
	if is_shop:
		_props.add_child(UiTheme.label("Через лавку можно пройти насквозь, но встать лагерем нельзя. Для проверок лавка считается высотой.", 13, UiTheme.DIM, true))
	else:
		_location_props(lid)
	# тропы
	_sep(_props)
	var nb := doc.path_places(lid)
	_props.add_child(UiTheme.label("Тропы отсюда: %s" % ("нет — место не связано!" if nb.is_empty() else str(nb.size())), 14, UiTheme.ERROR if nb.is_empty() else UiTheme.TEXT))
	for n: String in nb:
		var r := HBoxContainer.new()
		var go := UiTheme.button("→ " + doc.display_name(n), "Показать место", func() -> void: focus_place.emit(n))
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		go.alignment = HORIZONTAL_ALIGNMENT_LEFT
		r.add_child(go)
		r.add_child(UiTheme.button("✕", "Убрать тропу", func() -> void: doc.edit("Убрать тропу", func() -> void: doc.toggle_path(lid, n))))
		_props.add_child(r)
	_sep(_props)
	var del := UiTheme.button("Удалить место", "Место удалится вместе с его тропами (Del)", func() -> void: canvas.delete_requested.emit())
	del.add_theme_color_override("font_color", UiTheme.ERROR)
	_props.add_child(del)


func _pack_name(pid: String) -> String:
	var p: TexPack = lib.get_pack(pid) if lib != null else null
	return p.name if p != null else pid


func _set_name(lid: String, t: String) -> void:
	t = t.strip_edges()
	if t == "" or t == doc.display_name(lid):
		return
	doc.edit("Название места", func() -> void:
		if doc.shops.has(lid):
			doc.shops[lid]["name"] = t
		else:
			if not doc.locations.has(lid):
				doc.locations[lid] = doc.new_location(lid, t, doc.at(lid))
			doc.locations[lid]["name"] = t)
	canvas.queue_redraw()


## Игровые свойства места (locations.json): высота над водой, лагерь, появляющееся.
func _location_props(lid: String) -> void:
	if not doc.locations.has(lid):
		_props.add_child(UiTheme.button("Добавить место в список мест игры", "", func() -> void:
			doc.edit("Запись места", func() -> void: doc.locations[lid] = doc.new_location(lid, lid, doc.at(lid)))))
		return
	var loc: Dictionary = doc.locations[lid]
	_sep(_props)
	_props.add_child(UiTheme.label("Высота над водой", 14))
	var hb := OptionButton.new()
	var keys := ["low", "mid", "high", ""]
	for k: String in keys:
		hb.add_item(str(Words.HEIGHTS[k]))
	hb.select(maxi(0, keys.find(str(loc.get("height", "")))))
	hb.tooltip_text = "От высоты зависит, уходит ли место под воду в прилив, и «сухой хребет» карты"
	hb.item_selected.connect(func(i: int) -> void:
		doc.edit("Высота места", func() -> void:
			if keys[i] == "":
				doc.locations[lid].erase("height")
			else:
				doc.locations[lid]["height"] = keys[i])
		canvas.queue_redraw())
	_props.add_child(hb)
	# лагерь
	_sep(_props)
	var has_camp := loc.has("camp")
	var cb := CheckBox.new()
	cb.text = "Здесь можно встать лагерем"
	cb.button_pressed = has_camp
	cb.tooltip_text = "Где стоит фигура отряда — там лагерь: отдых, места для сна, опасность ночи"
	cb.toggled.connect(func(v: bool) -> void:
		doc.edit("Лагерь", func() -> void:
			if v:
				doc.locations[lid]["camp"] = {"rest": 10, "beds": 0, "danger": 0.2, "services": []}
			else:
				doc.locations[lid].erase("camp")))
	_props.add_child(cb)
	if has_camp:
		var camp: Dictionary = loc.camp
		_slider(_props, "Отдых за ночь", "Сколько психики отряд восстанавливает за ночь здесь", 0, 40, 1, float(camp.get("rest", 10)),
			func(v: float) -> String: return Words.rest(int(v)), func(v: float) -> void: doc.locations[lid]["camp"]["rest"] = int(v), "Отдых в лагере")
		_slider(_props, "Опасность ночи", "Насколько вероятно ночное нападение", 0.0, 0.6, 0.01, float(camp.get("danger", 0.2)),
			func(v: float) -> String: return Words.danger(v), func(v: float) -> void: doc.locations[lid]["camp"]["danger"] = snappedf(v, 0.01), "Опасность ночи")
		var br := HBoxContainer.new()
		br.add_child(UiTheme.label("Мест для сна", 14))
		var beds := SpinBox.new()
		beds.min_value = 0
		beds.max_value = 6
		beds.value = int(camp.get("beds", 0))
		beds.tooltip_text = "Сколько героев выспятся с удобством"
		beds.value_changed.connect(func(v: float) -> void: doc.edit("Места для сна", func() -> void: doc.locations[lid]["camp"]["beds"] = int(v)))
		br.add_child(beds)
		_props.add_child(br)
		for sv: String in Words.SERVICES:
			var c2 := CheckBox.new()
			c2.text = str(Words.SERVICES[sv])
			c2.button_pressed = Array(camp.get("services", [])).has(sv)
			c2.toggled.connect(func(v: bool) -> void:
				doc.edit("Службы лагеря", func() -> void:
					var a: Array = doc.locations[lid]["camp"].get("services", [])
					if v and not a.has(sv):
						a.append(sv)
					elif not v:
						a.erase(sv)
					doc.locations[lid]["camp"]["services"] = a))
			_props.add_child(c2)
	# появляющееся место
	_sep(_props)
	var em := CheckBox.new()
	em.text = "Появляется и исчезает (встаёт на площадки)"
	em.button_pressed = bool(loc.get("emerge", false))
	em.tooltip_text = "Такое место не стоит на карте постоянно: игра ставит его на свободную площадку (после отлива, бури…)"
	em.toggled.connect(func(v: bool) -> void:
		doc.edit("Появляющееся место", func() -> void:
			if v:
				doc.locations[lid]["emerge"] = true
			else:
				doc.locations[lid].erase("emerge")
				doc.locations[lid].erase("socket_group")))
	_props.add_child(em)
	if bool(loc.get("emerge", false)):
		var groups: Dictionary = doc.map.get("emerge_groups", {})
		var gb := OptionButton.new()
		gb.add_item("площадки отлива (общие)")
		gb.set_item_metadata(0, "")
		var gi := 0
		for g: String in groups:
			gb.add_item("группа «%s»" % g)
			gb.set_item_metadata(gb.item_count - 1, g)
			if g == str(loc.get("socket_group", "")):
				gi = gb.item_count - 1
		gb.select(gi)
		gb.item_selected.connect(func(i: int) -> void:
			doc.edit("Группа площадок", func() -> void:
				var g2 := str(gb.get_item_metadata(i))
				if g2 == "":
					doc.locations[lid].erase("socket_group")
				else:
					doc.locations[lid]["socket_group"] = g2))
		_props.add_child(gb)
	# описание
	_sep(_props)
	_props.add_child(UiTheme.label("Описание (для журнала)", 14))
	var te := TextEdit.new()
	te.text = str(loc.get("text", ""))
	te.custom_minimum_size = Vector2(0, 70)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.focus_exited.connect(func() -> void:
		if te.text != str(doc.locations.get(lid, {}).get("text", "")):
			doc.edit("Описание места", func() -> void: doc.locations[lid]["text"] = te.text))
	_props.add_child(te)


func _path_props(pair: Array) -> void:
	if pair.size() != 2:
		return
	var a := str(pair[0])
	var b := str(pair[1])
	_props.add_child(UiTheme.header("Тропа"))
	_props.add_child(UiTheme.label("%s — %s" % [Words.q(doc.display_name(a)), Words.q(doc.display_name(b))], 15, UiTheme.TEXT, true))
	_props.add_child(UiTheme.label("Тропа ведёт в обе стороны. Длина на рисунке не важна — переход всегда занимает один шаг (полдня).", 13, UiTheme.DIM, true))
	var row := HBoxContainer.new()
	row.add_child(UiTheme.button("→ " + doc.display_name(a), "", func() -> void: focus_place.emit(a)))
	row.add_child(UiTheme.button("→ " + doc.display_name(b), "", func() -> void: focus_place.emit(b)))
	_props.add_child(row)
	_special_path_props(a, b)
	_sep(_props)
	var del := UiTheme.button("Убрать тропу", "", func() -> void:
		doc.edit("Убрать тропу", func() -> void:
			if doc.has_path(a, b):
				doc.toggle_path(a, b)
			if doc.map.has("water_paths"):
				doc.map["water_paths"] = Array(doc.map.water_paths).filter(func(e: Array) -> bool: return not MapDoc.same_pair(e, a, b)))
		canvas.select_thing({}))
	del.add_theme_color_override("font_color", UiTheme.ERROR)
	_props.add_child(del)


## Особые тропы (ФТ-19): водная, хрупкий проход, опасный спуск. Расширяется в фазе v2.
func _special_path_props(a: String, b: String) -> void:
	pass


func _socket_props(i: int) -> void:
	_props.add_child(UiTheme.header("Площадка %d" % (i + 1)))
	_props.add_child(UiTheme.label("Сюда игра ставит места, которые появляются и исчезают (места отлива, котловины после бури, места событий). Площадку можно тащить.", 13, UiTheme.DIM, true))
	_sep(_props)
	var del := UiTheme.button("Убрать площадку", "Номера остальных площадок пересчитаются, группы обновятся", func() -> void:
		doc.edit("Убрать площадку", func() -> void: doc.remove_socket(i))
		canvas.select_thing({}))
	del.add_theme_color_override("font_color", UiTheme.ERROR)
	_props.add_child(del)


func _decal_props(d: Variant) -> void:
	_props.add_child(UiTheme.header("Метка"))
	if d is Dictionary:
		_props.add_child(UiTheme.label(str(d.get("decal", "")), 14))
		if d.has("place"):
			_props.add_child(UiTheme.label("у места %s" % Words.q(doc.display_name(str(d.place))), 13, UiTheme.DIM))


func _rubble_props(rid: String) -> void:
	_props.add_child(UiTheme.header("Завал"))
	var r: Dictionary = doc.map.get("rubble", {}).get(rid, {})
	var pr: Array = r.get("pair", [])
	if pr.size() == 2:
		_props.add_child(UiTheme.label("На тропе %s — %s. В игре тропа может завалиться и снова открыться." % [Words.q(doc.display_name(str(pr[0]))), Words.q(doc.display_name(str(pr[1])))], 13, UiTheme.DIM, true))


func _zone_props(zid: String) -> void:
	_props.add_child(UiTheme.header("Зона"))
	var z: Dictionary = doc.map.get("zones", {}).get(zid, {})
	_props.add_child(UiTheme.label(str(z.get("name", zid)), 14))


# --- карта ---------------------------------------------------------------------------------------

func _build_map() -> void:
	_clear(_map)
	_map.add_child(UiTheme.header("Карта"))
	var base_row := HBoxContainer.new()
	var bt := TextureRect.new()
	bt.custom_minimum_size = Vector2(128, 64)
	bt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bt.texture = cache.map_tex(canvas.src, "base", 256)
	base_row.add_child(bt)
	var bsrc := canvas.src.resolve("base")
	base_row.add_child(UiTheme.label("Основа: %s" % ("нет — перетащите из пака" if bsrc.from == "none" else ("пак «%s»" % _pack_name(str(bsrc.pack)) if bsrc.from == "pack" else "из игры")), 13, UiTheme.TEXT, true))
	_map.add_child(base_row)
	var tiles := HBoxContainer.new()
	for slot: String in ["fog_tile", "water_tile"]:
		if slot == "water_tile" and not doc.map.has("height"):
			continue
		var t := TextureRect.new()
		t.custom_minimum_size = Vector2(48, 48)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.texture = cache.map_tex(canvas.src, str(doc.map.get("fog" if slot == "fog_tile" else "water", slot + ".webp")).get_basename(), 128)
		t.tooltip_text = "Плитка %s. Новая — перетащите плитку из пака на холст." % ("тумана" if slot == "fog_tile" else "воды")
		tiles.add_child(t)
		tiles.add_child(UiTheme.label("туман" if slot == "fog_tile" else "вода", 13, UiTheme.DIM))
	_map.add_child(tiles)
	_sep(_map)
	_map.add_child(UiTheme.label("Как игрок увидит карту при старте", 14, UiTheme.ACCENT))
	_slider(_map, "Сколько карты спрятано сверху", "Какая доля основы при старте уходит под верхний край окна", 0.0, 0.3, 0.01,
		float(doc.map.get("view_top", 0.08)), func(v: float) -> String: return "почти ничего" if v < 0.04 else ("немного" if v < 0.12 else "заметно"),
		func(v: float) -> void: doc.map["view_top"] = snappedf(v, 0.01), "Вид при старте")
	_slider(_map, "Где встаёт значок события", "Ромб события под местом: ближе к центру картинки или ниже. Ромбы видны на холсте — их можно тянуть.", 0.0, 0.5, 0.01,
		float(doc.map.get("foot", 0.28)), func(v: float) -> String: return "в центре места" if v < 0.1 else ("чуть ниже центра" if v < 0.3 else "у нижнего края"),
		func(v: float) -> void: doc.map["foot"] = snappedf(v, 0.01), "Точка события")
	_slider(_map, "Запас для сдвига мышью", "Насколько основа больше окна игры — столько карту можно двигать", 1.0, 1.6, 0.05,
		float(doc.map.get("zoom", 1.15)), func(v: float) -> String: return "без запаса" if v < 1.05 else ("небольшой" if v < 1.25 else "большой"),
		func(v: float) -> void: doc.map["zoom"] = snappedf(v, 0.01), "Запас сдвига")
	_water_props()
	_sep(_map)
	_map.add_child(UiTheme.label("Глава игры для новых мест", 14))
	var ch := LineEdit.new()
	ch.text = doc.chapter
	ch.tooltip_text = "Новые места записываются в эту главу (locations.json → chapter)"
	ch.text_submitted.connect(func(t: String) -> void: doc.edit("Глава", func() -> void: doc.chapter = t.strip_edges()))
	_map.add_child(ch)
	if canvas.detailed:
		_map.add_child(UiTheme.label("Регион (папка картинок и файл карты): %s" % doc.region, 13, UiTheme.DIM, true))


## Вода и прилив (ФТ-23, 24): уровни — словами. Расширяется в фазе v2.
func _water_props() -> void:
	pass


# --- слои ----------------------------------------------------------------------------------------

func _build_layers() -> void:
	_clear(_layers)
	_layers.add_child(UiTheme.header("Что показывать"))
	var names := {"base": "Основа", "water": "Вода", "height": "Карта высот (поверх основы)", "paths": "Тропы", "places": "Места",
		"labels": "Подписи мест", "decals": "Метки", "sockets": "Площадки", "foot": "Точки значков событий"}
	for k: String in names:
		if k in ["water", "height"] and not doc.map.has("height"):
			continue
		var row := HBoxContainer.new()
		var c := CheckBox.new()
		c.text = names[k]
		c.button_pressed = bool(canvas.layers.get(k, true))
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.toggled.connect(func(v: bool) -> void:
			canvas.layers[k] = v
			doc.editor["layers"] = canvas.layers.duplicate()
			canvas.queue_redraw())
		row.add_child(c)
		if canvas.locked.has(k):
			var lk := CheckBox.new()
			lk.text = "🔒"
			lk.tooltip_text = "Заблокировать: нельзя сдвинуть случайно"
			lk.button_pressed = bool(canvas.locked[k])
			lk.toggled.connect(func(v: bool) -> void: canvas.locked[k] = v)
			row.add_child(lk)
		_layers.add_child(row)
	if doc.map.has("height"):
		_slider(_layers, "Прозрачность карты высот", "", 0.1, 1.0, 0.05, canvas.height_alpha,
			func(v: float) -> String: return "едва видно" if v < 0.35 else ("наполовину" if v < 0.7 else "плотно"),
			func(v: float) -> void: canvas.height_alpha = v, "")


# --- проверки ------------------------------------------------------------------------------------

func show_checks(rows: Array) -> void:
	_rows = rows
	_checks_list.clear()
	var ne := MapChecks.errors(rows).size()
	var nw := rows.size() - ne
	if rows.is_empty():
		_checks_sum.text = "✔ Всё в порядке — карту можно отдавать в игру."
		_checks_sum.add_theme_color_override("font_color", UiTheme.OK)
	else:
		_checks_sum.text = "Ошибок: %d (экспорт запрещён), предупреждений: %d" % [ne, nw] if ne > 0 else "Ошибок нет, предупреждений: %d — экспорт можно" % nw
		_checks_sum.add_theme_color_override("font_color", UiTheme.ERROR if ne > 0 else UiTheme.WARN)
	for r: Dictionary in rows:
		var i := _checks_list.add_item(("✖ " if r.level == "error" else "⚠ ") + str(r.text))
		_checks_list.set_item_custom_fg_color(i, UiTheme.ERROR if r.level == "error" else UiTheme.WARN)
	current_tab = get_tab_idx_from_control(_checks_box)


func _on_check_pick(i: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	var r: Dictionary = _rows[i]
	if not Array(r.places).is_empty():
		focus_place.emit(str(r.places[0]))
	elif not Array(r.path).is_empty():
		focus_thing.emit({"kind": "path", "id": r.path})
	elif int(r.socket) >= 0:
		focus_thing.emit({"kind": "socket", "id": int(r.socket)})


func _apply_extra() -> void:
	var v: Variant = JsonX.parse(_extra.text)
	if not v is Dictionary:
		message.emit("Не JSON-словарь: " + JsonX.last_error)
		return
	doc.edit("Дополнительные поля", func() -> void:
		for k: String in doc.unknown_fields():
			if not v.has(k):
				doc.map.erase(k)
		for k2: String in v:
			if MapDoc.KNOWN_KEYS.has(k2):
				continue
			doc.map[k2] = v[k2])
	message.emit("Дополнительные поля записаны в карту.")
