"""cli-anything-sunless-map — agent CLI for the SunLess map editor.

Stateful CLI + REPL over the real editor (Godot 4.7 project). Every command supports --json.
Run without a subcommand to enter the REPL.

Examples:
    cli-anything-sunless-map --json project new --region ash_valley -o ash_valley.mapproj
    cli-anything-sunless-map -p ash_valley.mapproj pack add "D:/kits/sunless-chapter4-map-kit"
    cli-anything-sunless-map -p ash_valley.mapproj map texture base sunless_chapter4_map_kit base
    cli-anything-sunless-map -p ash_valley.mapproj place add sunless_chapter4_map_kit soul_tree 0.5 0.5
    cli-anything-sunless-map -p ash_valley.mapproj path add soul_tree lake_shore
    cli-anything-sunless-map --json -p ash_valley.mapproj check
    cli-anything-sunless-map --json -p ash_valley.mapproj preview capture --recipe overview
    cli-anything-sunless-map -p ash_valley.mapproj export --dry-run
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
from typing import Any

import click

from cli_anything.sunless_map import __version__
from cli_anything.sunless_map.core import ops as O
from cli_anything.sunless_map.core import preview as P
from cli_anything.sunless_map.core import project as proj_mod
from cli_anything.sunless_map.core.session import Session
from cli_anything.sunless_map.utils import godot_backend as backend

_REPL_STATE: dict[str, Any] = {"project": None}


# --- output -----------------------------------------------------------------------------------------

def _emit(ctx: click.Context, data: Any, human: str | None = None) -> None:
    if ctx.obj.get("json"):
        click.echo(json.dumps(data, ensure_ascii=False, indent=1, default=str))
    else:
        click.echo(human if human is not None else json.dumps(data, ensure_ascii=False, indent=1, default=str))


def _fail(ctx: click.Context, msg: str, payload: dict | None = None) -> None:
    if ctx.obj.get("json"):
        click.echo(json.dumps({"ok": False, "error": msg, **(payload or {})}, ensure_ascii=False, indent=1, default=str))
    else:
        click.echo(f"✗ {msg}", err=True)
    ctx.exit(1)


def _project(ctx: click.Context) -> str:
    p = ctx.obj.get("project") or _REPL_STATE.get("project")
    if not p:
        _fail(ctx, "no project: pass -p/--project PATH (or `project new` / `project open-game` first)")
    return os.path.abspath(p)


def _opts(ctx: click.Context, **extra: Any) -> dict:
    o = {"library": ctx.obj.get("library"), "game": ctx.obj.get("game")}
    o.update(extra)
    return o


def _call(ctx: click.Context, command: str, positional=(), render: bool = False, **extra: Any) -> dict:
    try:
        return backend.run(command, positional, _opts(ctx, **extra), render=render)
    except backend.BackendError as exc:
        _fail(ctx, str(exc), exc.payload)
    except RuntimeError as exc:
        _fail(ctx, str(exc))
    return {}


def _apply(ctx: click.Context, label: str, ops: list[dict]) -> dict:
    """Mutating command: snapshot for undo, then run the ops in the editor."""
    p = _project(ctx)
    sess = Session(p)
    sess.before_edit(label)
    try:
        res = backend.run("apply", options=_opts(ctx, project=p, ops=ops))
    except (backend.BackendError, RuntimeError) as exc:
        sess.state["undo"].pop()
        sess._save()
        _fail(ctx, str(exc), getattr(exc, "payload", None))
        return {}
    return res


def _xy_ok(ctx: click.Context, fn, *a, **k) -> dict:
    try:
        return fn(*a, **k)
    except ValueError as exc:
        _fail(ctx, str(exc))
    return {}


# --- root -------------------------------------------------------------------------------------------

@click.group(invoke_without_command=True)
@click.option("-p", "--project", "project", type=click.Path(), help="Map project (.mapproj)")
@click.option("--json", "as_json", is_flag=True, help="Machine-readable JSON output")
@click.option("--library", type=click.Path(), help="Pack library file (default: the editor's library)")
@click.option("--game", type=click.Path(), help="SunLess game folder (default: from the project / ../SunLess)")
@click.version_option(__version__, prog_name="cli-anything-sunless-map")
@click.pass_context
def cli(ctx: click.Context, project: str | None, as_json: bool, library: str | None, game: str | None) -> None:
    """Agent CLI for the SunLess map editor: packs → map → checks → export to the game."""
    ctx.ensure_object(dict)
    ctx.obj.update({"project": project or _REPL_STATE.get("project"), "json": as_json or ctx.obj.get("json", False),
                    "library": library or ctx.obj.get("library"), "game": game or ctx.obj.get("game")})
    if ctx.invoked_subcommand is None:
        ctx.invoke(repl)


# --- project ----------------------------------------------------------------------------------------

@cli.group()
def project() -> None:
    """Create, open and inspect map projects."""


@project.command("new")
@click.option("--region", required=True, help="Region id (latin): file data/maps/<region>.json, folder art/map/<region>/")
@click.option("--chapter", help="Game chapter for new places (default: region)")
@click.option("-o", "--out", required=True, type=click.Path(), help="Where to write the .mapproj")
@click.pass_context
def project_new(ctx, region, chapter, out):
    """Start an empty map."""
    res = _call(ctx, "new", out=os.path.abspath(out), region=region, chapter=chapter)
    _REPL_STATE["project"] = res.get("project")
    _emit(ctx, res, f"✓ new map '{res.get('region')}' → {res.get('project')}")


@project.command("open-game")
@click.option("--region", required=True, help="Region of an existing game map (see `project regions`)")
@click.option("-o", "--out", required=True, type=click.Path())
@click.pass_context
def project_open_game(ctx, region, out):
    """Open a map from the game (pictures stay in the 'From game' pack)."""
    res = _call(ctx, "open-game", out=os.path.abspath(out), region=region)
    _REPL_STATE["project"] = res.get("project")
    _emit(ctx, res, f"✓ {region}: {res.get('places')} places, {res.get('paths')} paths → {res.get('project')}")


@project.command("regions")
@click.pass_context
def project_regions(ctx):
    """Regions of the game (with or without a map)."""
    res = _call(ctx, "regions")
    lines = [f"{r}: chapter {i.get('chapter')}, {'map' if i.get('map') else 'no map'}, {i.get('places')} places"
             for r, i in res.get("regions", {}).items()]
    _emit(ctx, res, "\n".join(lines))


@project.command("info")
@click.pass_context
def project_info(ctx):
    """Summary of the project (no Godot needed)."""
    p = _project(ctx)
    try:
        pr = proj_mod.load(p)
    except proj_mod.ProjectError as exc:
        _fail(ctx, str(exc))
        return
    s = proj_mod.summary(pr)
    _emit(ctx, {"ok": True, **s}, "\n".join(f"{k}: {v}" for k, v in s.items()))


@project.command("use")
@click.argument("path", type=click.Path(exists=True))
@click.pass_context
def project_use(ctx, path):
    """Make PATH the current project (REPL)."""
    _REPL_STATE["project"] = os.path.abspath(path)
    _emit(ctx, {"ok": True, "project": _REPL_STATE["project"]}, f"✓ current project: {_REPL_STATE['project']}")


# --- places -----------------------------------------------------------------------------------------

@cli.group()
def place() -> None:
    """Places (vignettes) on the map."""


@place.command("list")
@click.pass_context
def place_list(ctx):
    pr = proj_mod.load(_project(ctx))
    rows = proj_mod.places(pr)
    _emit(ctx, {"ok": True, "places": rows},
          "\n".join(f"{r['id']:<22} {r['name']:<28} h={r['height'] or '-':<4} paths={len(r['paths'])} states={','.join(r['states'])}" for r in rows))


@place.command("add")
@click.argument("pack")
@click.argument("pack_place")
@click.argument("x", type=float)
@click.argument("y", type=float)
@click.option("--size", type=float, help="Width as a fraction of the base width (0.10–0.19 typical)")
@click.option("--id", "pid", help="Place id (default: the pack's place name)")
@click.option("--name", help="Label shown in the game")
@click.pass_context
def place_add(ctx, pack, pack_place, x, y, size, pid, name):
    """Add a place from PACK (all its looks) at X Y (fractions of the base)."""
    op = _xy_ok(ctx, O.place_add, pack, pack_place, x, y, size, pid, name)
    res = _apply(ctx, "place add", [op])
    r = res.get("results", [{}])[0]
    _emit(ctx, res, f"✓ place {r.get('id')} «{r.get('name')}» looks: {', '.join(r.get('states', []))}")


@place.command("move")
@click.argument("pid")
@click.argument("x", type=float)
@click.argument("y", type=float)
@click.pass_context
def place_move(ctx, pid, x, y):
    pid = _resolve(ctx, pid)
    res = _apply(ctx, "place move", [_xy_ok(ctx, O.place_move, pid, x, y)])
    _emit(ctx, res, f"✓ {pid} moved")


@place.command("resize")
@click.argument("pid")
@click.argument("size", type=float)
@click.pass_context
def place_resize(ctx, pid, size):
    pid = _resolve(ctx, pid)
    res = _apply(ctx, "place resize", [_xy_ok(ctx, O.place_resize, pid, size)])
    _emit(ctx, res, f"✓ {pid} size {size}")


@place.command("remove")
@click.argument("pid")
@click.pass_context
def place_remove(ctx, pid):
    """Remove a place together with its paths."""
    pid = _resolve(ctx, pid)
    res = _apply(ctx, "place remove", [O.place_remove(pid)])
    _emit(ctx, res, f"✓ {pid} removed")


@place.command("rename")
@click.argument("pid")
@click.argument("new_id")
@click.pass_context
def place_rename(ctx, pid, new_id):
    """Change the place id everywhere (paths, decals, zones, textures)."""
    pid = _resolve(ctx, pid)
    res = _apply(ctx, "place rename", [O.place_rename(pid, new_id)])
    _emit(ctx, res, f"✓ {pid} → {new_id}")


@place.command("set")
@click.argument("pid")
@click.option("--name")
@click.option("--height", type=click.Choice(O.HEIGHTS), help="low drowns every tide, mid sometimes, high never")
@click.option("--text", help="Description for the journal")
@click.option("--camp-rest", type=int, help="Psyche restored per night (0–40)")
@click.option("--camp-danger", type=float, help="Night attack chance (0–0.6)")
@click.option("--camp-beds", type=int)
@click.option("--camp-services", help="Comma list: view,repair,equip")
@click.option("--no-camp", is_flag=True, help="Cannot camp here")
@click.option("--emerge/--no-emerge", default=None, help="Appears on sockets instead of standing permanently")
@click.option("--group", help="Socket group (emerge_groups key)")
@click.pass_context
def place_set(ctx, pid, name, height, text, camp_rest, camp_danger, camp_beds, camp_services, no_camp, emerge, group):
    """Game properties of a place (locations.json)."""
    pid = _resolve(ctx, pid)
    camp: dict | bool | None = None
    if no_camp:
        camp = False
    elif any(v is not None for v in (camp_rest, camp_danger, camp_beds, camp_services)):
        camp = {}
        if camp_rest is not None:
            camp["rest"] = camp_rest
        if camp_danger is not None:
            camp["danger"] = camp_danger
        if camp_beds is not None:
            camp["beds"] = camp_beds
        if camp_services is not None:
            camp["services"] = [s for s in camp_services.split(",") if s]
    op = _xy_ok(ctx, O.place_set, pid, name, height, text, camp, emerge, group)
    res = _apply(ctx, "place set", [op])
    _emit(ctx, res, f"✓ {pid} updated")


@place.command("look-add")
@click.argument("pid")
@click.argument("pack")
@click.argument("tex")
@click.option("--state", help="Look name (default: from the texture)")
@click.pass_context
def place_look_add(ctx, pid, pack, tex, state):
    """Add a look (state) to a place from any pack texture."""
    pid = _resolve(ctx, pid)
    res = _apply(ctx, "look add", [O.state_add(pid, pack, tex, state)])
    _emit(ctx, res, f"✓ {pid} looks: {', '.join(res.get('results', [{}])[0].get('states', []))}")


@place.command("look-remove")
@click.argument("pid")
@click.argument("state")
@click.pass_context
def place_look_remove(ctx, pid, state):
    pid = _resolve(ctx, pid)
    res = _apply(ctx, "look remove", [O.state_remove(pid, state)])
    _emit(ctx, res, f"✓ {pid} looks: {', '.join(res.get('results', [{}])[0].get('states', []))}")


@place.command("look-default")
@click.argument("pid")
@click.argument("state")
@click.pass_context
def place_look_default(ctx, pid, state):
    pid = _resolve(ctx, pid)
    res = _apply(ctx, "look default", [O.state_default(pid, state)])
    _emit(ctx, res, f"✓ default look of {pid}: {state}")


def _resolve(ctx: click.Context, ref: str) -> str:
    try:
        return proj_mod.find_place(proj_mod.load(_project(ctx)), ref)
    except proj_mod.ProjectError as exc:
        _fail(ctx, str(exc))
    return ref


# --- paths, sockets, map -------------------------------------------------------------------------

@cli.group()
def path() -> None:
    """Paths between places (undirected)."""


@path.command("list")
@click.pass_context
def path_list(ctx):
    rows = proj_mod.paths(proj_mod.load(_project(ctx)))
    _emit(ctx, {"ok": True, "paths": rows}, "\n".join(f"{r['names'][0]} — {r['names'][1]}{' (water)' if r['kind'] == 'water' else ''}" for r in rows))


@path.command("add")
@click.argument("a")
@click.argument("b")
@click.option("--water", is_flag=True, help="Black-water path: boat only")
@click.pass_context
def path_add(ctx, a, b, water):
    a, b = _resolve(ctx, a), _resolve(ctx, b)
    res = _apply(ctx, "path add", [_xy_ok(ctx, O.path, a, b, False, water)])
    _emit(ctx, res, f"✓ path {a} — {b}")


@path.command("remove")
@click.argument("a")
@click.argument("b")
@click.option("--water", is_flag=True)
@click.pass_context
def path_remove(ctx, a, b, water):
    a, b = _resolve(ctx, a), _resolve(ctx, b)
    res = _apply(ctx, "path remove", [_xy_ok(ctx, O.path, a, b, True, water)])
    _emit(ctx, res, f"✓ path {a} — {b} removed")


@cli.group()
def socket() -> None:
    """Sockets: points where appearing places stand."""


@socket.command("list")
@click.pass_context
def socket_list(ctx):
    rows = proj_mod.sockets(proj_mod.load(_project(ctx)))
    _emit(ctx, {"ok": True, "sockets": rows}, "\n".join(f"#{r['number']} at {r['at']}" for r in rows))


@socket.command("add")
@click.argument("x", type=float)
@click.argument("y", type=float)
@click.pass_context
def socket_add(ctx, x, y):
    res = _apply(ctx, "socket add", [_xy_ok(ctx, O.socket_add, x, y)])
    _emit(ctx, res, f"✓ socket #{res.get('results', [{}])[0].get('index', 0) + 1}")


@socket.command("move")
@click.argument("index", type=int)
@click.argument("x", type=float)
@click.argument("y", type=float)
@click.pass_context
def socket_move(ctx, index, x, y):
    res = _apply(ctx, "socket move", [_xy_ok(ctx, O.socket_move, index, x, y)])
    _emit(ctx, res, f"✓ socket index {index} moved")


@socket.command("remove")
@click.argument("index", type=int)
@click.pass_context
def socket_remove(ctx, index):
    """Remove socket INDEX (0-based); groups are renumbered."""
    res = _apply(ctx, "socket remove", [O.socket_remove(index)])
    _emit(ctx, res, f"✓ socket index {index} removed")


@cli.group("map")
def map_group() -> None:
    """Base, height map, tiles and map parameters."""


@map_group.command("texture")
@click.argument("slot", type=click.Choice(["base", "height", "fog", "water"]))
@click.argument("pack")
@click.argument("tex")
@click.pass_context
def map_texture(ctx, slot, pack, tex):
    """Set the base / height map / fog tile / water tile from a pack."""
    res = _apply(ctx, f"map {slot}", [O.set_texture(slot, pack, tex)])
    _emit(ctx, res, f"✓ {slot} = {pack}/{tex}")


@map_group.command("set")
@click.argument("key")
@click.argument("value")
@click.pass_context
def map_set(ctx, key, value):
    """Set a map field to a JSON VALUE (view_top, foot, zoom, levels, zones…). 'null' removes it."""
    try:
        val = json.loads(value)
    except json.JSONDecodeError:
        val = value
    res = _apply(ctx, f"map set {key}", [O.map_set(key, val)])
    _emit(ctx, res, f"✓ {key} set")


@map_group.command("decal")
@click.argument("pack")
@click.argument("tex")
@click.option("--place", "place_id")
@click.option("--path", "path_pair", nargs=2)
@click.option("--phase", help="Comma list of week phases: night,blood_moon…")
@click.option("--from-day", type=int)
@click.pass_context
def map_decal(ctx, pack, tex, place_id, path_pair, phase, from_day):
    """Put a decal next to a place or a strip on a path."""
    if place_id:
        place_id = _resolve(ctx, place_id)
    op = _xy_ok(ctx, O.decal_add, pack, tex, place_id, tuple(path_pair) if path_pair else None,
                [p for p in (phase or "").split(",") if p] or None, from_day)
    res = _apply(ctx, "decal", [op])
    _emit(ctx, res, f"✓ decal {tex}")


@cli.command("batch")
@click.argument("ops_file", type=click.Path(exists=True))
@click.pass_context
def batch(ctx, ops_file):
    """Apply a JSON array of ops in one step (one undo). See SKILL.md for op names."""
    with open(ops_file, encoding="utf-8") as fh:
        ops = json.load(fh)
    res = _apply(ctx, f"batch {os.path.basename(ops_file)}", ops if isinstance(ops, list) else [ops])
    _emit(ctx, res, f"✓ applied {res.get('applied')} ops")


# --- packs ------------------------------------------------------------------------------------------

@cli.group()
def pack() -> None:
    """Texture packs (folders or .zip) in the library."""


@pack.command("list")
@click.pass_context
def pack_list(ctx):
    res = _call(ctx, "pack-list")
    _emit(ctx, res, "\n".join(f"{p['id']:<34} {p['places']:>3} places {p['textures']:>4} tex  {'on ' if p['enabled'] else 'off'} {p['path']}"
                              for p in res.get("packs", [])))


@pack.command("add")
@click.argument("path_", metavar="PATH", type=click.Path(exists=True))
@click.option("--id", "pid")
@click.option("--name")
@click.pass_context
def pack_add(ctx, path_, pid, name):
    res = _call(ctx, "pack-add", [os.path.abspath(path_)], id=pid, name=name)
    _emit(ctx, res, f"✓ pack {res.get('id')}: {res.get('textures')} textures, {len(res.get('places', []))} places")


@pack.command("remove")
@click.argument("pid")
@click.pass_context
def pack_remove(ctx, pid):
    """Remove from the library (files untouched)."""
    _emit(ctx, _call(ctx, "pack-remove", [pid]), f"✓ {pid} removed from the library")


@pack.command("check")
@click.argument("pid", required=False)
@click.option("--deep", is_flag=True, help="Decode images (transparency of corners)")
@click.pass_context
def pack_check(ctx, pid, deep):
    res = _call(ctx, "pack-check", [pid] if pid else [], deep=deep)
    _emit(ctx, res, "\n".join(("✗ " if r["level"] == "error" else "⚠ ") + r["text"] for r in res.get("rows", [])) or "✓ no issues")


@pack.command("textures")
@click.argument("pid")
@click.option("--kind", type=click.Choice(["base", "height", "place", "decal", "strip", "tile", "token", "tech"]))
@click.pass_context
def pack_textures(ctx, pid, kind):
    res = _call(ctx, "pack-textures", [pid], kind=kind)
    if kind == "place" or kind is None:
        human = "\n".join(f"{pl}: {', '.join(sts)}" for pl, sts in res.get("places", {}).items())
    else:
        human = "\n".join(f"{t['name']} ({t['kind']} {t['w']}×{t['h']})" for t in res.get("textures", []))
    _emit(ctx, res, human)


@pack.command("manifest")
@click.argument("pid")
@click.option("--save", is_flag=True, help="Write pack.json into the pack folder")
@click.pass_context
def pack_manifest(ctx, pid, save):
    _emit(ctx, _call(ctx, "pack-manifest", [pid], save=save))


# --- checks, simulation, export ---------------------------------------------------------------------

@cli.command("check")
@click.pass_context
def check(ctx):
    """The game's own map checks (errors block export)."""
    res = _call(ctx, "check", project=_project(ctx))
    rows = res.get("rows", [])
    human = "\n".join(("✗ " if r["level"] == "error" else "⚠ ") + r["text"] for r in rows) or "✓ no issues — ready for export"
    _emit(ctx, res, human + f"\nerrors: {res.get('errors')}, warnings: {res.get('warnings')}")


