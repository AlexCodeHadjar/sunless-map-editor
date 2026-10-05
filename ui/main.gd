extends Control
## Главное окно редактора (ТЗ §4): меню, инструменты, паки слева, холст, свойства справа, строка состояния.

const SETTINGS := "user://settings.json"
const AUTOSAVE_SEC := 120.0

var lib: PackLibrary
var cache: TexCache
var doc: MapDoc
var src: TexSource
var settings: Dictionary = {}

var canvas: MapCanvas
var packs: PackPanel
var props: PropsPanel
var status_label: Label
var dirty_label: Label
var path_label: Label
var detailed_box: CheckBox
var tool_buttons: Dictionary = {}
var mode_buttons: Dictionary = {}
var phase_pick: OptionButton
var tide_pick: OptionButton
var boat_box: CheckBox
var sets_pick: OptionButton
var _menus: Dictionary = {}
var _autosave: Timer
var _busy: AcceptDialog


func _ready() -> void:
	theme = UiTheme.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_window().min_size = Vector2i(1100, 650)
	_load_settings()
	lib = PackLibrary.load_default()
	cache = TexCache.new()
	add_child(cache)
	_build()
	_autosave = Timer.new()
	_autosave.wait_time = AUTOSAVE_SEC
	_autosave.autostart = true
	_autosave.timeout.connect(_autosave_now)
	add_child(_autosave)
	get_window().files_dropped.connect(_on_files_dropped)
	var args := OS.get_cmdline_user_args()
	var opened := false
	for a: String in args:
		if a.ends_with(".mapproj") and FileAccess.file_exists(a):
			open_project(a)
			opened = true
		elif a.begins_with("--region="):
			open_game_region(game_dir(), a.substr(9))
			opened = true
	if not opened:
		var last := str(settings.get("last_project", ""))
		if last != "" and FileAccess.file_exists(last):
			open_project(last)
		else:
			set_doc(MapDoc.new_map("new_region"))
			doc.game = game_dir()
			doc.dirty = false
	_title()


# --- настройки -----------------------------------------------------------------------------------

func _load_settings() -> void:
	var s: Variant = JsonX.read_file(SETTINGS)
	settings = s if s is Dictionary else {}


func _save_settings() -> void:
	JsonX.write_file(SETTINGS, settings)


## Папка игры: из настроек, иначе соседняя ../SunLess.
func game_dir() -> String:
	var g := str(settings.get("game", ""))
	if g != "" and GameIO.is_game_dir(g):
		return g
	var sib := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir() + "/SunLess"
	return sib if GameIO.is_game_dir(sib) else ""


# --- раскладка -----------------------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(_build_menu())
	root.add_child(_build_toolbar())
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	packs = PackPanel.new()
	left.add_child(packs)
	split.add_child(left)
	var split2 := HSplitContainer.new()
	split.add_child(split2)
	canvas = MapCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(400, 300)
	split2.add_child(canvas)
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(360, 0)
	props = PropsPanel.new()
	props.clip_tabs = true
	right.add_child(props)
	split2.add_child(right)
	split2.split_offset = -10
	root.add_child(_build_status())
	packs.setup(lib, cache, canvas)
	packs.picked.connect(func(pid: String, tex: String) -> void: canvas.pack_pick = {"pack": pid, "tex": tex})
	packs.add_folder.connect(_add_pack_folder)
	packs.add_zip.connect(_add_pack_zip)
	packs.check_pack.connect(_check_pack)
	packs.message.connect(_say)
	canvas.status.connect(_say)
	canvas.selection_changed.connect(func() -> void: props.queue_rebuild())
	canvas.delete_requested.connect(_delete_selected)
	props.focus_place.connect(func(lid: String) -> void:
		canvas.select_place(lid)
		canvas.focus_place(lid))
	props.focus_thing.connect(func(s: Dictionary) -> void:
		canvas.select_thing(s)
		if s.get("kind", "") == "path":
			canvas.focus_place(str(s.id[0])))
	props.run_checks.connect(run_checks)
	props.message.connect(_say)


func _build_menu() -> Control:
	var bar := PanelContainer.new()
	var mb := MenuBar.new()
	bar.add_child(mb)
	_menu(mb, "Файл", [
		["Новый проект…", KEY_N, _new_project_dialog],
		["Открыть проект…", KEY_O, _open_project_dialog],
		["Открыть карту из игры…", 0, _open_game_dialog],
		[],
		["Сохранить", KEY_S, save],
		["Сохранить как…", 0, _save_as_dialog],
		[],
		["Экспорт в игру…", KEY_E, export_dialog],
		["Выбрать папку игры…", 0, _pick_game_dir],
		["Лишние картинки в папке игры…", 0, _unused_files],
		[],
		["Выход", 0, func() -> void: _quit()]])
	_menu(mb, "Правка", [
		["Отменить", KEY_Z, func() -> void: _undo()],
		["Повторить", KEY_Y, func() -> void: _redo()],
		[],
		["Удалить выделенное", 0, _delete_selected]])
	_menu(mb, "Вид", [
		["Показать всю карту", 0, func() -> void: canvas.fit()],
		["Режим «Граф»", 0, func() -> void: _toggle_mode("graph")],
		["Режим «Маршрут»", 0, func() -> void: _toggle_mode("route")],
		["Подробно (числа для знатоков)", 0, func() -> void: detailed_box.button_pressed = not detailed_box.button_pressed]])
	_menu(mb, "Паки", [
		["Подключить папку…", 0, _add_pack_folder],
		["Подключить архив .zip…", 0, _add_pack_zip],
		["Подключить комплекты игры (docs/assets/kits)", 0, _add_game_kits],
		["Картинки из генерации → «Мои текстуры»…", 0, func() -> void: _raw_import([])],
		["Обновить выбранный пак (что изменилось)", 0, _update_pack],
		["Проверить все паки", 0, func() -> void: _check_pack("")]])
	_menu(mb, "Проверка", [
		["Проверить карту", KEY_F7, run_checks],
		["Проверить игрой (тесты данных)", 0, func() -> void: _game_test("test_content")],
		["Тест игры «без тупиков»", 0, func() -> void: _game_test("test_travel")]])
	_menu(mb, "Справка", [
		["Как пользоваться", KEY_F1, _help],
		["О программе", 0, func() -> void: _info("О программе", "Редактор карт SunLess\nСборка карт глав из паков текстур, проверки как в игре, экспорт в data/maps и art/map.\n\nАгентский интерфейс: cli-anything-sunless-map (папка agent-harness).")]])
	return bar


