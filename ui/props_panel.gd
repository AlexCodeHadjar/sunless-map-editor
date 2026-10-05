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
var _icon_buttons: Array = []   ## [кнопка, имя текстуры] — миниатюры приходят из фона позже


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
	ex.name = "Ещё"
	ex.tooltip_text = "Дополнительные поля карты"
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
	if not cache.loaded.is_connected(_on_icon_loaded):
		cache.loaded.connect(_on_icon_loaded)
	rebuild()


func _on_doc_changed(_w: String) -> void:
	queue_rebuild()


func _on_icon_loaded(_k: String) -> void:
	for it: Array in _icon_buttons:
		var b: Button = it[0]
		if is_instance_valid(b) and b.icon == null:
			b.icon = cache.map_tex(canvas.src, it[1], 128)


func queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	if doc == null:
		return
	_icon_buttons.clear()
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
		_icon_buttons.append([b, "%s_%s" % [lid, st]])
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
	_phase_looks(lid)
	_place_extras(lid)
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
	_groups_props()
	_sep(_map)
	_map.add_child(UiTheme.label("Глава игры для новых мест", 14))
	var ch := LineEdit.new()
	ch.text = doc.chapter
	ch.tooltip_text = "Новые места записываются в эту главу (locations.json → chapter)"
	ch.text_submitted.connect(func(t: String) -> void: doc.edit("Глава", func() -> void: doc.chapter = t.strip_edges()))
	_map.add_child(ch)
	if canvas.detailed:
		_map.add_child(UiTheme.label("Регион (папка картинок и файл карты): %s" % doc.region, 13, UiTheme.DIM, true))


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


## Особые тропы (ФТ-19): водная (только на лодке), опасный спуск, сети троп бури.
func _special_path_props(a: String, b: String) -> void:
	_sep(_props)
	_props.add_child(UiTheme.label("Особая тропа", 14, UiTheme.ACCENT))
	var is_water: bool = Array(doc.map.get("water_paths", [])).any(func(e: Array) -> bool: return MapDoc.same_pair(e, a, b))
	var wc := CheckBox.new()
	wc.text = "По Чёрной воде — только на лодке"
	wc.button_pressed = is_water
	wc.tooltip_text = "Водная тропа рисуется голубым; пройти можно только с лодкой и в «водные» фазы недели"
	wc.toggled.connect(func(v: bool) -> void:
		doc.edit("Водная тропа", func() -> void:
			var wp: Array = doc.map.get("water_paths", [])
			wp = wp.filter(func(e: Array) -> bool: return not MapDoc.same_pair(e, a, b))
			if v:
				wp.append([a, b])
				if doc.has_path(a, b):
					doc.toggle_path(a, b)
				if not doc.map.has("water_phases"):
					doc.map["water_phases"] = ["night", "blood_moon"]
			elif not doc.has_path(a, b):
				doc.paths().append([a, b])
			if wp.is_empty():
				doc.map.erase("water_paths")
			else:
				doc.map["water_paths"] = wp))
	_props.add_child(wc)
	var risky: Array = doc.map.get("risky", [])
	var ri := -1
	for i in risky.size():
		if MapDoc.same_pair(Array(risky[i].get("pair", [])), a, b):
			ri = i
	var rc := CheckBox.new()
	rc.text = "Опасный спуск — при переходе проверка героя"
	rc.button_pressed = ri >= 0
	rc.tooltip_text = "Лучший герой проходит проверку силы; провал — на грань смерти"
	rc.toggled.connect(func(v: bool) -> void:
		doc.edit("Опасный спуск", func() -> void:
			var rk: Array = doc.map.get("risky", [])
			rk = rk.filter(func(e: Dictionary) -> bool: return not MapDoc.same_pair(Array(e.get("pair", [])), a, b))
			if v:
				rk.append({"pair": [a, b], "name": "Спуск: %s — %s" % [doc.display_name(a), doc.display_name(b)], "req": {"power": 7}, "tags": ["climb"]})
			if rk.is_empty():
				doc.map.erase("risky")
			else:
				doc.map["risky"] = rk))
	_props.add_child(rc)
	var sets: Array = doc.map.get("path_sets", {}).get("sets", [])
	if not sets.is_empty():
		_props.add_child(UiTheme.label("Сети троп бури: в бурю открывается следующая сеть", 13, UiTheme.DIM, true))
		for i2 in sets.size():
			var sc := CheckBox.new()
			sc.text = "Есть в сети бури %d" % (i2 + 1)
			sc.button_pressed = Array(sets[i2]).any(func(e: Array) -> bool: return MapDoc.same_pair(e, a, b))
			var idx := i2
			sc.toggled.connect(func(v: bool) -> void:
				doc.edit("Сеть бури", func() -> void:
					var st: Array = doc.map.path_sets.sets[idx]
					st = st.filter(func(e: Array) -> bool: return not MapDoc.same_pair(e, a, b))
					if v:
						st.append([a, b])
					doc.map.path_sets.sets[idx] = st))
			_props.add_child(sc)
	_props.add_child(UiTheme.button("＋ Сеть троп бури", "Добавить сеть троп, которая включается в бурю (как в Главе 4)", func() -> void:
		doc.edit("Новая сеть бури", func() -> void:
			if not doc.map.has("path_sets"):
				doc.map["path_sets"] = {"storm_phase": "ash_storm", "sets": []}
			doc.map.path_sets.sets.append([[a, b]]))))