@cli.command("route")
@click.argument("frm")
@click.argument("to", required=False)
@click.option("--boat", is_flag=True)
@click.option("--tide", type=click.Choice(["normal", "warn", "flood", "storm"]))
@click.option("--phase")
@click.pass_context
def route(ctx, frm, to, boat, tide, phase):
    """Steps from FRM to every place; shortest path to TO (BFS like the game)."""
    frm = _resolve(ctx, frm)
    to = _resolve(ctx, to) if to else None
    res = _call(ctx, "route", project=_project(ctx), **{"from": frm}, to=to, boat=boat, tide=tide, phase=phase)
    human = " → ".join(res.get("names", [])) + f"  ({res.get('steps')} steps)" if to else json.dumps(res.get("distances"), ensure_ascii=False)
    _emit(ctx, res, human)


@cli.command("step")
@click.argument("frm")
@click.option("--boat", is_flag=True)
@click.option("--tide", type=click.Choice(["normal", "warn", "flood", "storm"]))
@click.pass_context
def step(ctx, frm, boat, tide):
    """Where the figure can step from FRM (empty reason = allowed)."""
    frm = _resolve(ctx, frm)
    res = _call(ctx, "step", project=_project(ctx), **{"from": frm}, boat=boat, tide=tide)
    _emit(ctx, res, "\n".join(f"{n}: {'ok' if not why else why}" for n, why in res.get("neighbors", {}).items()))


