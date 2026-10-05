extends TestCase
## Все скрипты редактора компилируются (ошибка разбора в окне иначе видна только при запуске).


func test_all_scripts_compile() -> void:
	for f: String in _scripts("res://"):
		var s: GDScript = load(f)
		check(s != null and s.can_instantiate(), "компилируется " + f)


func _scripts(dir: String) -> Array:
	var out: Array = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d in ["agent-harness", "examples", "docs"]:
			continue
		out.append_array(_scripts(dir.path_join(d)))
	return out