func _socket_props(i: int) -> void:
	_props.add_child(UiTheme.header("Площадка %d" % (i + 1)))
	_props.add_child(UiTheme.label("Сюда игра ставит места, которые появляются и исчезают (места отлива, котловины после бури, места событий). Площадку можно тащить.", 13, UiTheme.DIM, true))
	_sep(_props)
	_props.add_child(UiTheme.label("В каких группах эта площадка", 14))
	var ebb := CheckBox.new()
	ebb.text = "Площадки отлива (общие)"
	ebb.button_pressed = Array(doc.map.get("ebb_sockets", [])).has(i)
	ebb.toggled.connect(func(v: bool) -> void:
		doc.edit("Площадки отлива", func() -> void:
			var a: Array = doc.map.get("ebb_sockets", [])
			a.erase(i)
			if v:
				a.append(i)
				a.sort()
			doc.map["ebb_sockets"] = a))
	_props.add_child(ebb)
	var groups: Dictionary = doc.map.get("emerge_groups", {})
	for g: String in groups:
		var c := CheckBox.new()
		c.text = "Группа «%s»" % g
		c.button_pressed = Array(groups[g].get("sockets", [])).has(i)
		c.toggled.connect(func(v: bool) -> void:
			doc.edit("Группа площадок", func() -> void:
				var a2: Array = doc.map.emerge_groups[g].get("sockets", [])
				a2.erase(i)
				if v:
					a2.append(i)
					a2.sort()
				doc.map.emerge_groups[g]["sockets"] = a2))
		_props.add_child(c)
	# предпросмотр (ФТ-22): поставить появляющееся место и увидеть, к какому месту игра проведёт тропу
	var em: Array = doc.locations.keys().filter(func(l: String) -> bool: return doc.is_emerging(l) and doc.places().has(l))
	if not em.is_empty():
		_sep(_props)
		_props.add_child(UiTheme.label("Предпросмотр: поставить сюда появляющееся место", 14))
		var ob := OptionButton.new()
		ob.add_item("— никого —")
		ob.set_item_metadata(0, "")
		var cur := 0
		for l2: String in em:
			ob.add_item(doc.display_name(l2))
			ob.set_item_metadata(ob.item_count - 1, l2)
			if int(canvas.sim.emerged.get(l2, -1)) == i:
				cur = ob.item_count - 1
		ob.select(cur)
		ob.item_selected.connect(func(k: int) -> void:
			for l3: String in canvas.sim.emerged.keys():
				if int(canvas.sim.emerged[l3]) == i:
					canvas.sim.emerged.erase(l3)
			var pick := str(ob.get_item_metadata(k))
			if pick != "":
				canvas.sim.emerged[pick] = i
				var near := canvas.sim.nearest_permanent(canvas.sim.anchor(pick), pick)
				message.emit("«%s» на площадке %d — игра соединит его тропой с «%s» (ближайшее постоянное место)." % [doc.display_name(pick), i + 1, doc.display_name(near)])
			canvas.queue_redraw())
		_props.add_child(ob)
	_sep(_props)
	var del := UiTheme.button("Убрать площадку", "Номера остальных площадок пересчитаются, группы обновятся", func() -> void:
		doc.edit("Убрать площадку", func() -> void: doc.remove_socket(i))
		canvas.select_thing({}))
	del.add_theme_color_override("font_color", UiTheme.ERROR)
	_props.add_child(del)


const PHASE_LIST := ["day", "dawn", "dusk", "night", "storm", "blood_moon", "ash_storm"]