@cli.command("tide")
@click.option("--level", type=click.Choice(["normal", "warn", "flood", "storm"]), default="flood")
@click.pass_context
def tide(ctx, level):
    """Which places drown at LEVEL and whether dry land stays connected."""
    res = _call(ctx, "tide", project=_project(ctx), tide=level)
    _emit(ctx, res, f"flooded: {', '.join(res.get('flooded', [])) or '—'}; maybe: {', '.join(res.get('maybe', [])) or '—'}; dry connected: {res.get('dry_connected')}")


@cli.command("export")
@click.option("--dry-run", is_flag=True, help="Only list what would change")
@click.option("--reimport", is_flag=True, help="Run Godot import in the game afterwards (needed for new pictures)")
@click.option("--force", is_flag=True, help="Export despite check errors (not recommended)")
@click.pass_context
def export(ctx, dry_run, reimport, force):
    """Write data/maps/<region>.json, locations.json entries and art/map/<region>/ to the game."""
    p = _project(ctx)
    try:
        res = backend.run("export", options=_opts(ctx, project=p, dry_run=dry_run, reimport=reimport, force=force), check=False)
    except (backend.BackendError, RuntimeError) as exc:
        _fail(ctx, str(exc))
        return
    if not res.get("ok"):
        _fail(ctx, str(res.get("error", "export failed")), res)
        return
    changed = [i for i in res.get("items", []) if i["status"] != "same"]
    human = "\n".join(f"{i['status']:<8} {i['rel']}" for i in changed) or "nothing to change"
    if not dry_run:
        human += f"\nwritten: {len(res.get('written', []))}; backup: {res.get('backup') or '—'}"
    _emit(ctx, res, human)