func _menu(mb: MenuBar, title: String, items: Array) -> void:
	var pm := PopupMenu.new()
	pm.name = title
	mb.add_child(pm)
	var cbs: Array = []
	for it: Array in items:
		if it.is_empty():
			pm.add_separator()
			cbs.append(Callable())
			continue
		var key: int = it[1]
		pm.add_item(it[0], cbs.size())
		if key != 0:
			var sc := InputEventKey.new()
			sc.keycode = key
			sc.ctrl_pressed = key != KEY_F7 and key != KEY_F1
			sc.command_or_control_autoremap = sc.ctrl_pressed
			var shortcut := Shortcut.new()
			shortcut.events = [sc]
			pm.set_item_shortcut(pm.item_count - 1, shortcut, true)
		cbs.append(it[2])
	pm.id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < cbs.size() and (cbs[id] as Callable).is_valid():
			(cbs[id] as Callable).call())
	_menus[title] = pm


func _build_toolbar() -> Control:
	var bar := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)
	var group := ButtonGroup.new()
	var keys := {MapCanvas.Tool.SELECT: "V", MapCanvas.Tool.PLACE: "P", MapCanvas.Tool.PATH: "T", MapCanvas.Tool.SOCKET: "S",
		MapCanvas.Tool.DECAL: "D", MapCanvas.Tool.RUBBLE: "R", MapCanvas.Tool.ZONE: "Z", MapCanvas.Tool.ERASER: "E"}
	for t: int in MapCanvas.TOOL_NAMES:
		var b := Button.new()
		b.text = MapCanvas.TOOL_NAMES[t]
		b.toggle_mode = true
		b.button_group = group
		b.tooltip_text = "%s (%s)\n%s" % [MapCanvas.TOOL_NAMES[t], keys[t], MapCanvas.TOOL_HINTS[t]]
		b.button_pressed = t == MapCanvas.Tool.SELECT
		b.pressed.connect(func() -> void: canvas.set_tool(t))
		row.add_child(b)
		tool_buttons[t] = b
	row.add_child(VSeparator.new())
	var modes := {"graph": ["Граф", "Места кружками по высоте, тропы линиями, несвязанные — красным. Выделите место — числа шагов от него."],
		"route": ["Маршрут", "Щёлкните место-лагерь, потом цель: шаги до всех мест и кратчайший путь, как в игре."],
		"tide": ["Прилив", "Какие места уходят под воду и какие тропы закрыты при выбранной воде."],
		"fog": ["Туман", "Отметьте посещённые места (щелчком в режиме «Шаг фигуры») — видно, что откроется игроку."],
		"step": ["Шаг фигуры", "Щёлкните место фигуры: соседи серебром — можно, тёмно-красным — нельзя (с причиной). Щёлкните соседа — шаг."]}
	for m: String in modes:
		var b2 := Button.new()
		b2.text = modes[m][0]
		b2.toggle_mode = true
		b2.tooltip_text = modes[m][1]
		b2.toggled.connect(func(v: bool) -> void: _set_mode(m, v))
		row.add_child(b2)
		mode_buttons[m] = b2
	var game_b := UiTheme.button("Игра", "Окно 16:9 — как игрок увидит карту при старте", _game_view)
	row.add_child(game_b)
	row.add_child(VSeparator.new())
	phase_pick = OptionButton.new()
	phase_pick.tooltip_text = "Фаза недели: облики мест и метки по фазе"
	for ph: String in ["", "day", "dawn", "dusk", "night", "storm", "blood_moon", "ash_storm"]:
		phase_pick.add_item("Фаза: " + Words.phase(ph))
		phase_pick.set_item_metadata(phase_pick.item_count - 1, ph)
	phase_pick.item_selected.connect(func(i: int) -> void:
		canvas.sim.phase = str(phase_pick.get_item_metadata(i))
		canvas.queue_redraw())
	row.add_child(phase_pick)
	tide_pick = OptionButton.new()
	tide_pick.tooltip_text = "Уровень воды для режима «Прилив»"
	for td: String in Words.TIDES:
		tide_pick.add_item(str(Words.TIDES[td]).capitalize())
		tide_pick.set_item_metadata(tide_pick.item_count - 1, td)
	tide_pick.item_selected.connect(func(i: int) -> void:
		canvas.sim.tide = str(tide_pick.get_item_metadata(i))
		canvas.queue_redraw()
		_tide_status())
	tide_pick.visible = false
	row.add_child(tide_pick)
	sets_pick = OptionButton.new()
	sets_pick.tooltip_text = "Какая сеть троп бури сейчас (глава 4)"
	sets_pick.item_selected.connect(func(i: int) -> void:
		canvas.sim.path_set = i
		canvas.queue_redraw())
	sets_pick.visible = false
	row.add_child(sets_pick)
	boat_box = CheckBox.new()
	boat_box.text = "есть лодка"
	boat_box.tooltip_text = "Водные тропы проходимы только с лодкой"
	boat_box.toggled.connect(func(v: bool) -> void:
		canvas.sim.boat = v
		canvas.queue_redraw())
	boat_box.visible = false
	row.add_child(boat_box)
	return bar


