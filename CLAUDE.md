# Редактор карт SunLess — карта проекта для Claude

Godot 4.7 проект: редактор карт глав игры SunLess (соседняя папка `../SunLess`). ТЗ — `../SunLess/docs/ТЗ — Редактор карт SunLess.docx`,
план фаз — `docs/PLAN.md`. Владелец пишет по-русски, не программист: интерфейс — словами и ползунками, без «сырых» чисел.

## Агенту: работать с картами — через CLI

Skill `.claude/skills/cli-anything-sunless-map/SKILL.md` (канон — `skills/cli-anything-sunless-map/SKILL.md`).
Команда `cli-anything-sunless-map` (установка: `pip install -e agent-harness[test]`), всё с `--json`:
`project new|open-game`, `pack add|textures`, `map texture`, `place add|set`, `path add`, `check`, `route`,
`preview capture --recipe overview` (PNG тем же холстом, что окно), `export --dry-run`.

## Код

| Что | Файлы |
|---|---|
| Ядро | `core/jsonx.gd` (JSON как у игры), `map_doc.gd` (проект, правки, отмена), `tex_pack.gd`/`pack_library.gd`/`pack_check.gd` (паки), `tex_source.gd` (откуда текстура), `graph.gd`, `checks.gd` (= content_validator игры), `sim.gd` (маршрут, прилив, туман, шаг фигуры), `game_io.gd` (открыть/экспорт), `words.gd` (слова вместо чисел) |
| Окно | `ui/main.gd`, `map_canvas.gd` (холст), `pack_panel.gd`, `props_panel.gd`, `tex_cache.gd` (фоновая загрузка), `shaders/` (из игры) |
| Агент | `cli/cli.gd` (бэкенд, `apply_op`), `agent-harness/` (Python, CLI-Anything) |

## Команды

```bash
G="/d/Godot_v4.7.2-stable_win64_console.exe"
"$G" --headless --path . -s res://tests/run_tests.gd               # тесты редактора
"$G" --path . --resolution 1600x900 -- --shots=<папка> [--shots-from=new]   # автоснимки окна
cd agent-harness && python -m pytest cli_anything/sunless_map/tests -q -p no:cacheprovider --basetemp=<tmp>
```

Ошибка разбора скрипта в `-s` режиме вешает Godot — запускать с `timeout`. После фазы — коммит и push в `main`.
