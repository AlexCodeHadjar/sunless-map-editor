"""Unit tests: project inspection, ops builders, session undo/redo, backend argument building. No Godot."""

import json
import os

import pytest

from cli_anything.sunless_map.core import ops as O
from cli_anything.sunless_map.core import project as P
from cli_anything.sunless_map.core.session import Session
from cli_anything.sunless_map.utils import godot_backend as B


def _proj(tmp_path, **over):
    data = {
        "format": 1, "game": "", "region": "r", "chapter": "c", "packs": [{"id": "p1", "version": 1}],
        "textures": {"base": {"pack": "p1", "tex": "base"}},
        "map": {"region": "r", "places": {
            "a": {"at": [0.2, 0.5], "size": 0.1, "states": ["dry"]},
            "b": {"at": [0.5, 0.5], "size": 0.12, "states": ["dry", "flooded"]},
            "s": {"at": [0.8, 0.5], "size": 0.1, "states": ["dry"]}},
            "paths": [["a", "b"], ["b", "s"]], "sockets": [[0.1, 0.1]], "water_paths": [["a", "s"]]},
        "locations": {"a": {"id": "a", "name": "Альфа", "height": "high"}, "b": {"id": "b", "name": "Бета", "emerge": True}},
        "shops": {"s": {"id": "s", "name": "Лавка"}},
        "editor": {},
    }
    data.update(over)
    f = tmp_path / "t.mapproj"
    f.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return str(f)


class TestProject:
    def test_load_and_summary(self, tmp_path):
        pr = P.load(_proj(tmp_path))
        s = P.summary(pr)
        assert s["places"] == 3 and s["paths"] == 2 and s["water_paths"] == 1 and s["sockets"] == 1
        assert s["has_water"] is False and s["packs"] == ["p1"]

    def test_places(self, tmp_path):
        rows = {r["id"]: r for r in P.places(P.load(_proj(tmp_path)))}
        assert rows["a"]["name"] == "Альфа" and rows["a"]["paths"] == ["b"]
        assert rows["s"]["shop"] and rows["s"]["height"] == "high"
        assert rows["b"]["emerge"] and rows["b"]["paths"] == ["a", "s"]

    def test_paths_and_sockets(self, tmp_path):
        pr = P.load(_proj(tmp_path))
        kinds = [p["kind"] for p in P.paths(pr)]
        assert kinds == ["path", "path", "water"]
        assert P.sockets(pr) == [{"index": 0, "number": 1, "at": [0.1, 0.1]}]

    def test_find_place_by_name(self, tmp_path):
        pr = P.load(_proj(tmp_path))
        assert P.find_place(pr, "бета") == "b"
        assert P.find_place(pr, "a") == "a"
        with pytest.raises(P.ProjectError):
            P.find_place(pr, "нет такого")

    def test_bad_files(self, tmp_path):
        with pytest.raises(P.ProjectError):
            P.load(str(tmp_path / "missing.mapproj"))
        bad = tmp_path / "bad.mapproj"
        bad.write_text("{oops", encoding="utf-8")
        with pytest.raises(P.ProjectError):
            P.load(str(bad))
        nomap = tmp_path / "nomap.mapproj"
        nomap.write_text("{}", encoding="utf-8")
        with pytest.raises(P.ProjectError):
            P.load(str(nomap))

    def test_fingerprint_changes(self, tmp_path):
        f = _proj(tmp_path)
        a = P.fingerprint(f)
        with open(f, "a", encoding="utf-8") as fh:
            fh.write(" ")
        assert P.fingerprint(f) != a and a.startswith("sha256:")


class TestOps:
    def test_place_add(self):
        op = O.place_add("pk", "soul_tree", 0.51234, 0.4, 0.15, "tree", "Древо")
        assert op == {"op": "place.add", "pack": "pk", "place": "soul_tree", "at": [0.512, 0.4], "size": 0.15, "id": "tree", "name": "Древо"}

    def test_coordinates_validated(self):
        with pytest.raises(ValueError):
            O.place_move("a", 1.5, 0.2)
        with pytest.raises(ValueError):
            O.socket_add(-0.1, 0.2)

    def test_size_validated(self):
        with pytest.raises(ValueError):
            O.place_resize("a", 0.9)
        assert O.place_resize("a", 0.12)["size"] == 0.12

    def test_place_set(self):
        op = O.place_set("a", name="Х", height="high", camp={"rest": 20}, emerge=False)
        assert op["height"] == "high" and op["camp"] == {"rest": 20} and op["emerge"] is False
        with pytest.raises(ValueError):
            O.place_set("a", height="sky")

    def test_paths(self):
        assert O.path("a", "b") == {"op": "path.add", "a": "a", "b": "b", "kind": "path"}
        assert O.path("a", "b", remove=True, water=True)["op"] == "path.remove"
        with pytest.raises(ValueError):
            O.path("a", "a")

    def test_textures_and_decals(self):
        assert O.set_texture("fog", "p", "fog_tile") == {"op": "tile.set", "slot": "fog", "pack": "p", "tex": "fog_tile"}
        assert O.set_texture("base", "p", "base")["op"] == "base.set"
        with pytest.raises(ValueError):
            O.set_texture("sky", "p", "x")
        d = O.decal_add("p", "decal_x", place="a", phases=["night"])
        assert d["place"] == "a" and d["phase"] == ["night"]
        with pytest.raises(ValueError):
            O.decal_add("p", "decal_x")


class TestSession:
    def test_undo_redo(self, tmp_path):
        f = _proj(tmp_path)
        s = Session(f)
        original = open(f, encoding="utf-8").read()
        s.before_edit("edit 1")
        with open(f, "w", encoding="utf-8") as fh:
            fh.write(original.replace("Альфа", "Гамма"))
        assert Session(f).status()["undo"] == ["edit 1"]
        assert Session(f).undo() == "edit 1"
        assert "Альфа" in open(f, encoding="utf-8").read()
        assert Session(f).redo() == "edit 1"
        assert "Гамма" in open(f, encoding="utf-8").read()
        assert Session(f).redo() is None

    def test_new_edit_clears_redo(self, tmp_path):
        f = _proj(tmp_path)
        s = Session(f)
        s.before_edit("one")
        s.undo()
        s = Session(f)
        assert s.status()["redo"] == ["one"]
        s.before_edit("two")
        assert Session(f).status()["redo"] == []


class TestBackendArgs:
    def test_headless_args(self):
        args = B.build_args("check", [], {"project": "x.mapproj", "boat": True, "tide": None, "dry_run": False, "ops": [{"op": "a"}]},
                            godot="godot.exe", editor="ED")
        assert args[:6] == ["godot.exe", "--headless", "--path", "ED", "-s", "res://cli/cli.gd"]
        assert args[6:8] == ["--", "check"]
        assert "--boat" in args and "--tide" not in args and "--dry-run" not in args
        assert args[args.index("--ops") + 1] == '[{"op": "a"}]'

    def test_render_has_window(self):
        args = B.build_args("render", [], {}, render=True, godot="g", editor="E")
        assert "--headless" not in args and "--resolution" in args

    def test_parse_output(self):
        out = "Godot Engine v4.7\nnoise\n" + B.MARK + '{"ok": true, "x": "Я"}\n'
        assert B.parse_output(out) == {"ok": True, "x": "Я"}
        with pytest.raises(B.BackendError):
            B.parse_output("nothing here")

    def test_find_editor_from_package(self):
        ed = B.find_editor()
        assert os.path.isfile(os.path.join(ed, "project.godot"))
        assert os.path.isfile(os.path.join(ed, "cli", "cli.gd"))