## Метка (ФТ-27): условия — фазы недели, с какого дня, только если место открыто, вариант места.
func _decal_props(d: Variant) -> void:
	_props.add_child(UiTheme.header("Метка"))
	if not d is Dictionary:
		return
	var dd: Dictionary = d
	var row := HBoxContainer.new()
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(72, 72)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture = cache.map_tex(canvas.src, str(dd.get("decal", "")), 128)
	row.add_child(t)
	var where := "у места %s" % Words.q(doc.display_name(str(dd.place))) if dd.has("place") else "на тропе"
	row.add_child(UiTheme.label("%s\n%s" % [str(dd.get("decal", "")).trim_prefix("decal_").replace("_", " "), where], 14, UiTheme.TEXT, true))
	_props.add_child(row)
	_sep(_props)
	_props.add_child(UiTheme.label("Когда видна (ничего не отмечено — всегда)", 14))
	var flow := HFlowContainer.new()
	for ph: String in PHASE_LIST:
		var c := CheckBox.new()
		c.text = Words.phase(ph)
		c.button_pressed = Array(dd.get("phase", [])).has(ph)
		c.toggled.connect(func(v: bool) -> void:
			doc.edit("Условие метки", func() -> void:
				var a: Array = dd.get("phase", [])
				a.erase(ph)
				if v:
					a.append(ph)
				if a.is_empty():
					dd.erase("phase")
				else:
					dd["phase"] = a))
		flow.add_child(c)
	_props.add_child(flow)
	var dr := HBoxContainer.new()
	dr.add_child(UiTheme.label("С какого дня главы", 14))
	var sp := SpinBox.new()
	sp.min_value = 0
	sp.max_value = 60
	sp.value = int(dd.get("from_day", 0))
	sp.tooltip_text = "0 — с первого дня"
	sp.value_changed.connect(func(v: float) -> void:
		doc.edit("Условие метки", func() -> void:
			if int(v) <= 0:
				dd.erase("from_day")
			else:
				dd["from_day"] = int(v)))
	dr.add_child(sp)
	_props.add_child(dr)
	if dd.has("place"):
		var oc := CheckBox.new()
		oc.text = "Только когда место уже открыто игроку"
		oc.button_pressed = bool(dd.get("open", false))
		oc.toggled.connect(func(v: bool) -> void:
			doc.edit("Условие метки", func() -> void:
				if v:
					dd["open"] = true
				else:
					dd.erase("open")))
		_props.add_child(oc)
	_sep(_props)
	var del := UiTheme.button("Убрать метку", "", func() -> void:
		doc.edit("Убрать метку", func() -> void:
			for key: String in ["place_decals", "path_decals"]:
				if doc.map.has(key):
					doc.map[key].erase(dd))
		canvas.select_thing({}))
	del.add_theme_color_override("font_color", UiTheme.ERROR)
	_props.add_child(del)


## Облики по фазе недели и событиям (ФТ-28): какой облик у места в эту фазу.
func _phase_looks(lid: String) -> void:
	var sts := doc.states(lid)
	if sts.size() < 2:
		return
	_sep(_props)
	_props.add_child(UiTheme.label("Облик по фазе недели", 14))
	_props.add_child(UiTheme.label("Например: Древо светится ночью. Посмотреть — переключатель «Фаза» сверху.", 12, UiTheme.DIM, true))
	var ps: Dictionary = doc.map.get("phase_states", {}).get(lid, {})
	for ph: String in PHASE_LIST:
		var row := HBoxContainer.new()
		var l := UiTheme.label(Words.phase(ph), 13)
		l.custom_minimum_size = Vector2(120, 0)
		row.add_child(l)
		var ob := OptionButton.new()
		ob.add_item("как обычно")
		ob.set_item_metadata(0, "")
		var cur := 0
		for st: String in sts:
			ob.add_item(Words.state(st))
			ob.set_item_metadata(ob.item_count - 1, st)
			if str(ps.get(ph, "")) == st:
				cur = ob.item_count - 1
		ob.select(cur)
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.item_selected.connect(func(k: int) -> void:
			doc.edit("Облик по фазе", func() -> void:
				var all: Dictionary = doc.map.get("phase_states", {})
				var mine: Dictionary = all.get(lid, {})
				var st2 := str(ob.get_item_metadata(k))
				if st2 == "":
					mine.erase(ph)
				else:
					mine[ph] = st2
				if mine.is_empty():
					all.erase(lid)
				else:
					all[lid] = mine
				if all.is_empty():
					doc.map.erase("phase_states")
				else:
					doc.map["phase_states"] = all))
		row.add_child(ob)
		_props.add_child(row)
	var evs: Array = Array(doc.map.get("event_states", [])).filter(func(e: Dictionary) -> bool: return str(e.get("place", "")) == lid)
	for es: Dictionary in evs:
		var parts: Array = []
		if es.has("phase"):
			parts.append(", ".join(Array(es.phase).map(func(x: String) -> String: return Words.phase(x))))
		if bool(es.get("camp", false)):
			parts.append("когда здесь лагерь")
		if es.has("from_day"):
			parts.append("с дня %d" % int(es.from_day))
		_props.add_child(UiTheme.label("• %s — %s" % [Words.state(str(es.get("state", ""))), "; ".join(parts) if not parts.is_empty() else "по событию"], 12, UiTheme.DIM, true))


