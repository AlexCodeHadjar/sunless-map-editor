extends TestCase


## Пак по ТЗ (папки base/, places/<место>/, decals/, strips/, tiles/, tokens/).
static func make_pack(d: String) -> void:
	for sub: String in ["base", "places/tower", "places/swamp", "decals", "strips", "tiles", "tokens"]:
		DirAccess.make_dir_recursive_absolute(d + "/" + sub)
	make_image(512, 256, Color(0.3, 0.4, 0.3), false).save_png(d + "/base/base.png")
	var hm := Image.create(512, 256, false, Image.FORMAT_L8)
	hm.fill(Color(0.5, 0.5, 0.5))
	hm.save_png(d + "/base/height.png")
	make_image(128, 128, Color.RED).save_png(d + "/places/tower/dry.png")
	make_image(128, 128, Color.ORANGE).save_png(d + "/places/tower/burning.png")
	make_image(128, 128, Color.GREEN).save_png(d + "/places/swamp/swamp_dry.png")
	make_image(128, 128, Color.BLUE).save_png(d + "/places/swamp/swamp_flooded.png")
	make_image(64, 64, Color.WHITE).save_png(d + "/decals/decal_skull.png")
	make_image(256, 64, Color.WHITE).save_png(d + "/strips/decal_tracks.png")
	make_image(64, 64, Color.GRAY, false).save_png(d + "/tiles/fog_tile.png")
	make_image(64, 64, Color.GRAY, false).save_png(d + "/tiles/water_tile.png")
	for i in 4:
		make_image(64, 64, Color.PURPLE).save_png(d + "/tokens/wolf_%d.png" % (i + 1))
	make_image(64, 32, Color.BLACK, false).save_png(d + "/preview.png")


func test_folder_pack_auto_manifest() -> void:
	var d := tmp_dir("pack_a")
	make_pack(d)
	var p := TexPack.open(d)
	eq(p.errors, [], "без ошибок")
	check(not p.has_manifest, "манифеста нет")
	eq(p.places().keys().size(), 2, "два места")
	eq(Array(p.places().tower), ["dry", "burning"], "облики башни: dry первым")
	eq(str(p.textures.tower_burning.kind), "place", "облик — место")
	eq(str(p.textures.swamp_flooded.state), "flooded", "имя с префиксом места в папке места")
	eq(str(p.textures.base.kind), "base", "основа")
	eq(str(p.textures.height.kind), "height", "карта высот")
	eq(str(p.textures.decal_skull.kind), "decal", "метка")
	eq(str(p.textures.decal_tracks.kind), "strip", "полоса")
	eq(str(p.textures.fog_tile.kind), "tile", "плитка")
	eq(str(p.textures.wolf_3.kind), "token", "фишка")
	eq(p.preview, "preview.png", "обложка")
	eq(int(p.textures.base.w), 512, "размер из заголовка")
	eq(p.textures.tower_dry.alpha, true, "прозрачность из заголовка")


func test_manifest_save_and_reload() -> void:
	var d := tmp_dir("pack_b")
	make_pack(d)
	var p := TexPack.open(d)
	p.name = "Болото"
	eq(p.save_manifest(), "", "манифест сохранён")
	var p2 := TexPack.open(d)
	check(p2.has_manifest, "манифест прочитан")
	eq(p2.name, "Болото", "название из манифеста")
	eq(p2.textures.size(), p.textures.size(), "те же текстуры")


func test_flat_kit_names() -> void:
	var d := tmp_dir("pack_c")
	for nm: String in ["base", "coral_maze_dry", "coral_maze_dry_b", "coral_maze_flooded", "gate_omen", "camp_x_occupied", "decal_fog"]:
		make_image(64 if nm != "base" else 256, 64 if nm != "base" else 128, Color.WHITE, nm != "base").save_png(d + "/" + nm + ".png")
	var p := TexPack.open(d)
	eq(str(p.textures.coral_maze_dry_b.place), "coral_maze", "место по dry")
	eq(str(p.textures.coral_maze_dry_b.state), "dry_b", "облик dry_b")
	eq(str(p.textures.camp_x_occupied.place), "camp_x", "место по словарю обликов")
	eq(str(p.textures.gate_omen.kind), "decal", "неизвестный облик — метка")
	eq(str(p.textures.base.kind), "base", "основа")


func test_zip_pack() -> void:
	var d := tmp_dir("pack_zip")
	make_pack(d + "/src")
	var zp := ZIPPacker.new()
	eq(zp.open(d + "/swamp.zip"), OK, "архив создан")
	for f: String in TexPack.open(d + "/src").files():
		zp.start_file("swamp/" + f)
		zp.write_file(FileAccess.get_file_as_bytes(d + "/src/" + f))
		zp.close_file()
	zp.close()
	var p := TexPack.open(d + "/swamp.zip")
	eq(p.errors, [], "архив открыт")
	check(p.is_zip, "это архив")
	eq(p.places().size(), 2, "места из архива (папка внутри)")
	var img := p.image("tower_dry")
	check(img != null and img.get_width() == 128, "картинка из архива")


func test_check_pack() -> void:
	var d := tmp_dir("pack_bad")
	DirAccess.make_dir_recursive_absolute(d + "/places/hut")
	make_image(100, 60, Color.RED).save_png(d + "/places/hut/burning.png")   # не квадрат и нет dry
	make_image(64, 64, Color.RED, false).save_png(d + "/decal_flat.png")     # метка без прозрачности
	FileAccess.open(d + "/broken.png", FileAccess.WRITE).store_string("not a png")
	var rep := PackCheck.check(TexPack.open(d))
	var text := "\n".join(rep.map(func(r: Dictionary) -> String: return r.text))
	check(text.contains("квадратной"), "не квадрат")
	check(text.contains("нет облика dry"), "нет dry")
	check(text.contains("нет прозрачности"), "метка без прозрачности")
	check(text.contains("битый"), "битый файл")


func test_library_and_duplicates() -> void:
	var d := tmp_dir("lib")
	make_pack(d + "/a")
	make_pack(d + "/b")
	var lib := PackLibrary.new()
	lib.path_file = d + "/library.json"
	var pa := lib.add(d + "/a")
	var pb := lib.add(d + "/b")
	check(pa.id != pb.id, "разные id у паков с похожими именами")
	eq(lib.find("tower_dry").size(), 2, "текстура в двух паках")
	check(not PackCheck.duplicates(lib.enabled_packs()).is_empty(), "дубли имён видны")
	lib.set_enabled(pb.id, false)
	eq(lib.find("tower_dry"), [pa.id], "выключенный пак не участвует")
	var lib2 := PackLibrary.new()
	lib2.path_file = d + "/library.json"
	lib2.load_file()
	eq(lib2.entries.size(), 2, "библиотека сохранена")
	lib2.remove(pa.id)
	check(DirAccess.dir_exists_absolute(d + "/a"), "файлы пака не тронуты")


func test_real_kits() -> void:
	var g := game_dir()
	if g == "" or not DirAccess.dir_exists_absolute(g + "/docs/assets/kits/sunless-map-kit"):
		return
	var p := TexPack.open(g + "/docs/assets/kits/sunless-map-kit")
	eq(p.places().size(), 18, "комплект Берега: 18 мест (копии с хромакеем пропущены)")
	check(p.textures.has("height") and p.textures.base.kind == "base", "основа и высоты")
	var ev := TexPack.open(g + "/docs/assets/kits/sunless-map-events-kit")
	eq(str(ev.textures.centurion_gate_molting.kind), "place", "облик чужого места — тоже облик")
