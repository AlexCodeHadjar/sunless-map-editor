"""Read-only access to a SunLess map project (.mapproj, JSON).

The .mapproj is the editor's native format::

    {"format": 1, "game": ..., "region": ..., "chapter": ..., "packs": [...], "textures": {...},
     "map": {...same as data/maps/<region>.json...}, "locations": {...}, "shops": {...}, "editor": {...}}

Mutations go through the editor backend (``apply``) so the rules live in one place;
this module only inspects the file — fast, no Godot start-up.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


class ProjectError(ValueError):
    pass


def load(path: str) -> dict:
    p = Path(path)
    if not p.is_file():
        raise ProjectError(f"project not found: {path}")
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ProjectError(f"project is not valid JSON: {exc}") from exc
    if not isinstance(data, dict) or "map" not in data:
        raise ProjectError("not a SunLess map project (no 'map' field)")
    return data


def fingerprint(path: str) -> str:
    return "sha256:" + hashlib.sha256(Path(path).read_bytes()).hexdigest()


def display_name(proj: dict, lid: str) -> str:
    loc = proj.get("locations", {}).get(lid) or proj.get("shops", {}).get(lid) or {}
    return str(loc.get("name", lid))


def places(proj: dict) -> list[dict]:
    """Places with their game-facing properties, in map order."""
    out = []
    paths = proj["map"].get("paths", [])
    for lid, pl in proj["map"].get("places", {}).items():
        loc = proj.get("locations", {}).get(lid, {})
        out.append({
            "id": lid,
            "name": display_name(proj, lid),
            "at": pl.get("at"),
            "size": pl.get("size"),
            "states": pl.get("states", ["dry"]),
            "height": "high" if lid in proj.get("shops", {}) else loc.get("height", ""),
            "shop": lid in proj.get("shops", {}),
            "emerge": bool(loc.get("emerge", False)),
            "camp": loc.get("camp"),
            "paths": sorted({b if a == lid else a for a, b in paths if lid in (a, b)}),
        })
    return out


def paths(proj: dict) -> list[dict]:
    out = [{"a": a, "b": b, "kind": "path", "names": [display_name(proj, a), display_name(proj, b)]}
           for a, b in proj["map"].get("paths", [])]
    out += [{"a": a, "b": b, "kind": "water", "names": [display_name(proj, a), display_name(proj, b)]}
            for a, b in proj["map"].get("water_paths", [])]
    return out


def sockets(proj: dict) -> list[dict]:
    return [{"index": i, "number": i + 1, "at": at} for i, at in enumerate(proj["map"].get("sockets", []))]


def summary(proj: dict) -> dict[str, Any]:
    m = proj["map"]
    return {
        "region": proj.get("region"),
        "chapter": proj.get("chapter"),
        "game": proj.get("game"),
        "places": len(m.get("places", {})),
        "paths": len(m.get("paths", [])),
        "water_paths": len(m.get("water_paths", [])),
        "sockets": len(m.get("sockets", [])),
        "has_water": "height" in m,
        "packs": [p.get("id") for p in proj.get("packs", [])],
        "base": proj.get("textures", {}).get("base"),
    }


def find_place(proj: dict, ref: str) -> str:
    """Accept a place id or its (Russian) display name."""
    pl = proj["map"].get("places", {})
    if ref in pl:
        return ref
    low = ref.strip().lower()
    for lid in pl:
        if display_name(proj, lid).lower() == low:
            return lid
    raise ProjectError(f"no place '{ref}' (use an id from `place list`)")