@cli.command("game-shot")
@click.option("--camp", help="Place where the figure stands (default: first high place)")
@click.option("-o", "--out", required=True, type=click.Path(), help="PNG to write (1920×1080)")
@click.pass_context
def game_shot(ctx, camp, out):
    """Render the map with the GAME's own code (SleeperMap). A new or edited map goes through a temporary
    region 'editor_preview' that is removed afterwards — the game folder is left exactly as it was."""
    p = _project(ctx)
    res = _call(ctx, "game-snapshot", project=p, camp=_resolve(ctx, camp) if camp else None, out=os.path.abspath(out))
    _emit(ctx, res, f"✓ game snapshot {res.get('out')}{' (temporary region, cleaned up)' if res.get('temporary') else ''}")


# --- preview ----------------------------------------------------------------------------------------

@cli.group()
def preview() -> None:
    """Preview bundles (preview-bundle/v1) rendered by the editor canvas. Inspect with `cli-hub previews`."""


@preview.command("recipes")
@click.pass_context
def preview_recipes(ctx):
    _emit(ctx, {"ok": True, "recipes": P.RECIPES}, "\n".join(f"{k:<9} {v}" for k, v in P.RECIPES.items()))


@preview.command("capture")
@click.option("--recipe", default="plain", type=click.Choice(list(P.RECIPES)))
@click.option("--width", default=1600, type=int)
@click.option("--from", "frm")
@click.option("--to")
@click.option("--tide", type=click.Choice(["normal", "warn", "flood", "storm"]))
@click.option("--phase")
@click.option("--select")
@click.option("--force", is_flag=True, help="Render even if a cached bundle exists")
@click.pass_context
def preview_capture(ctx, recipe, width, frm, to, tide, phase, select, force):
    """Render the map with the real editor canvas into a bundle."""
    p = _project(ctx)
    extra = {"from": _resolve(ctx, frm) if frm else None, "to": _resolve(ctx, to) if to else None, "tide": tide,
             "phase": phase, "select": select, "game": ctx.obj.get("game")}
    try:
        res = P.capture(p, recipe, width, extra, library=ctx.obj.get("library"), force=force)
    except (ValueError, RuntimeError) as exc:
        _fail(ctx, str(exc))
        return
    arts = [os.path.join(res["_bundle_dir"], a["path"]) for a in res.get("artifacts", [])]
    _emit(ctx, {"ok": True, **res}, f"✓ bundle {res['_bundle_dir']}\n" + "\n".join(arts))


