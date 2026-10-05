# TEST.md — cli-anything-sunless-map

## Part 1 — plan

| File | What | Count |
|---|---|---|
| `test_core.py` | project inspection (load, summary, places, paths, sockets, find by Russian name, bad files, fingerprint); op builders (coordinates and sizes validated, place.set heights, paths, textures, decals); session undo/redo and redo clearing; backend argument building, output parsing, editor discovery | 17 |
| `test_full_e2e.py` | installed CLI driving the real editor (Godot 4.7): `--help`; full new-map workflow; preview bundle; real game map | 4 |

Realistic workflows:

- **New chapter map from a pack** — project new → pack add (folder pack in the ТЗ layout, made with Pillow) → base and fog tile →
  3 places (two via id, one via Russian name in paths) → `check` must fail while places are unconnected → paths → place set
  (height, camp) → decal with phase → `check` 0 errors → `route` (BFS path) → `step` (neighbours allowed) →
  `session undo/redo` → `export --dry-run` (nothing written) → `export` → verified: WebP magic bytes, base 3072×1536,
  places 512×512, decals 256×256, map JSON, locations.json order (foreign record kept first) → second dry run: everything "same".
- **Preview** — overview bundle (plain + graph): manifest `preview-bundle/v1`, PNG magic, 800×400, non-flat image; second
  capture is served from cache; `preview latest` returns the same bundle.
- **Real game** (needs the SunLess folder) — open «Забытый Берег»: 29 places, 0 check errors, export dry run changes nothing,
  route «Каменная платформа» → «Костяной хребет» = 4 steps (as in the game).

## Part 2 — results

```
cli_anything/sunless_map/tests/test_core.py::TestProject::test_load_and_summary PASSED [  4%]
cli_anything/sunless_map/tests/test_core.py::TestProject::test_places PASSED [  9%]
cli_anything/sunless_map/tests/test_core.py::TestProject::test_paths_and_sockets PASSED [ 13%]
cli_anything/sunless_map/tests/test_core.py::TestProject::test_find_place_by_name PASSED [ 18%]
cli_anything/sunless_map/tests/test_core.py::TestProject::test_bad_files PASSED [ 22%]
cli_anything/sunless_map/tests/test_core.py::TestProject::test_fingerprint_changes PASSED [ 27%]
cli_anything/sunless_map/tests/test_core.py::TestOps::test_place_add PASSED [ 31%]
cli_anything/sunless_map/tests/test_core.py::TestOps::test_coordinates_validated PASSED [ 36%]
cli_anything/sunless_map/tests/test_core.py::TestOps::test_size_validated PASSED [ 40%]
cli_anything/sunless_map/tests/test_core.py::TestOps::test_place_set PASSED [ 45%]
cli_anything/sunless_map/tests/test_core.py::TestOps::test_paths PASSED  [ 50%]
cli_anything/sunless_map/tests/test_core.py::TestOps::test_textures_and_decals PASSED [ 54%]
cli_anything/sunless_map/tests/test_core.py::TestSession::test_undo_redo PASSED [ 59%]
cli_anything/sunless_map/tests/test_core.py::TestSession::test_new_edit_clears_redo PASSED [ 63%]
cli_anything/sunless_map/tests/test_core.py::TestBackendArgs::test_headless_args PASSED [ 68%]
cli_anything/sunless_map/tests/test_core.py::TestBackendArgs::test_render_has_window PASSED [ 72%]
cli_anything/sunless_map/tests/test_core.py::TestBackendArgs::test_parse_output PASSED [ 77%]
cli_anything/sunless_map/tests/test_core.py::TestBackendArgs::test_find_editor_from_package PASSED [ 81%]
cli_anything/sunless_map/tests/test_full_e2e.py::TestCLISubprocess::test_help PASSED [ 86%]
cli_anything/sunless_map/tests/test_full_e2e.py::TestCLISubprocess::test_full_new_map_workflow PASSED [ 90%]
cli_anything/sunless_map/tests/test_full_e2e.py::TestCLISubprocess::test_preview_bundle PASSED [ 95%]
cli_anything/sunless_map/tests/test_full_e2e.py::TestRealGame::test_shore_open_unchanged_export_and_route PASSED [100%]
============================= 22 passed in 26.37s =============================
```

Editor-side tests (Godot): `godot --headless --path . -s res://tests/run_tests.gd` — 210 checks, 0 failures
(includes `test_cli`: every `apply` op against MapDoc).

Coverage notes: the REPL loop is exercised manually (it dispatches to the same Click commands); `gui` opens a window and is
not run in tests; `--reimport` runs Godot import inside the game folder and is covered by the editor's export dialog only.
