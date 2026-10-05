extends Node
## Автоснимки окна редактора (проверка интерфейса без рук):
## godot --path . --resolution 1600x900 -- --shots=<папка> [--shots-from=<сценарий>]
## Сценарии: main (по умолчанию) — Берег из игры, выделение, граф, маршрут, проверки.

var out_dir := ""
var scenario := "main"
var main: Control


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out_dir = a.substr(8)
		if a.begins_with("--shots-from="):
			scenario = a.substr(13)
	if out_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func shot(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("[shots] ", name)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## Подождать, пока догрузятся картинки.
func settle(max_sec: float = 15.0) -> void:
	var t := 0.0
	await wait(0.3)
	while main.cache.is_loading() and t < max_sec:
		await wait(0.2)
		t += 0.2
	await wait(0.3)


func _run() -> void:
	main = get_tree().current_scene
	await wait(0.5)
	match scenario:
		"main":
			await _main_flow()
		"new":
			await _new_flow()
		"v2":
			await _v2_flow()
		"v3":
			await _v3_flow()
		"examples":
			await _examples_flow()
	get_tree().quit()


func _main_flow() -> void:
	var g: String = main.game_dir()
	main.open_game_region(g, "forgotten_shore")
	await settle()
	await shot("01_shore")
	main.canvas.select_place("coral_maze")
	main.props.rebuild()
	await settle()
	await shot("02_place_selected")
	main.mode_buttons.graph.button_pressed = true
	main.canvas.select_place("stone_isle")
	await settle()
	await shot("03_graph")
	main.mode_buttons.graph.button_pressed = false
	main.mode_buttons.route.button_pressed = true
	main.canvas.route_from = "stone_isle"
	main.canvas.route_to = "bone_ridge" if main.doc.places().has("bone_ridge") else "spire_view"
	main.canvas._route_status()
	await settle()
	await shot("04_route")
	main.mode_buttons.route.button_pressed = false
	main.run_checks()
	await settle()
	await shot("05_checks")
	main.packs.select_pack("game_forgotten_shore")
	await settle()
	await shot("06_packs")


## Новая карта с нуля из комплектов игры: основа, места, тропы, проверка, диалог экспорта.
func _new_flow() -> void:
	var g: String = main.game_dir()
	var kit: TexPack = main.lib.add(g + "/docs/assets/kits/sunless-chapter4-map-kit")
	var ev: TexPack = main.lib.add(g + "/docs/assets/kits/sunless-map-events-kit")
	main.packs.refresh_packs()
	var d := MapDoc.new_map("demo_valley")
	d.chapter = "demo_valley"
	d.game = g
	main.set_doc(d)
	await settle()
	await shot("10_new_empty")
	var c: MapCanvas = main.canvas
	c._drop_data(c.to_screen(Vector2(0.5, 0.5)), {"type": "tex", "pack": kit.id, "tex": "base"})
	await settle()
	await shot("11_new_base")
	var spots := {"ash_dunes": Vector2(0.25, 0.3), "stone_hulk": Vector2(0.45, 0.45), "death_beacon": Vector2(0.62, 0.3),
		"soul_tree": Vector2(0.78, 0.55), "lake_shore": Vector2(0.55, 0.7), "boat_cove": Vector2(0.3, 0.72)}
	for pl: String in spots:
		c._drop_data(c.to_screen(spots[pl]), {"type": "tex", "pack": kit.id, "tex": pl + "_dry"})
	c._drop_data(c.to_screen(Vector2(0.88, 0.3)), {"type": "tex", "pack": ev.id, "tex": "strangers_camp_occupied"})
	await settle()
	await shot("12_new_places")
	var ids: Array = d.places().keys()
	for i in ids.size() - 1:
		d.edit("Тропа", func() -> void: d.toggle_path(ids[i], ids[i + 1]))
	d.edit("Тропа", func() -> void: d.toggle_path(ids[0], ids[2]))
	c.select_place(ids[1])
	await settle()
	await shot("13_new_paths")
	main.run_checks()
	await settle()
	await shot("14_new_checks")
	main.export_dialog()
	await settle(30.0)
	await wait(1.0)
	await shot("15_export_dialog")


## v2: прилив, туман и шаг фигуры, режим «Игра», площадка с появляющимся местом, метка, Глава 4.
func _v2_flow() -> void:
	var g: String = main.game_dir()
	main.open_game_region(g, "forgotten_shore")
	await settle()
	main.mode_buttons.tide.button_pressed = true
	main.tide_pick.select(2)
	main.tide_pick.item_selected.emit(2)
	await settle()
	await shot("20_tide_flood")
	main.mode_buttons.tide.button_pressed = false
	main.mode_buttons.step.button_pressed = true
	main.mode_buttons.fog.button_pressed = true
	main.canvas.sim.visited = ["stone_isle", "low_tide"]
	main.canvas.step_from = "low_tide"
	await settle()
	await shot("21_fog_step")
	main.mode_buttons.step.button_pressed = false
	main.mode_buttons.fog.button_pressed = false
	main.canvas.select_place("stone_isle")
	main._game_view()
	await settle()
	await wait(1.0)
	await shot("22_game_view")
	for w in main.get_children():
		if w is GameView:
			w.queue_free()
	await wait(0.3)
	main.canvas.sim.emerged["strangers_camp"] = 2
	main.canvas.select_thing({"kind": "socket", "id": 2})
	main.props.rebuild()
	await settle()
	await shot("23_socket_emerge")
	var dc: Dictionary = main.doc.map.place_decals[0]
	main.canvas.select_thing({"kind": "decal", "id": dc})
	main.props.rebuild()
	await settle()
	await shot("24_decal")
	main.open_game_region(g, "ash_path")
	main.boat_box.button_pressed = true
	main.phase_pick.select(4)
	main.phase_pick.item_selected.emit(4)
	main.canvas.select_place("soul_tree")
	main.props.rebuild()
	await settle()
	await shot("25_ash_path_night")
	main.props.current_tab = 1
	await settle()
	await shot("26_map_tab")


## v3: зоны и подвижные угрозы (Мрачный город), угрозы-точки (Город людей), погода, кисть высот (Берег).
func _v3_flow() -> void:
	var g: String = main.game_dir()
	main.open_game_region(g, "dark_city")
	main.phase_pick.select(4)
	main.phase_pick.item_selected.emit(4)
	var zid: String = main.doc.map.zones.keys()[0]
	main.canvas.select_thing({"kind": "zone", "id": zid})
	main.props.rebuild()
	await settle()
	await shot("30_zone")
	var mid: String = main.doc.map.movers.keys()[0]
	main.canvas.select_thing({"kind": "mover", "id": mid})
	main.props.rebuild()
	await settle()
	await shot("31_mover")
	main.open_game_region(g, "real_city")
	main.canvas.select_thing({})
	main.props.rebuild()
	main.props.current_tab = 1
	await settle()
	var sc: ScrollContainer = main.props.get_child(1)
	sc.scroll_vertical = 100000
	await settle()
	await shot("32_threat_table")
	main.open_game_region(g, "forgotten_shore")
	main.phase_pick.select(6)
	main.phase_pick.item_selected.emit(6)
	main.mode_buttons.tide.button_pressed = true
	main.tide_pick.select(2)
	main.tide_pick.item_selected.emit(2)
	var c: MapCanvas = main.canvas
	c.brush_size = 0.06
	c.brush_strength = 1.0
	c.brush_begin()
	for i in 12:
		c.brush_at(Vector2(0.43, 0.55), "raise")
	await settle()
	await shot("33_brush_weather")


## Примеры новых карт (examples/*.mapproj) в окне редактора.
func _examples_flow() -> void:
	var dir := ProjectSettings.globalize_path("res://examples")
	main.open_project(dir + "/night_shore.mapproj")
	main.phase_pick.select(6)
	main.phase_pick.item_selected.emit(6)
	main.canvas.select_place("ns_watch")
	main.props.rebuild()
	await settle()
	await shot("40_night_shore_blood_moon")
	main.open_project(dir + "/ash_pass.mapproj")
	main.phase_pick.select(4)
	main.phase_pick.item_selected.emit(4)
	main.canvas.select_thing({"kind": "zone", "id": "wrath"})
	main.props.rebuild()
	await settle()
	await shot("41_ash_pass_night")
	main.open_project(dir + "/gate_town.mapproj")
	main.mode_buttons.graph.button_pressed = true
	main.canvas.select_place("gt_bunker")
	main.props.rebuild()
	await settle()
	await shot("42_gate_town_graph")
