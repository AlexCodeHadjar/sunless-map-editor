"""Preview bundles (CLI-Anything ``preview-bundle/v1``) rendered by the real editor canvas.

Recipes:
  plain   — the map as in the editor: base, vignettes, ink paths, labels, sockets
  graph   — graph mode: nodes coloured by height, unconnected places ringed red
  route   — steps from --from to every place and the shortest path to --to
  tide    — what is under water at the chosen tide (default: flood)
  overview — hero (plain) + graph + tide (if the map has water)
"""

from __future__ import annotations

import os
from pathlib import Path

from cli_anything.sunless_map import __version__
from cli_anything.sunless_map.core import project as proj_mod
from cli_anything.sunless_map.utils import godot_backend as backend
from cli_anything.sunless_map.utils import preview_bundle as pb

SOFTWARE = "sunless_map"

RECIPES = {
    "plain": "Map as in the editor (base, vignettes, paths, labels, sockets)",
    "graph": "Graph mode: nodes by height, unconnected places in red",
    "route": "Steps from --from and the shortest path to --to",
    "tide": "Flooded places at the chosen --tide (flood by default)",
    "game": "As the player sees it: 16:9 window, zoom and view_top, figure at --from, fog of the unknown",
    "overview": "plain + graph (+ tide if the map has water)",
}


def _render(project_path: str, out: str, mode: str, width: int, extra: dict, library: str | None) -> dict:
    opts = {"project": project_path, "out": out, "mode": mode, "width": width, "library": library}
    opts.update({k: v for k, v in extra.items() if v not in (None, "")})
    return backend.run("render", options=opts, render=True)


def capture(project_path: str, recipe: str = "plain", width: int = 1600, extra: dict | None = None,
            library: str | None = None, force: bool = False, root_dir: str | None = None) -> dict:
    if recipe not in RECIPES:
        raise ValueError(f"unknown recipe {recipe}; known: {', '.join(RECIPES)}")
    extra = dict(extra or {})
    proj = proj_mod.load(project_path)
    fp = proj_mod.fingerprint(project_path)
    options = {"width": width, **extra}
    prep = pb.prepare_bundle(SOFTWARE, recipe, "capture", fp, options=options, harness_version=__version__,
                             project_path=project_path, root_dir=root_dir, force=force)
    if prep.get("cached"):
        manifest = prep["manifest"]
        return {"cached": True, "_bundle_dir": prep["bundle_dir"], "_manifest_path": prep["manifest_path"],
                "summary_path": prep["summary_path"], "artifacts": manifest.get("artifacts", [])}
    bundle_dir = prep["bundle_dir"]
    art_dir = prep["artifacts_dir"]
    shots = []
    modes = {"plain": ["plain"], "graph": ["graph"], "route": ["route"], "tide": ["tide"], "game": ["game"],
             "overview": ["plain", "graph"] + (["tide"] if "height" in proj["map"] else [])}[recipe]
    warnings = []
    for i, mode in enumerate(modes):
        out = os.path.join(art_dir, f"{mode}.png")
        try:
            res = _render(project_path, out, mode, width, extra, library)
            shots.append(pb.artifact_record(bundle_dir, out, artifact_id=mode, role="hero" if i == 0 else "gallery",
                                            kind="image", label={"plain": "Карта", "graph": "Граф", "route": "Маршрут",
                                                                 "tide": "Прилив", "game": "Как у игрока"}[mode],
                                            media_type="image/png", width=res.get("width"), height=res.get("height")))
        except backend.BackendError as exc:
            warnings.append(f"{mode}: {exc}")
    summ = proj_mod.summary(proj)
    summary = {
        "headline": f"{summ['region']}: {summ['places']} places, {summ['paths']} paths — {recipe} preview",
        "facts": {k: summ[k] for k in ("region", "places", "paths", "sockets", "has_water")},
        "warnings": warnings,
        "next_actions": ["Run `check` before `export`", "Open the hero image to judge placement and overlaps"],
    }
    manifest = pb.finalize_bundle(
        bundle_dir, prep["bundle_id"], "capture", SOFTWARE, recipe,
        source={"project_path": str(Path(project_path).resolve()), "project_fingerprint": fp},
        artifacts=shots, summary=summary, cache_key=prep["cache_key"],
        generator={"entry_point": "cli-anything-sunless-map", "harness_version": __version__,
                   "backend": "SunLess map editor (Godot 4.7) res://cli/cli.gd render"},
        status="ok" if shots and not warnings else ("partial" if shots else "error"),
        warnings=warnings or None, metrics={"places": summ["places"], "paths": summ["paths"]},
        context={"recipe": recipe, "options": options},
    )
    return {"cached": False, **{k: manifest[k] for k in ("_bundle_dir", "_manifest_path", "_summary_path", "artifacts", "status")}}


def latest(project_path: str, recipe: str | None = None) -> dict | None:
    """Newest existing bundle (no rendering)."""
    return pb.find_latest_manifest(SOFTWARE, recipe=recipe, project_path=project_path)