func _build_status() -> Control:
	var bar := PanelContainer.new()
	var row := HBoxContainer.new()
	bar.add_child(row)
	status_label = UiTheme.label("", 13, UiTheme.TEXT)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	row.add_child(status_label)
	dirty_label = UiTheme.label("", 13, UiTheme.WARN)
	row.add_child(dirty_label)
	path_label = UiTheme.label("", 12, UiTheme.DIM)
	row.add_child(path_label)
	detailed_box = CheckBox.new()
	detailed_box.text = "Подробно"
	detailed_box.tooltip_text = "Показать технические числа и коды (координаты, коды мест). Обычно не нужно."
	detailed_box.toggled.connect(func(v: bool) -> void:
		canvas.detailed = v
		props.rebuild()
		canvas.queue_redraw())
	row.add_child(detailed_box)
	return bar


# --- документ ------------------------------------------------------------------------------------

func set_doc(d: MapDoc) -> void:
	doc = d
	src = TexSource.new(doc, lib)
	if doc.game == "":
		doc.game = game_dir()
	canvas.setup(doc, src, cache, lib)
	var ly: Dictionary = doc.editor.get("layers", {})
	for k: String in ly:
		canvas.layers[k] = ly[k]
	props.setup(doc, canvas, cache, lib)
	doc.changed.connect(func(_w: String) -> void:
		_title()
		canvas.queue_redraw())
	var sets: Array = doc.map.get("path_sets", {}).get("sets", [])
	sets_pick.clear()
	for i in sets.size():
		sets_pick.add_item("Сеть бури %d" % (i + 1))
	sets_pick.visible = not sets.is_empty()
	boat_box.visible = doc.map.has("water_paths")
	_title()


func _title() -> void:
	if doc == null:
		return
	var nm := doc.path.get_file() if doc.path != "" else "новый проект"
	get_window().title = "Редактор карт SunLess — %s (%s)%s" % [nm, doc.region, " *" if doc.dirty else ""]
	dirty_label.text = "изменено  " if doc.dirty else ""
	path_label.text = ("игра: " + doc.game) if doc.game != "" else "папка игры не выбрана"


func _say(t: String) -> void:
	status_label.text = t
	status_label.tooltip_text = t


func open_project(file: String) -> void:
	var d := MapDoc.load_project(file)
	if d == null:
		_info("Не открыть проект", "Файл повреждён или это не проект редактора:\n" + file + "\n" + JsonX.last_error)
		return
	_relink_packs(d)
	set_doc(d)
	settings["last_project"] = file
	_save_settings()
	_say("Открыт проект %s" % file.get_file())


## Паки проекта, которых нет в библиотеке, — подключить по сохранённому пути.
func _relink_packs(d: MapDoc) -> void:
	for p: Dictionary in d.packs:
		if lib.get_pack(str(p.get("id", ""))) == null and str(p.get("path", "")) != "":
			var path := str(p.path)
			if DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(path):
				lib.add(path, str(p.id))


## Запомнить паки, из которых взяты текстуры (id, версия, путь).
func _sync_packs() -> void:
	var used := {}
	for k: String in doc.textures:
		used[str(doc.source(k).get("pack", ""))] = true
	var out: Array = []
	for pid: String in used:
		var p: TexPack = lib.get_pack(pid)
		if p != null:
			out.append({"id": pid, "version": p.version, "path": p.root})
	doc.packs = out


func save() -> void:
	if doc.path == "":
		_save_as_dialog()
		return
	_sync_packs()
	doc.editor["view"] = [canvas.to_map(canvas.size / 2.0).x, canvas.to_map(canvas.size / 2.0).y, canvas.base_px]
	var err := doc.save()
	if err != "":
		_info("Не сохранить", err)
		return
	settings["last_project"] = doc.path
	_save_settings()
	_say("Проект сохранён: %s" % doc.path.get_file())
	_title()


func _autosave_now() -> void:
	if doc == null or not doc.dirty:
		return
	_sync_packs()
	if doc.path != "":
		doc.save()
		_say("Автосохранение: %s" % doc.path.get_file())
	else:
		var f := ProjectSettings.globalize_path("user://autosave/%s.mapproj" % doc.region)
		JsonX.write_file(f, doc.to_project())
		_say("Автосохранение (проект ещё без имени): %s" % f)
	_title()


