---
name: "cli-anything-sunless-map"
description: "Build and edit SunLess chapter maps (Godot 4.7 game) from texture packs from the command line: places, paths, sockets, looks, decals, the game's own map checks, BFS routes, tide, previews rendered by the editor canvas, and export into the game's data/maps, locations.json and art/map. Use when asked to create, change, check, preview or export a SunLess map, or to assemble a new map from texture kits."
---

# cli-anything-sunless-map

Agent CLI for the **SunLess map editor** (a Godot 4.7 project, built with the CLI-Anything methodology).
Every rule runs inside the editor itself (`res://cli/cli.gd`), the same code as the GUI — the CLI never
re-implements checks, routes, export or rendering.

## Install

```bash
pip install -e <editor>/agent-harness          # gives the `cli-anything-sunless-map` command
set SUNLESS_GODOT=D:\Godot_v4.7.2-stable_win64_console.exe   # console build (stdout must reach the CLI)
set SUNLESS_MAP_EDITOR=<editor folder>        # optional; found automatically from the package
set SUNLESS_GAME=<SunLess game folder>        # optional; default ../SunLess next to the editor
```

Godot 4.7 is a **hard dependency**. Each command starts Godot headless (~1–2 s); `preview capture`
starts it with a tiny window (real renderer).

## Concepts

- **Project** `.mapproj` (JSON): the map (same as `data/maps/<region>.json`), location records for
  `locations.json`, which pack every texture comes from, packs used, editor state.
- **Coordinates** are fractions of the base image: `(0,0)` top-left, `(1,1)` bottom-right.
  `size` = vignette width as a fraction of the base width (typical 0.10–0.19).
- **Pack**: folder or .zip of textures. Places are `<place>_<look>` (look = state: `dry` is the normal one,
  `flooded`, `storm`, `ravaged`…). `pack textures <id> --kind place` lists `place: looks`.
- **Height** of a place: `low` drowns every tide, `mid` sometimes, `high` never. On maps with water the
  "dry spine" rule needs high places + shops connected among themselves, each high place with ≥2 paths.
- **Paths** are undirected; distance = number of paths (BFS, neighbours alphabetical — like the game).

## Commands (all accept `--json`; global `-p/--project`, `--library`, `--game`)

| Group | Commands |
|---|---|
| project | `new --region R [--chapter C] -o F`, `open-game --region R -o F`, `regions`, `info`, `use F` |
| pack | `list`, `add PATH [--id]`, `remove ID`, `check [ID] [--deep]`, `textures ID [--kind place\|decal\|base…]`, `manifest ID [--save]` |
| map | `texture base\|height\|fog\|water PACK TEX`, `set KEY JSON` (view_top, foot, zoom, levels, zones…), `decal PACK TEX --place ID \| --path A B [--phase night]` |
| place | `list`, `add PACK PLACE X Y [--size S] [--id] [--name]`, `move ID X Y`, `resize ID S`, `remove ID`, `rename ID NEW`, `set ID [--name] [--height low\|mid\|high] [--camp-rest N] [--camp-danger F] [--camp-beds N] [--camp-services view,repair] [--no-camp] [--emerge/--no-emerge] [--group G]`, `look-add ID PACK TEX [--state S]`, `look-remove ID S`, `look-default ID S` |
| path | `list`, `add A B [--water]`, `remove A B [--water]` |
| socket | `list`, `add X Y`, `move I X Y`, `remove I` (0-based; groups renumbered) |
| — | `check`, `route FROM [TO] [--boat] [--tide flood]`, `step FROM`, `tide [--level flood\|storm]` |
| — | `export [--dry-run] [--reimport] [--force]`, `batch OPS.json` |
| preview | `recipes`, `capture [--recipe plain\|graph\|route\|tide\|game\|overview] [--from A --to B] [--width 1600]` (`game` — as the player sees it: 16:9, figure at `--from`, fog), `latest` |
| session | `status`, `undo`, `redo` |
| — | `gui` (open the editor window for a human) |

Places can be referenced by id or by their Russian name (`"Древо Души"`).

## Typical agent workflow

```bash
C="cli-anything-sunless-map --json"
$C project new --region ash_valley --chapter ash_valley -o ash_valley.mapproj
$C pack add "<game>/docs/assets/kits/sunless-chapter4-map-kit"            # → id sunless_chapter4_map_kit
$C -p ash_valley.mapproj pack textures sunless_chapter4_map_kit --kind place
$C -p ash_valley.mapproj map texture base sunless_chapter4_map_kit base
$C -p ash_valley.mapproj place add sunless_chapter4_map_kit soul_tree 0.50 0.45 --size 0.17
$C -p ash_valley.mapproj place add sunless_chapter4_map_kit lake_shore 0.30 0.62
$C -p ash_valley.mapproj path add soul_tree lake_shore
$C -p ash_valley.mapproj place set soul_tree --height high --camp-rest 25 --camp-danger 0.05
$C -p ash_valley.mapproj check                     # errors block export — fix them
$C -p ash_valley.mapproj preview capture --recipe overview   # look at artifacts/plain.png and graph.png
$C -p ash_valley.mapproj export --dry-run          # what would change in the game
$C -p ash_valley.mapproj export --reimport         # write + Godot import in the game
```

For many edits use `batch ops.json` (one Godot start, one undo step). Ops:
`place.add {pack, place, at:[x,y], size?, id?, name?}`, `place.move {id, at}`, `place.resize {id, size}`,
`place.remove {id}`, `place.rename {id, to}`, `place.set {id, name?, height?, text?, camp?, emerge?, socket_group?}`,
`state.add {id, pack, tex, state?}`, `state.remove {id, state}`, `state.default {id, state}`,
`path.add|path.remove {a, b, kind: path|water}`, `socket.add {at}`, `socket.move {index, at}`, `socket.remove {index}`,
`base.set|height.set {pack, tex}`, `tile.set {slot: fog|water, pack, tex}`,
`decal.add {pack, tex, place | path:[a,b], phase?, from_day?}`, `map.set {key, value}`, `chapter.set {chapter}`.

## Agent guidance

- Always `check` before `export`; `export` refuses on errors unless `--force`.
- Read `preview capture` artifacts (PNG) to judge placement: vignettes should sit on empty spots of the base,
  not overlap (the check warns at >35 % overlap), labels readable.
- Opening a game map (`project open-game`) keeps pictures from the game folder, so exporting it unchanged
  writes nothing; edits only touch `data/maps/<region>.json` and that region's `locations.json` records.
- A new region needs: base, fog tile (the game's shared one is used automatically), places with a `dry` look,
  every permanent place connected by paths. Water maps also need a height map, levels and the dry spine.
- `session undo` restores the project file before the last CLI edit.
- Errors come back as `{"ok": false, "error": "..."}` with exit code 1.

## Preview

Producer: `cli-anything-sunless-map preview capture|latest|recipes` writes `preview-bundle/v1` bundles to
`<project dir>/.cli-anything/previews/sunless-map/<recipe>/<bundle>/` (`manifest.json`, `summary.json`,
`artifacts/*.png`). Images are rendered by the editor's own map canvas (truthful to the GUI).
Consumer (read-only): `cli-hub previews inspect <bundle_dir>`.
