# SunLess map editor — CLI-Anything analysis and SOP

## Backend engine

The editor is a Godot 4.7 project. Its core (`core/*.gd`) holds the data model and the rules; the GUI
(`ui/*.gd`) and the agent backend (`cli/cli.gd`) are two front-ends over the same core:

| GUI action | Core call | CLI |
|---|---|---|
| drag a place look from a pack | `MapCanvas.add_place_from_pack` → `MapDoc.add_place` + `set_source` | `place add` / op `place.add` |
| drag a place / its corner | `MapDoc.move_place`, `set_size` | `place move`, `place resize` |
| Path tool: click A, click B | `MapDoc.toggle_path` | `path add/remove` |
| Socket tool | `MapDoc.add_socket/move_socket/remove_socket` | `socket …` |
| drop a look onto a place | `MapDoc.add_state` | `place look-add` |
| properties panel | `locations[id]` fields | `place set` |
| F7 «Проверить» | `MapChecks.run` (mirrors the game's `content_validator.gd`) | `check` |
| «Маршрут» mode | `MapSim.route/distances` (BFS like `TravelRules.route`) | `route` |
| «Шаг фигуры» mode | `MapSim.why_not` (like `FigureRules.why_not`) | `step` |
| «Прилив» mode | `MapSim.flooded` | `tide` |
| Ctrl+E export | `GameIO.plan` + `GameIO.write` | `export` |
| canvas | `MapCanvas._draw` | `preview capture` (renders the same canvas) |

## Data model

`.mapproj` — JSON: `{format, game, region, chapter, packs, textures, map, locations, shops, editor}`.
`map` is byte-compatible with the game's `data/maps/<region>.json` (custom JSON writer: ints stay ints,
key order kept, indent 1, LF). Unknown map fields round-trip untouched.

## Interaction model

- One-shot subcommands with `--json` (agents) and a REPL (default, `ReplSkin` from CLI-Anything).
- Read-only inspection (`project info`, `place list`, `path list`, `socket list`) parses `.mapproj` in Python.
- Mutations: Python snapshots the project (session undo/redo), then the editor applies ops (`apply`).
- Render: Godot without `--headless` draws `MapCanvas` into a SubViewport → PNG → preview bundle.

## Why not Python rendering/checks

The CLI-Anything rule «use the real software»: checks, routes and rendering live in the editor so the CLI,
the GUI and the game cannot drift apart.