@preview.command("latest")
@click.option("--recipe", type=click.Choice(list(P.RECIPES)))
@click.pass_context
def preview_latest(ctx, recipe):
    """Newest existing bundle (no rendering)."""
    m = P.latest(_project(ctx), recipe)
    if not m:
        _fail(ctx, "no preview bundles yet — run `preview capture`")
        return
    _emit(ctx, {"ok": True, **m}, f"{m['_bundle_dir']}\n" + "\n".join(a["path"] for a in m.get("artifacts", [])))


# --- session ----------------------------------------------------------------------------------------

@cli.group()
def session() -> None:
    """Undo/redo of CLI edits."""


@session.command("status")
@click.pass_context
def session_status(ctx):
    s = Session(_project(ctx)).status()
    _emit(ctx, {"ok": True, **s}, f"undo: {len(s['undo'])} ({', '.join(s['undo'][-3:])}) · redo: {len(s['redo'])}")


@session.command("undo")
@click.pass_context
def session_undo(ctx):
    lbl = Session(_project(ctx)).undo()
    if lbl is None:
        _fail(ctx, "nothing to undo")
    _emit(ctx, {"ok": True, "undone": lbl}, f"✓ undone: {lbl}")


@session.command("redo")
@click.pass_context
def session_redo(ctx):
    lbl = Session(_project(ctx)).redo()
    if lbl is None:
        _fail(ctx, "nothing to redo")
    _emit(ctx, {"ok": True, "redone": lbl}, f"✓ redone: {lbl}")