func open_game_region(game: String, region: String) -> void:
	if not GameIO.is_game_dir(game):
		_info("Нет папки игры", "Выберите папку игры SunLess (меню «Файл» → «Выбрать папку игры»).")
		return
	var d := GameIO.open_region(game, region, lib)
	set_doc(d)
	packs.refresh_packs()
	_say("Открыта карта «%s» из игры: мест %d, троп %d. Картинки — из пака «Из игры: %s»." % [region, d.places().size(), d.paths().size(), region])
	canvas.fit()


# --- действия ------------------------------------------------------------------------------------

func _undo() -> void:
	if doc.undo():
		_say("Отменено")
	props.rebuild()


func _redo() -> void:
	if doc.redo():
		_say("Повторено")
	props.rebuild()


func _delete_selected() -> void:
	var s: Dictionary = canvas.sel
	match str(s.get("kind", "")):
		"place":
			var lid := str(s.id)
			var n := doc.path_places(lid).size()
			_confirm("Удалить место «%s»%s?" % [doc.display_name(lid), " вместе с его тропами (%d)" % n if n > 0 else ""], func() -> void:
				doc.edit("Удалить место", func() -> void: doc.remove_place(lid))
				canvas.select_thing({})
				_say("Место удалено (Ctrl+Z — вернуть)."))
		"path":
			var pr: Array = s.id
			doc.edit("Убрать тропу", func() -> void:
				if doc.has_path(str(pr[0]), str(pr[1])):
					doc.toggle_path(str(pr[0]), str(pr[1])))
			canvas.select_thing({})
		"socket":
			var i := int(s.id)
			doc.edit("Убрать площадку", func() -> void: doc.remove_socket(i))
			canvas.select_thing({})
		"decal":
			var d: Dictionary = s.id
			doc.edit("Убрать метку", func() -> void:
				for key: String in ["place_decals", "path_decals"]:
					if doc.map.has(key):
						doc.map[key].erase(d))
			canvas.select_thing({})
		"rubble":
			var rid := str(s.id)
			doc.edit("Убрать завал", func() -> void: doc.map.rubble.erase(rid))
			canvas.select_thing({})
		"zone":
			var zid := str(s.id)
			doc.edit("Убрать зону", func() -> void: doc.map.zones.erase(zid))
			canvas.select_thing({})


func run_checks() -> Array:
	var rows := MapChecks.run(doc, src)
	props.show_checks(rows)
	var ne := MapChecks.errors(rows).size()
	_say("Проверка: ошибок %d, предупреждений %d." % [ne, rows.size() - ne] if not rows.is_empty() else "Проверка: всё в порядке.")
	return rows


func _set_mode(m: String, on: bool) -> void:
	canvas.modes[m] = on
	if m == "route" and on:
		mode_buttons.step.button_pressed = false
		_say("Маршрут: щёлкните место-лагерь, затем цель.")
	if m == "step" and on:
		mode_buttons.route.button_pressed = false
		_say("Шаг фигуры: щёлкните место, где стоит фигура.")
	if m == "tide":
		tide_pick.visible = on
		if on and not doc.map.has("height"):
			_say("На этой карте нет воды (нет карты высот) — прилив ничего не меняет.")
	boat_box.visible = doc.map.has("water_paths") or canvas.modes.route or canvas.modes.step
	canvas.queue_redraw()


func _toggle_mode(m: String) -> void:
	mode_buttons[m].button_pressed = not mode_buttons[m].button_pressed


func _tide_status() -> void:
	var under: Array = []
	for lid: String in doc.places():
		if canvas.sim.flooded(lid):
			under.append(doc.display_name(lid))
	var land := doc.permanent().filter(func(l: String) -> bool: return not canvas.sim.flooded(l))
	var bad := MapGraph.unreachable(land, canvas.sim.links().filter(func(e: Array) -> bool: return land.has(e[0]) and land.has(e[1])))
	_say("%s: под водой %d мест%s. Сухая часть %s." % [Words.TIDES[canvas.sim.tide].capitalize(), under.size(),
		(" (" + ", ".join(under.slice(0, 5)) + ("…" if under.size() > 5 else "") + ")") if not under.is_empty() else "",
		"связана" if bad.is_empty() else "разорвана — не дойти до %d мест" % bad.size()])


func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.ctrl_pressed:
		match k.keycode:
			KEY_Z:
				if k.shift_pressed:
					_redo()
				else:
					_undo()
				accept_event()
			KEY_Y:
				_redo()
				accept_event()
		return
	var keys := {KEY_V: MapCanvas.Tool.SELECT, KEY_P: MapCanvas.Tool.PLACE, KEY_T: MapCanvas.Tool.PATH, KEY_S: MapCanvas.Tool.SOCKET,
		KEY_D: MapCanvas.Tool.DECAL, KEY_R: MapCanvas.Tool.RUBBLE, KEY_Z: MapCanvas.Tool.ZONE, KEY_E: MapCanvas.Tool.ERASER}
	if keys.has(k.keycode):
		var t: int = keys[k.keycode]
		tool_buttons[t].button_pressed = true
		canvas.set_tool(t)
		accept_event()
	elif k.keycode == KEY_DELETE:
		_delete_selected()
		accept_event()
	elif k.keycode == KEY_HOME:
		canvas.fit()
		accept_event()


# --- паки ----------------------------------------------------------------------------------------

func _add_pack_folder() -> void:
	_file_dialog(FileDialog.FILE_MODE_OPEN_DIR, [], "Папка пака", func(p: String) -> void: _added(lib.add(p)))


