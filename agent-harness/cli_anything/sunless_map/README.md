# cli-anything-sunless-map

Agent CLI for the SunLess map editor, built with the [CLI-Anything](https://github.com/HKUDS/CLI-Anything) methodology.
The real software (the editor, a Godot 4.7 project) does all the work: edits, checks, routes, export, rendering.

## Install

1. Godot 4.7.2 — the **console** build (`Godot_v4.7.2-stable_win64_console.exe`). Point `SUNLESS_GODOT` at it
   unless it is at `D:\Godot_v4.7.2-stable_win64_console.exe`.
2. The editor folder (this repository). Found automatically when installed from it; otherwise set `SUNLESS_MAP_EDITOR`.
3. `pip install -e agent-harness[test]`

## Use

```bash
cli-anything-sunless-map --help
cli-anything-sunless-map --json project open-game --region forgotten_shore -o shore.mapproj
cli-anything-sunless-map -p shore.mapproj check
cli-anything-sunless-map -p shore.mapproj route "Каменная платформа" "Костяной хребет"
cli-anything-sunless-map -p shore.mapproj preview capture --recipe overview
cli-anything-sunless-map                      # REPL
```

Full command reference and agent workflow: [skills/SKILL.md](skills/SKILL.md).

## Preview

- Producer: `cli-anything-sunless-map preview recipes | capture | latest` — bundles `preview-bundle/v1`
  in `<project dir>/.cli-anything/previews/sunless-map/…`, PNG artifacts rendered by the editor canvas.
- Consumer: `cli-hub previews inspect <bundle_dir>` (read-only; never renders).

## Tests

```bash
cd agent-harness
python -m pytest cli_anything/sunless_map/tests -v -s
```

E2E tests need Godot 4.7 and the editor (hard dependency — they fail, not skip, without them).
Game-folder tests use `SUNLESS_GAME` or `../SunLess` next to the editor.