@cli.command("gui")
@click.pass_context
def gui(ctx):
    """Open the project in the editor window (for a human)."""
    p = _project(ctx)
    godot = backend.find_godot().replace("_console", "")
    subprocess.Popen([godot, "--path", backend.find_editor(), "--", p])
    _emit(ctx, {"ok": True, "project": p}, f"✓ editor window opened on {p}")


# --- REPL -------------------------------------------------------------------------------------------

@cli.command("repl", hidden=True)
@click.pass_context
def repl(ctx):
    """Interactive mode (default when no command is given)."""
    from cli_anything.sunless_map.utils.repl_skin import ReplSkin
    skin = ReplSkin("sunless_map", version=__version__)
    skin.print_banner()
    skin.hint("Type a command without the program name, e.g. `project info`, `place list`, `check`. `help`, `exit`.")
    session_pt = skin.create_prompt_session()
    while True:
        try:
            name = os.path.basename(_REPL_STATE.get("project") or ctx.obj.get("project") or "") or "no project"
            line = skin.get_input(session_pt, project_name=name)
        except (EOFError, KeyboardInterrupt):
            break
        if not line:
            continue
        if line in ("exit", "quit"):
            break
        if line == "help":
            skin.help({c: (cli.commands[c].help or "").split("\n")[0] for c in sorted(cli.commands) if c != "repl"})
            continue
        parts = [s.strip('"') for s in shlex.split(line, posix=False)]
        base = []
        if ctx.obj.get("json"):
            base.append("--json")
        p = _REPL_STATE.get("project") or ctx.obj.get("project")
        if p and "-p" not in parts and "--project" not in parts:
            base += ["-p", p]
        try:
            cli.main(args=base + parts, prog_name="cli-anything-sunless-map", standalone_mode=False,
                     obj={"library": ctx.obj.get("library"), "game": ctx.obj.get("game")})
        except click.exceptions.Exit:
            pass
        except click.ClickException as exc:
            skin.error(exc.format_message())
        except SystemExit:
            pass
    skin.print_goodbye()


def main() -> None:
    # Windows consoles default to a legacy code page; names of places are Cyrillic
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    cli(obj={})


if __name__ == "__main__":
    main()