func _add_pack_zip() -> void:
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.zip ; Архив пака"], "Архив пака", func(p: String) -> void: _added(lib.add(p)))


func _added(p: TexPack) -> void:
	if p == null:
		return
	packs.refresh_packs()
	packs.select_pack(p.id)
	var rep := PackCheck.check(p)
	var ne := rep.filter(func(r: Dictionary) -> bool: return r.level == "error").size()
	_say("Пак «%s» подключён: текстур %d, мест %d%s." % [p.name, p.textures.size(), p.places().size(), ", ошибок в паке: %d (Паки → Проверить)" % ne if ne > 0 else ""])
	if not p.has_manifest and not p.is_zip:
		_confirm("У пака «%s» нет описания (pack.json). Редактор построил его по папкам и именам файлов. Сохранить описание в папку пака?" % p.name, func() -> void:
			var err := p.save_manifest()
			_say("Описание пака сохранено." if err == "" else err))


func _on_files_dropped(files: PackedStringArray) -> void:
	for f: String in files:
		if f.get_extension().to_lower() == "mapproj":
			open_project(f)
		elif f.get_extension().to_lower() == "zip" or DirAccess.dir_exists_absolute(f):
			_added(lib.add(f))
		elif f.get_extension().to_lower() in ["png", "webp", "jpg"]:
			_raw_import([f])
			return


func _add_game_kits() -> void:
	var g := game_dir()
	var kits := g + "/docs/assets/kits"
	if g == "" or not DirAccess.dir_exists_absolute(kits):
		_info("Нет комплектов", "В папке игры нет docs/assets/kits.")
		return
	var n := 0
	for d: String in DirAccess.get_directories_at(kits):
		lib.add(kits + "/" + d)
		n += 1
	packs.refresh_packs()
	_say("Подключено комплектов: %d" % n)


func _check_pack(pid: String) -> void:
	var rows: Array = []
	var list: Array = [lib.get_pack(pid)] if pid != "" else lib.enabled_packs()
	for p: TexPack in list:
		if p != null:
			rows.append_array(PackCheck.check(p, true))
	if pid == "":
		rows.append_array(PackCheck.duplicates(lib.enabled_packs()))
	var text := "Замечаний нет — пак в порядке." if rows.is_empty() else "\n".join(rows.map(func(r: Dictionary) -> String:
		return ("✖ " if r.level == "error" else "⚠ ") + str(r.text) + (("\n      " + str(r.file)) if str(r.file) != "" else "")))
	_info("Проверка пака", text)


# --- диалоги -------------------------------------------------------------------------------------

func _file_dialog(mode: int, filters: Array, title: String, cb: Callable, save_name: String = "") -> void:
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = mode
	fd.title = title
	fd.use_native_dialog = true
	fd.filters = PackedStringArray(filters)
	if save_name != "":
		fd.current_file = save_name
	var g := game_dir()
	if g != "":
		fd.current_dir = g.get_base_dir()
	fd.file_selected.connect(func(p: String) -> void: cb.call(p))
	fd.files_selected.connect(func(ps: PackedStringArray) -> void: cb.call(ps))
	fd.dir_selected.connect(func(p: String) -> void: cb.call(p))
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.6)


func _info(title: String, text: String) -> void:
	var d := AcceptDialog.new()
	d.title = title
	d.dialog_text = text
	d.dialog_autowrap = true
	d.min_size = Vector2i(560, 160)
	d.max_size = Vector2i(900, 700)
	add_child(d)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	d.popup_centered()


func _confirm(text: String, yes: Callable, ok_text: String = "Да") -> void:
	var d := ConfirmationDialog.new()
	d.title = "Подтвердите"
	d.dialog_text = text
	d.dialog_autowrap = true
	d.min_size = Vector2i(480, 150)
	d.ok_button_text = ok_text
	d.cancel_button_text = "Отмена"
	add_child(d)
	d.confirmed.connect(func() -> void:
		yes.call()
		d.queue_free())
	d.canceled.connect(d.queue_free)
	d.popup_centered()


func _open_project_dialog() -> void:
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.mapproj ; Проект карты"], "Открыть проект", open_project)


func _save_as_dialog() -> void:
	_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.mapproj ; Проект карты"], "Сохранить проект", func(p: String) -> void:
		if p.get_extension() != "mapproj":
			p += ".mapproj"
		doc.path = p
		save(), doc.region + ".mapproj")


func _pick_game_dir() -> void:
	_file_dialog(FileDialog.FILE_MODE_OPEN_DIR, [], "Папка игры SunLess", func(p: String) -> void:
		if not GameIO.is_game_dir(p):
			_info("Это не папка игры", "В папке игры должны быть project.godot и data/.")
			return
		settings["game"] = p
		_save_settings()
		if doc != null:
			doc.game = p
		_title())


func _open_game_dialog() -> void:
	var g := game_dir()
	if g == "":
		_pick_game_dir()
		return
	var regs := GameIO.regions(g)
	var d := ConfirmationDialog.new()
	d.title = "Открыть карту из игры"
	d.ok_button_text = "Открыть"
	d.cancel_button_text = "Отмена"
	var v := VBoxContainer.new()
	v.add_child(UiTheme.label("Какую карту открыть? Картинки останутся из папки игры (пак «Из игры»).", 14, UiTheme.TEXT, true))
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(520, 260)
	var ids: Array = []
	for r: String in regs:
		var info: Dictionary = regs[r]
		if not bool(info.map):
			continue
		list.add_item("%s — глава «%s», мест: %d" % [r, info.chapter, int(info.places)])
		ids.append(r)
	if not ids.is_empty():
		list.select(0)
	v.add_child(list)
	d.add_child(v)
	add_child(d)
	d.confirmed.connect(func() -> void:
		var s := list.get_selected_items()
		if not s.is_empty():
			open_game_region(g, ids[s[0]])
		d.queue_free())
	list.item_activated.connect(func(i: int) -> void:
		open_game_region(g, ids[i])
		d.hide()
		d.queue_free())
	d.canceled.connect(d.queue_free)
	d.popup_centered()


