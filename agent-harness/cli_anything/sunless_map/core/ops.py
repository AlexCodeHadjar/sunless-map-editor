"""Builders for editor operations (``apply`` ops). Pure functions — unit-tested.

Each op is executed by the editor itself (``res://cli/cli.gd`` → ``apply_op``), the same
MapDoc methods the GUI uses. Coordinates are fractions of the base image: (0, 0) top-left,
(1, 1) bottom-right; ``size`` is the vignette width as a fraction of the base width.
"""

from __future__ import annotations

from typing import Any

HEIGHTS = ("low", "mid", "high")


def _xy(x: float, y: float) -> list[float]:
    if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
        raise ValueError(f"coordinates must be fractions 0..1 of the base image, got ({x}, {y})")
    return [round(x, 3), round(y, 3)]


def place_add(pack: str, place: str, x: float, y: float, size: float | None = None, pid: str | None = None,
              name: str | None = None) -> dict:
    op: dict[str, Any] = {"op": "place.add", "pack": pack, "place": place, "at": _xy(x, y)}
    if size is not None:
        op["size"] = size
    if pid:
        op["id"] = pid
    if name:
        op["name"] = name
    return op


def place_move(pid: str, x: float, y: float) -> dict:
    return {"op": "place.move", "id": pid, "at": _xy(x, y)}


def place_resize(pid: str, size: float) -> dict:
    if not 0.02 <= size <= 0.5:
        raise ValueError("size is a fraction of the base width, 0.02..0.5 (typical 0.10–0.19)")
    return {"op": "place.resize", "id": pid, "size": size}


def place_remove(pid: str) -> dict:
    return {"op": "place.remove", "id": pid}


def place_rename(pid: str, new_id: str) -> dict:
    return {"op": "place.rename", "id": pid, "to": new_id}


def place_set(pid: str, name: str | None = None, height: str | None = None, text: str | None = None,
              camp: dict | bool | None = None, emerge: bool | None = None, group: str | None = None) -> dict:
    op: dict[str, Any] = {"op": "place.set", "id": pid}
    if name is not None:
        op["name"] = name
    if height is not None:
        if height not in HEIGHTS:
            raise ValueError(f"height must be one of {HEIGHTS}")
        op["height"] = height
    if text is not None:
        op["text"] = text
    if camp is not None:
        op["camp"] = camp
    if emerge is not None:
        op["emerge"] = emerge
    if group is not None:
        op["socket_group"] = group
    return op


def state_add(pid: str, pack: str, tex: str, state: str | None = None) -> dict:
    op = {"op": "state.add", "id": pid, "pack": pack, "tex": tex}
    if state:
        op["state"] = state
    return op


def state_remove(pid: str, state: str) -> dict:
    return {"op": "state.remove", "id": pid, "state": state}


def state_default(pid: str, state: str) -> dict:
    return {"op": "state.default", "id": pid, "state": state}


def path(a: str, b: str, remove: bool = False, water: bool = False) -> dict:
    if a == b:
        raise ValueError("a path must connect two different places")
    return {"op": "path.remove" if remove else "path.add", "a": a, "b": b, "kind": "water" if water else "path"}


def socket_add(x: float, y: float) -> dict:
    return {"op": "socket.add", "at": _xy(x, y)}


def socket_move(index: int, x: float, y: float) -> dict:
    return {"op": "socket.move", "index": index, "at": _xy(x, y)}


def socket_remove(index: int) -> dict:
    return {"op": "socket.remove", "index": index}


def set_texture(slot: str, pack: str, tex: str) -> dict:
    if slot == "base":
        return {"op": "base.set", "pack": pack, "tex": tex}
    if slot == "height":
        return {"op": "height.set", "pack": pack, "tex": tex}
    if slot in ("fog", "water"):
        return {"op": "tile.set", "slot": slot, "pack": pack, "tex": tex}
    raise ValueError("slot must be base, height, fog or water")


def decal_add(pack: str, tex: str, place: str | None = None, path_pair: tuple[str, str] | None = None,
              phases: list[str] | None = None, from_day: int | None = None) -> dict:
    if bool(place) == bool(path_pair):
        raise ValueError("a decal goes either on a place (--place) or on a path (--path A B)")
    op: dict[str, Any] = {"op": "decal.add", "pack": pack, "tex": tex, "decal": tex}
    if place:
        op["place"] = place
    else:
        op["path"] = list(path_pair)
    if phases:
        op["phase"] = phases
    if from_day is not None:
        op["from_day"] = from_day
    return op


def map_set(key: str, value: Any) -> dict:
    return {"op": "map.set", "key": key, "value": value}
