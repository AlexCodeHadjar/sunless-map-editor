extends SceneTree
## «Открыть в игре» (ФТ-41): снимок карты настоящей отрисовкой игры (SleeperMap игры).
## Редактор копирует этот файл в <игра>/.map_editor_tmp/ и запускает:
##   godot --path <игра> --resolution 1920x1080 -s res://.map_editor_tmp/game_snapshot.gd -- --chapter C --camp ID --out file.png
## Скрипт работает внутри проекта игры: классы Content, RunState, SleeperMap — игровые.

var args := {}


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			args[a[i].substr(2)] = a[i + 1]
			i += 2
		else:
			i += 1
	_run.call_deferred()


func _run() -> void:
	var content: Variant = root.get_node_or_null("ContentDB")
	var c: Variant = content.get("data") if content != null else null
	if c == null:
		c = load("res://core/content/content.gd").call("load_from", "res://data")
	var chapter := str(args.get("chapter", ""))
	var state: Variant = load("res://core/state/run_state.gd").new()
	state.chapter = chapter
	state.party_at = str(args.get("camp", ""))
	var map_rules: Variant = load("res://core/rules/map_rules.gd")
	var cfg: Dictionary = map_rules.call("config", c, chapter)
	if cfg.is_empty():
		print("@@SNAPSHOT@@{\"ok\": false, \"error\": \"у главы нет карты-плана\"}")
		quit(1)
		return
	var size := Vector2(1920, 1080)
	var sm_script: Variant = load("res://scenes/map/sleeper_map.gd")
	var sm: Variant = sm_script.call("make", cfg, Rect2(Vector2.ZERO, size))
	var holder := Control.new()
	holder.size = size
	root.add_child(holder)
	holder.add_child(sm)
	if "figure_mode" in sm:
		sm.set("figure_mode", true)
	for k in 3:
		await process_frame
	sm.call("sync", c, state, str(args.get("sky", "night")))
	if state.party_at != "":
		sm.call("focus", sm.call("center", c, state, state.party_at), size / 2.0)
	# проявление мест и туман — дать дорисоваться
	await create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := str(args.get("out", "user://snapshot.png"))
	img.save_png(out)
	print("@@SNAPSHOT@@" + JSON.stringify({"ok": true, "out": out, "places": cfg.get("places", {}).size()}))
	quit(0)