## Хрупкий проход и лавка (ФТ-16, 19).
func _place_extras(lid: String) -> void:
	_sep(_props)
	var fr := CheckBox.new()
	fr.text = "Хрупкий проход (мост) — рушится после нескольких переходов"
	fr.button_pressed = doc.map.get("fragile", {}).has(lid)
	fr.toggled.connect(func(v: bool) -> void:
		doc.edit("Хрупкий проход", func() -> void:
			var f: Dictionary = doc.map.get("fragile", {})
			if v:
				f[lid] = {"crossings": 4, "storm": false, "warn": "cracked"}
			else:
				f.erase(lid)
			if f.is_empty():
				doc.map.erase("fragile")
			else:
				doc.map["fragile"] = f))
	_props.add_child(fr)
	if doc.map.get("fragile", {}).has(lid):
		var fd: Dictionary = doc.map.fragile[lid]
		_slider(_props, "Сколько переходов выдержит", "После стольких переходов проход трескается, затем рушится", 1, 10, 1, float(fd.get("crossings", 4)),
			func(v: float) -> String: return Words.steps(int(v)).replace("шаг", "переход"), func(v: float) -> void: doc.map.fragile[lid]["crossings"] = int(v), "Хрупкий проход")
	if doc.game != "":
		var sc := CheckBox.new()
		sc.text = "Это лавка (пройти можно, встать лагерем — нет)"
		sc.button_pressed = doc.is_shop(lid)
		sc.toggled.connect(func(v: bool) -> void: _make_shop(lid, v))
		_props.add_child(sc)


func _make_shop(lid: String, on: bool) -> void:
	if on:
		var tmpl := GameIO.game_shop_template(doc.game, doc.chapter)
		if tmpl.is_empty():
			message.emit("В игре нет ни одной лавки, с которой можно взять ассортимент.")
			queue_rebuild()
			return
		doc.edit("Лавка", func() -> void:
			var loc: Dictionary = doc.locations.get(lid, {})
			var sh := {"id": lid, "chapter": doc.chapter if doc.chapter != "" else str(loc.get("chapter", doc.region)),
				"name": doc.display_name(lid), "text": str(loc.get("text", "")), "pos": doc.place(lid).get("at", [0.5, 0.5])}
			for k: String in ["slots", "min_characters", "refresh_every", "stock", "services"]:
				if tmpl.has(k):
					sh[k] = tmpl[k]
			doc.shops[lid] = sh
			doc.locations.erase(lid))
		message.emit("«%s» теперь лавка. Ассортимент взят из лавки «%s» — поменять можно в редакторе контента игры." % [doc.display_name(lid), tmpl.get("name", "")])
	else:
		doc.edit("Не лавка", func() -> void:
			var sh2: Dictionary = doc.shops.get(lid, {})
			doc.shops.erase(lid)
			doc.locations[lid] = doc.new_location(lid, str(sh2.get("name", lid)), doc.at(lid)))


## Вода и прилив (ФТ-23, 24): уровни — словами, числа только в «Подробно».
func _water_props() -> void:
	_sep(_map)
	var has := doc.map.has("height")
	var wc := CheckBox.new()
	wc.text = "На карте есть вода и прилив"
	wc.button_pressed = has
	wc.tooltip_text = "Вода рисуется по карте высот. Перетащите карту высот из пака на холст — вода включится сама."
	wc.toggled.connect(func(v: bool) -> void:
		doc.edit("Вода", func() -> void:
			if v:
				doc.map["height"] = "height.png"
				doc.map["water"] = doc.map.get("water", "water_tile.webp")
				doc.map["levels"] = doc.map.get("levels", {"normal": 55, "warn": 68, "flood": 115, "storm": 140})
			else:
				for k: String in ["height", "water", "levels"]:
					doc.map.erase(k)))
	_map.add_child(wc)
	if not has:
		return
	var lv: Dictionary = doc.map.get("levels", {})
	var names := {"normal": "Обычная кромка воды", "warn": "Вода подступает", "flood": "Прилив", "storm": "Штормовой прилив"}
	var word := func(v: float) -> String:
		if v < 50:
			return "низко"
		if v < 90:
			return "у берега"
		if v < 130:
			return "заливает низины"
		return "заливает и средние"
	for k2: String in names:
		_slider(_map, names[k2], "Уровень воды по карте высот (всё ниже — под водой). Включите режим «Прилив», чтобы увидеть.", 0, 255, 1,
			float(lv.get(k2, 55)), word, func(v: float) -> void:
				var l2: Dictionary = doc.map.get("levels", {})
				l2[k2] = int(v)
				doc.map["levels"] = l2, "Уровень воды")


