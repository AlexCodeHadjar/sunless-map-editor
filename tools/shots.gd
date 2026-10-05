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