func _new_project_dialog() -> void:
	var d := ConfirmationDialog.new()
	d.title = "Новая карта"
	d.ok_button_text = "Создать"
	d.cancel_button_text = "Отмена"
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(520, 0)
	v.add_child(UiTheme.label("Название региона латиницей (так будут называться файл карты и папка картинок), например: ash_valley", 14, UiTheme.TEXT, true))
	var reg := LineEdit.new()
	reg.placeholder_text = "new_region"
	v.add_child(reg)
	v.add_child(UiTheme.label("Глава игры (для списка мест). Можно оставить как регион.", 14, UiTheme.TEXT, true))
	var ch := LineEdit.new()
	v.add_child(ch)
	v.add_child(UiTheme.label("Дальше: перетащите основу из пака на холст, потом облики мест.", 13, UiTheme.DIM, true))
	d.add_child(v)
	add_child(d)
	d.confirmed.connect(func() -> void:
		var r := TexPack.slug(reg.text if reg.text.strip_edges() != "" else "new_region")
		var nd := MapDoc.new_map(r)
		nd.chapter = ch.text.strip_edges() if ch.text.strip_edges() != "" else r
		nd.game = game_dir()
		set_doc(nd)
		_say("Новая карта «%s». Перетащите основу из пака (вид «Основы») на холст." % r)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	d.popup_centered()


# --- экспорт -------------------------------------------------------------------------------------

func export_dialog() -> void:
	if not GameIO.is_game_dir(doc.game):
		_info("Нет папки игры", "Выберите папку игры: «Файл» → «Выбрать папку игры».")
		return
	var rows := run_checks()
	if not MapChecks.errors(rows).is_empty():
		_info("Сначала исправьте ошибки", "В карте есть ошибки — игра с ней не запустится. Список — справа, во вкладке «Проверки» (щелчок по строке покажет место).\nПроект можно сохранить и доделать позже.")
		return
	_say("Готовлю экспорт…")
	await get_tree().process_frame
	await get_tree().process_frame
	var pl := GameIO.plan(doc, lib)
	if not pl.errors.is_empty():
		_info("Экспорт невозможен", "\n".join(pl.errors))
		return
	var items: Array = pl.items
	var todo := items.filter(func(it: Dictionary) -> bool: return it.status in ["new", "changed"])
	var missing := items.filter(func(it: Dictionary) -> bool: return it.status == "missing")
	var d := ConfirmationDialog.new()
	d.title = "Экспорт в игру"
	d.ok_button_text = "Записать" if not todo.is_empty() else "Закрыть"
	d.cancel_button_text = "Отмена"
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(620, 0)
	if todo.is_empty():
		v.add_child(UiTheme.label("Игра уже содержит эту карту — менять нечего.", 15, UiTheme.OK, true))
	else:
		v.add_child(UiTheme.label("Будет записано в папку игры (%d файлов). Прежние версии сохранятся в резервной копии." % todo.size(), 14, UiTheme.TEXT, true))
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(600, 300)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for it: Dictionary in todo:
		list.add_item(("＋ новый  " if it.status == "new" else "✎ изменён  ") + str(it.rel))
	for it2: Dictionary in missing:
		var i := list.add_item("✖ нет картинки  " + str(it2.rel))
		list.set_item_custom_fg_color(i, UiTheme.ERROR)
	var same := items.size() - todo.size() - missing.size()
	list.add_item("без изменений: %d файлов" % same)
	v.add_child(list)
	var reimp := CheckBox.new()
	reimp.text = "После записи обновить картинки в игре (импорт Godot, ~20 с)"
	reimp.button_pressed = todo.any(func(it: Dictionary) -> bool: return it.status == "new" and str(it.rel).begins_with("art/"))
	v.add_child(reimp)
	d.add_child(v)
	add_child(d)
	d.confirmed.connect(func() -> void:
		d.queue_free()
		if todo.is_empty():
			return
		var res := GameIO.write(doc, items)
		var msg := "Записано файлов: %d." % res.written.size()
		if str(res.backup) != "":
			msg += "\nРезервная копия прежних файлов: " + str(res.backup)
		if not res.errors.is_empty():
			msg += "\n\nОшибки:\n" + "\n".join(res.errors)
		if reimp.button_pressed:
			msg += "\n\nИмпорт картинок в игре запущен — подождите."
			_run_godot(GameIO.reimport_args(doc.game), "Импорт картинок игры")
		_info("Экспорт готов", msg)
		_say("Экспорт в игру: записано %d файлов." % res.written.size()))
	d.canceled.connect(d.queue_free)
	d.max_size = Vector2i(900, 640)
	d.popup_centered(Vector2i(700, 560))



## Запустить Godot (тот же, что редактор) по папке игры в фоне; итог — окном.
func _run_godot(args: PackedStringArray, title: String) -> void:
	var exe := OS.get_executable_path()
	_say(title + "…")
	var out: Array = []
	var task := WorkerThreadPool.add_task(func() -> void:
		var o: Array = []
		var code := OS.execute(exe, args, o, true)
		out.append(code)
		out.append("\n".join(o)))
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().create_timer(0.3).timeout
	WorkerThreadPool.wait_for_task_completion(task)
	var code2: int = out[0]
	var text: String = out[1]
	var lines := Array(text.split("\n")).filter(func(l: String) -> bool:
		return l.contains("ОК ") or l.contains("СБОЙ") or l.contains("Итого") or l.contains("×") or l.contains("maps/"))
	_say("%s: %s" % [title, "готово" if code2 == 0 else "есть ошибки"])
	_info(title, ("Готово." if code2 == 0 else "Есть ошибки.") + ("\n\n" + "\n".join(lines.slice(0, 40)) if not lines.is_empty() else ""))


func _game_test(only: String) -> void:
	if not GameIO.is_game_dir(doc.game):
		_info("Нет папки игры", "Выберите папку игры.")
		return
	_run_godot(GameIO.game_test_args(doc.game, only), "Проверка игрой (%s)" % only)


func _help() -> void:
	_info("Как пользоваться", "1. «Паки» → подключите папку с текстурами (или «Подключить комплекты игры»).\n2. «Файл» → «Открыть карту из игры» или «Новый проект».\n3. Перетащите основу из пака на холст, затем облики мест — появятся места. Бросьте облик на место — у места появится новый облик.\n4. Инструмент «Тропа» (T): щёлкните два места. Ещё раз — тропа уберётся.\n5. Инструмент «Площадка» (S): места для появляющихся мест.\n6. Справа — свойства: название, размер, высота над водой, лагерь.\n7. F7 — проверка (как в игре). Ctrl+E — экспорт в игру со списком изменений.\n\nКолесо мыши — масштаб, средняя кнопка или пробел + мышь — сдвиг. Ctrl+Z / Ctrl+Y — отмена и повтор. Home — вся карта.\nРежимы: «Граф» — связность, «Маршрут» — шаги и путь, «Прилив» — вода, «Шаг фигуры» — куда можно пойти, «Туман» — что видно игроку.")


func _quit() -> void:
	if doc != null and doc.dirty:
		_confirm("Есть несохранённые изменения. Сохранить проект перед выходом?", func() -> void:
			save()
			get_tree().quit(), "Сохранить и выйти")
		return
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave_now()


## Импорт «сырых» картинок из генерации (ФТ-06): мастер — вид, имя, облик, обрезка и центровка, хромакей.
func _raw_import(files: Array) -> void:
	if files.is_empty():
		_file_dialog(FileDialog.FILE_MODE_OPEN_FILES, ["*.png, *.webp, *.jpg ; Картинки"], "Картинки из генерации", func(p: Variant) -> void: _raw_import(Array(p) if p is PackedStringArray else [p]))
		return
	var queue: Array = files.duplicate()
	_raw_step(queue)


func _raw_step(queue: Array) -> void:
	if queue.is_empty():
		var p := lib.add(RawImport.pack_dir(), RawImport.PACK_ID, RawImport.PACK_NAME)
		lib.reload(p.id)
		packs.refresh_packs()
		packs.select_pack(p.id)
		_say("Картинки сохранены в пак «Мои текстуры» — их можно перетаскивать на карту.")
		return
	var file: String = queue.pop_front()
	var src_img := Image.load_from_file(file)
	if src_img == null:
		_info("Не открыть картинку", file)
		_raw_step(queue)
		return
	var d := ConfirmationDialog.new()
	d.title = "Новая картинка: " + file.get_file()
	d.ok_button_text = "Сохранить в «Мои текстуры»"
	d.cancel_button_text = "Пропустить"
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(640, 0)
	var row := HBoxContainer.new()
	var pv := TextureRect.new()
	pv.custom_minimum_size = Vector2(260, 260)
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(pv)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(UiTheme.label("Что это", 14))
	var kind := OptionButton.new()
	var kinds := ["place", "decal", "strip", "base", "height", "tile", "token"]
	for k: String in kinds:
		kind.add_item(str(Words.KINDS[k]).capitalize())
	var guess := TexPack.guess_kind(file.get_file().get_basename(), {"w": src_img.get_width(), "h": src_img.get_height()})
	kind.select(maxi(0, kinds.find(guess if guess != "" else "place")))
	form.add_child(kind)
	var sp := TexPack.split_state(TexPack.slug(file.get_file().get_basename()))
	form.add_child(UiTheme.label("Имя (латиницей): место, метка или основа", 14))
	var nm := LineEdit.new()
	nm.text = str(sp[0]) if not sp.is_empty() else TexPack.slug(file.get_file().get_basename())
	form.add_child(nm)
	form.add_child(UiTheme.label("Облик места", 14))
	var st := OptionButton.new()
	for s: String in TexPack.STATES:
		st.add_item("%s (%s)" % [Words.state(s), s])
		st.set_item_metadata(st.item_count - 1, s)
	var want := str(sp[1]) if not sp.is_empty() else "dry"
	for i in st.item_count:
		if str(st.get_item_metadata(i)) == want:
			st.select(i)
	form.add_child(st)
	var crop := CheckBox.new()
	crop.text = "Обрезать пустые края и поставить по центру квадрата"
	crop.button_pressed = true
	form.add_child(crop)
	var chroma := CheckBox.new()
	chroma.text = "Убрать пурпурный фон (хромакей)"
	var corner := src_img.get_pixel(1, 1)
	chroma.button_pressed = corner.r > 0.8 and corner.b > 0.8 and corner.g < 0.3
	form.add_child(chroma)
	var cut := CheckBox.new()
	cut.text = "Фишка: убрать землю под существом"
	form.add_child(cut)
	var strength := HSlider.new()
	strength.min_value = 0.1
	strength.max_value = 1.0
	strength.step = 0.05
	strength.value = 0.5
	strength.tooltip_text = "Сколько снизу убирать: левее — бережнее, правее — сильнее"
	form.add_child(strength)
	row.add_child(form)
	v.add_child(row)
	d.add_child(v)
	add_child(d)
	var result := [null]
	var refresh := func() -> void:
		var k2: String = kinds[kind.selected]
		var im := RawImport.prepare(src_img, k2, crop.button_pressed, chroma.button_pressed)
		if cut.button_pressed:
			im = RawImport.cut_base(im, strength.value)
		result[0] = im
		var small := im.duplicate()
		small.resize(260, maxi(1, int(260.0 * small.get_height() / small.get_width())))
		pv.texture = ImageTexture.create_from_image(small)
		st.disabled = k2 != "place"
		cut.visible = k2 == "token"
		strength.visible = k2 == "token" and cut.button_pressed
	for c: Control in [crop, chroma, cut]:
		(c as BaseButton).toggled.connect(func(_v: bool) -> void: refresh.call())
	kind.item_selected.connect(func(_i: int) -> void: refresh.call())
	strength.drag_ended.connect(func(_c: bool) -> void: refresh.call())
	refresh.call()
	d.confirmed.connect(func() -> void:
		var err := RawImport.save(result[0], kinds[kind.selected], nm.text, str(st.get_item_metadata(st.selected)))
		if err != "":
			_info("Не сохранить", err)
		d.queue_free()
		_raw_step(queue))
	d.canceled.connect(func() -> void:
		d.queue_free()
		_raw_step(queue))
	d.max_size = Vector2i(900, 700)
	d.popup_centered()


## Обновление пака (ФТ-04): новые, изменённые и пропавшие текстуры и где они в этой карте.
func _update_pack() -> void:
	var pid := packs._current_pack()
	if pid == "" or pid == PackPanel.ALL:
		_info("Обновить пак", "Выберите пак в списке слева.")
		return
	var df := lib.diff(pid)
	if df.is_empty():
		return
	cache.clear()
	var used := {}
	for k: String in doc.textures:
		var s := doc.source(k)
		if str(s.get("pack", "")) == pid:
			used[str(s.tex)] = k
	var lines: Array = []
	if df.version != df.version_was:
		lines.append("Версия пака: %d → %d" % [df.version_was, df.version])
	for key: String in ["new", "changed", "missing"]:
		var title: String = {"new": "Новые", "changed": "Изменённые", "missing": "Пропавшие"}[key]
		var arr: Array = df[key]
		if arr.is_empty():
			continue
		lines.append("%s (%d):" % [title, arr.size()])
		for nm: String in arr.slice(0, 30):
			lines.append("   %s%s" % [nm, ("  — в карте: " + str(used[nm])) if used.has(nm) else ""])
	if lines.is_empty():
		_info("Обновить пак", "В паке ничего не изменилось.")
		return
	packs.refresh_packs()
	canvas.queue_redraw()
	_confirm("Пак изменился:\n" + "\n".join(lines) + "\n\nПринять изменения (запомнить эту версию пака)?", func() -> void:
		lib.accept(pid)
		_say("Новая версия пака принята."), "Принять")


## Режим «Игра» (ФТ-40): окно 16:9 как у игрока.
func _game_view() -> void:
	var camp := ""
	if canvas.sel.get("kind", "") == "place":
		camp = str(canvas.sel.id)
	if camp == "":
		for lid: String in doc.places():
			if doc.height_of(lid) == "high" and not doc.is_shop(lid):
				camp = lid
				break
	if camp == "" and not doc.places().is_empty():
		camp = doc.places().keys()[0]
	GameView.open_for(self, doc, src, cache, lib, camp, true)
	_say("Фигура — у «%s» (выделите другое место перед «Игрой», чтобы поставить её туда). Карту можно сдвигать мышью." % doc.display_name(camp) if camp != "" else "")


## Лишние картинки в папке региона (ФТ-45): удалить — только с подтверждением.
func _unused_files() -> void:
	var unused := GameIO.unused_files(doc)
	if unused.is_empty():
		_info("Лишние картинки", "Все картинки в art/map/%s/ используются картой." % doc.region)
		return
	_confirm("Карта больше не использует %d картинок в art/map/%s/:\n%s\n\nУдалить их из папки игры? (Это нельзя отменить в редакторе; файлы под git можно вернуть через git.)" % [unused.size(), doc.region, "\n".join(unused.slice(0, 25))], func() -> void:
		var dir := "%s/art/map/%s/" % [doc.game, doc.region]
		var n := 0
		for f: String in unused:
			if DirAccess.remove_absolute(dir + f) == OK:
				n += 1
			DirAccess.remove_absolute(dir + f + ".import")
		_say("Удалено лишних картинок: %d" % n), "Удалить")