## Группы появляющихся мест (ФТ-21): когда поднимаются, сколько, когда уходят.
func _groups_props() -> void:
	_sep(_map)
	_map.add_child(UiTheme.label("Группы появляющихся мест", 14, UiTheme.ACCENT))
	_map.add_child(UiTheme.label("Какие площадки в группе — отмечается у площадки (щёлкните её на холсте).", 12, UiTheme.DIM, true))
	var groups: Dictionary = doc.map.get("emerge_groups", {})
	for g: String in groups:
		var grp: Dictionary = groups[g]
		var box := VBoxContainer.new()
		box.add_child(UiTheme.label("«%s» — площадок: %d" % [g, Array(grp.get("sockets", [])).size()], 14))
		var row := HBoxContainer.new()
		row.add_child(UiTheme.label("Поднимаются:", 13))
		var ph := OptionButton.new()
		for p: String in PHASE_LIST:
			ph.add_item(Words.phase(p))
			ph.set_item_metadata(ph.item_count - 1, p)
			if str(grp.get("phase", "")) == p:
				ph.select(ph.item_count - 1)
		ph.item_selected.connect(func(k: int) -> void: doc.edit("Группа", func() -> void: doc.map.emerge_groups[g]["phase"] = str(ph.get_item_metadata(k))))
		row.add_child(ph)
		row.add_child(UiTheme.label("уходят после:", 13))
		var sk := OptionButton.new()
		for p2: String in PHASE_LIST:
			sk.add_item(Words.phase(p2))
			sk.set_item_metadata(sk.item_count - 1, p2)
			if str(grp.get("sink_after", "")) == p2:
				sk.select(sk.item_count - 1)
		sk.item_selected.connect(func(k: int) -> void: doc.edit("Группа", func() -> void: doc.map.emerge_groups[g]["sink_after"] = str(sk.get_item_metadata(k))))
		row.add_child(sk)
		box.add_child(row)
		var row2 := HBoxContainer.new()
		row2.add_child(UiTheme.label("сколько мест:", 13))
		var cnt: Array = grp.get("count", [1, 1])
		for j in 2:
			var s := SpinBox.new()
			s.min_value = 0
			s.max_value = 6
			s.value = int(cnt[j]) if cnt.size() > j else 1
			s.tooltip_text = "от" if j == 0 else "до"
			var jj := j
			s.value_changed.connect(func(v: float) -> void:
				doc.edit("Группа", func() -> void:
					var c2: Array = doc.map.emerge_groups[g].get("count", [1, 1]).duplicate()
					c2[jj] = int(v)
					doc.map.emerge_groups[g]["count"] = c2))
			row2.add_child(s)
		row2.add_child(UiTheme.label("день фазы:", 13))
		var di := SpinBox.new()
		di.min_value = 1
		di.max_value = 7
		di.value = int(grp.get("day_in", 1))
		di.value_changed.connect(func(v: float) -> void: doc.edit("Группа", func() -> void: doc.map.emerge_groups[g]["day_in"] = int(v)))
		row2.add_child(di)
		box.add_child(row2)
		box.add_child(UiTheme.button("Убрать группу «%s»" % g, "", func() -> void: doc.edit("Убрать группу", func() -> void: doc.map.emerge_groups.erase(g))))
		_map.add_child(box)
	var nr := HBoxContainer.new()
	var ne := LineEdit.new()
	ne.placeholder_text = "имя новой группы (латиницей)"
	ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nr.add_child(ne)
	nr.add_child(UiTheme.button("＋ Группа", "", func() -> void:
		var gid := TexPack.slug(ne.text if ne.text != "" else "group")
		doc.edit("Новая группа", func() -> void:
			if not doc.map.has("emerge_groups"):
				doc.map["emerge_groups"] = {}
			doc.map.emerge_groups[gid] = {"sockets": [], "phase": "dawn", "day_in": 1, "count": [1, 1], "sink_after": "storm"})))
	_map.add_child(nr)
