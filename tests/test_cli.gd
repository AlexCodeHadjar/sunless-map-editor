extends TestCase
## Операции агентского интерфейса (cli/cli.gd → apply_op) — те же методы MapDoc, что в окне.

const Cli := preload("res://cli/cli.gd")
const Packs := preload("res://tests/test_packs.gd")


func test_apply_ops() -> void:
	var d := tmp_dir("cli_ops")
	Packs.make_pack(d + "/pack")
	var lib := PackLibrary.new()
	lib.path_file = d + "/lib.json"
	var p := lib.add(d + "/pack")
	var doc := MapDoc.new_map("ops")
	var ok := func(op: Dictionary) -> Dictionary:
		var r: Dictionary = Cli.apply_op(doc, op, lib)
		check(not r.has("error"), "операция %s: %s" % [op.op, r.get("error", "")])
		return r
	ok.call({"op": "base.set", "pack": p.id, "tex": "base"})
	eq(float(doc.editor.aspect), 2.0, "пропорции основы")
	var r1: Dictionary = ok.call({"op": "place.add", "pack": p.id, "place": "tower", "at": [0.3, 0.4], "name": "Башня"})
	eq(Array(r1.states), ["dry", "burning"], "все облики места из пака")
	ok.call({"op": "place.add", "pack": p.id, "tex": "swamp_flooded", "at": [0.6, 0.4]})
	check(doc.places().has("swamp"), "место по текстуре облика")
	var r2: Dictionary = ok.call({"op": "place.add", "pack": p.id, "place": "tower", "at": [0.5, 0.7]})
	eq(str(r2.id), "tower_2", "второе место с тем же id — tower_2")
	eq(doc.source("tower_2_burning"), {"pack": p.id, "tex": "tower_burning"}, "источник облика второго места")
	ok.call({"op": "path.add", "a": "tower", "b": "swamp"})
	ok.call({"op": "path.add", "a": "tower", "b": "swamp"})
	eq(doc.paths().size(), 1, "повторное добавление тропы не дублирует её")
	ok.call({"op": "path.add", "a": "swamp", "b": "tower_2", "kind": "water"})
	eq(Array(doc.map.water_paths), [["swamp", "tower_2"]], "водная тропа")
	ok.call({"op": "place.set", "id": "tower", "height": "high", "camp": {"rest": 22}})
	eq(int(doc.locations.tower.camp.rest), 22, "лагерь")
	eq(str(doc.locations.tower.height), "high", "высота")
	ok.call({"op": "socket.add", "at": [0.1, 0.1]})
	ok.call({"op": "decal.add", "pack": p.id, "tex": "decal_skull", "place": "tower", "phase": ["night"]})
	eq(Array(doc.map.place_decals[0].phase), ["night"], "метка с фазой")
	ok.call({"op": "place.rename", "id": "tower", "to": "watchtower"})
	check(doc.has_path("watchtower", "swamp") and str(doc.map.place_decals[0].place) == "watchtower", "переименование везде")
	ok.call({"op": "map.set", "key": "view_top", "value": 0.1})
	eq(float(doc.map.view_top), 0.1, "параметр карты")
	check(Cli.apply_op(doc, {"op": "place.move", "id": "nowhere", "at": [0.1, 0.1]}, lib).has("error"), "ошибка для несуществующего места")
	check(Cli.apply_op(doc, {"op": "map.set", "key": "places", "value": {}}, lib).has("error"), "places не меняется через map.set")
	check(Cli.apply_op(doc, {"op": "frobnicate"}, lib).has("error"), "неизвестная операция")
