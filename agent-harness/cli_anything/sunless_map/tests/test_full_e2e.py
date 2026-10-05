"""E2E tests: the installed CLI drives the real editor (Godot 4.7). Godot is a hard dependency."""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from PIL import Image


def _resolve_cli(name):
    """Installed command, or python -m for development. CLI_ANYTHING_FORCE_INSTALLED=1 requires installed."""
    force = os.environ.get("CLI_ANYTHING_FORCE_INSTALLED", "").strip() == "1"
    path = shutil.which(name)
    if path:
        print(f"[_resolve_cli] Using installed command: {path}")
        return [path]
    if force:
        raise RuntimeError(f"{name} not found in PATH. Install with: pip install -e .")
    print(f"[_resolve_cli] Falling back to: {sys.executable} -m cli_anything.sunless_map")
    return [sys.executable, "-m", "cli_anything.sunless_map"]


CLI = _resolve_cli("cli-anything-sunless-map")


def make_pack(d: Path) -> None:
    """A small pack in the ТЗ layout: base/, places/<place>/<look>.png, tiles/, decals/."""
    for sub in ("base", "places/tower", "places/swamp", "places/hill", "tiles", "decals"):
        (d / sub).mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (1024, 512), (60, 80, 60)).save(d / "base" / "base.png")
    for place, looks, col in (("tower", ("dry", "burning"), (200, 40, 40)), ("swamp", ("dry", "flooded"), (40, 160, 60)),
                              ("hill", ("dry",), (160, 160, 40))):
        for look in looks:
            im = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
            im.paste(col + (255,), (64, 64, 192, 192))
            im.save(d / "places" / place / f"{look}.png")
    Image.new("RGB", (128, 128), (90, 90, 100)).save(d / "tiles" / "fog_tile.png")
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    im.paste((255, 255, 255, 255), (32, 32, 96, 96))
    im.save(d / "decals" / "decal_skull.png")


def make_game(d: Path) -> None:
    (d / "data" / "maps").mkdir(parents=True)
    (d / "project.godot").write_text("config_version=5\n", encoding="utf-8")
    (d / "data" / "locations.json").write_text(json.dumps([{"id": "elsewhere", "name": "Чужое", "chapter": "x", "region": "x"}],
                                                          ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    (d / "data" / "shops.json").write_text("[]\n", encoding="utf-8")


@pytest.fixture()
def env(tmp_path):
    make_pack(tmp_path / "pack")
    make_game(tmp_path / "game")
    return tmp_path


class TestCLISubprocess:
    def _run(self, env, args, check=True):
        base = CLI + ["--json", "--library", str(env / "lib.json"), "--game", str(env / "game")]
        r = subprocess.run(base + args, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if check and r.returncode != 0:
            raise AssertionError(f"command failed: {args}\n{r.stdout}\n{r.stderr}")
        return json.loads(r.stdout) if r.stdout.strip().startswith("{") else {"raw": r.stdout, "code": r.returncode}

    def test_help(self):
        r = subprocess.run(CLI + ["--help"], capture_output=True, text=True, encoding="utf-8")
        assert r.returncode == 0 and "SunLess" in r.stdout

    def test_full_new_map_workflow(self, env):
        proj = str(env / "swamp.mapproj")
        res = self._run(env, ["project", "new", "--region", "swamp_test", "-o", proj])
        assert res["ok"] and Path(proj).is_file()
        pk = self._run(env, ["pack", "add", str(env / "pack")])
        pid = pk["id"]
        assert set(pk["places"]) == {"tower", "swamp", "hill"}
        tex = self._run(env, ["-p", proj, "pack", "textures", pid, "--kind", "place"])
        assert tex["places"]["tower"] == ["dry", "burning"]
        self._run(env, ["-p", proj, "map", "texture", "base", pid, "base"])
        self._run(env, ["-p", proj, "map", "texture", "fog", pid, "fog_tile"])
        r1 = self._run(env, ["-p", proj, "place", "add", pid, "tower", "0.3", "0.4", "--size", "0.12", "--name", "Башня"])
        assert r1["results"][0]["states"] == ["dry", "burning"]
        self._run(env, ["-p", proj, "place", "add", pid, "swamp", "0.6", "0.5"])
        self._run(env, ["-p", proj, "place", "add", pid, "hill", "0.45", "0.25"])
        # not connected yet: the game's check must fail
        chk = self._run(env, ["-p", proj, "check"])
        assert chk["errors"] > 0
        self._run(env, ["-p", proj, "path", "add", "tower", "swamp"])
        self._run(env, ["-p", proj, "path", "add", "Башня", "hill"])
        self._run(env, ["-p", proj, "place", "set", "hill", "--height", "high", "--camp-rest", "20"])
        self._run(env, ["-p", proj, "map", "decal", pid, "decal_skull", "--place", "tower", "--phase", "night"])
        chk = self._run(env, ["-p", proj, "check"])
        assert chk["errors"] == 0, chk["rows"]
        rt = self._run(env, ["-p", proj, "route", "swamp", "hill"])
        assert rt["path"] == ["tower", "hill"] and rt["steps"] == 2
        st = self._run(env, ["-p", proj, "step", "tower"])
        assert st["neighbors"] == {"hill": "", "swamp": ""}
        # undo the last edit (decal), redo it
        assert self._run(env, ["-p", proj, "session", "undo"])["undone"] == "decal"
        assert "place_decals" not in json.loads(Path(proj).read_text(encoding="utf-8"))["map"]
        self._run(env, ["-p", proj, "session", "redo"])
        # export: dry run, then for real
        dry = self._run(env, ["-p", proj, "export", "--dry-run"])
        st2 = {i["rel"]: i["status"] for i in dry["items"]}
        assert st2["data/maps/swamp_test.json"] == "new"
        assert st2["art/map/swamp_test/tower_burning.webp"] == "new"
        assert not (env / "game" / "data" / "maps" / "swamp_test.json").exists()
        ex = self._run(env, ["-p", proj, "export"])
        assert ex["ok"] and len(ex["written"]) >= 8
        art = env / "game" / "art" / "map" / "swamp_test"
        for f in ("base.webp", "tower_dry.webp", "tower_burning.webp", "swamp_flooded.webp", "decal_skull.webp", "fog_tile.webp"):
            data = (art / f).read_bytes()
            assert data[:4] == b"RIFF" and data[8:12] == b"WEBP", f
        assert Image.open(art / "base.webp").size == (3072, 1536)
        assert Image.open(art / "tower_dry.webp").size == (512, 512)
        assert Image.open(art / "decal_skull.webp").size == (256, 256)
        m = json.loads((env / "game" / "data" / "maps" / "swamp_test.json").read_text(encoding="utf-8"))
        assert m["region"] == "swamp_test" and len(m["places"]) == 3 and len(m["paths"]) == 2
        locs = json.loads((env / "game" / "data" / "locations.json").read_text(encoding="utf-8"))
        assert [l["id"] for l in locs] == ["elsewhere", "tower", "swamp", "hill"]
        assert locs[1]["name"] == "Башня" and locs[3]["height"] == "high"
        print(f"\n  exported map: {env / 'game' / 'data' / 'maps' / 'swamp_test.json'}")
        # second export writes nothing
        again = self._run(env, ["-p", proj, "export", "--dry-run"])
        assert all(i["status"] == "same" for i in again["items"])

    def test_preview_bundle(self, env):
        proj = str(env / "p.mapproj")
        self._run(env, ["project", "new", "--region", "prev_test", "-o", proj])
        pid = self._run(env, ["pack", "add", str(env / "pack")])["id"]
        self._run(env, ["-p", proj, "map", "texture", "base", pid, "base"])
        self._run(env, ["-p", proj, "place", "add", pid, "tower", "0.3", "0.4"])
        self._run(env, ["-p", proj, "place", "add", pid, "swamp", "0.7", "0.6"])
        self._run(env, ["-p", proj, "path", "add", "tower", "swamp"])
        res = self._run(env, ["-p", proj, "preview", "capture", "--recipe", "overview", "--width", "800"])
        assert res["ok"] and not res["cached"]
        manifest = json.loads(Path(res["_manifest_path"]).read_text(encoding="utf-8"))
        assert manifest["protocol_version"] == "preview-bundle/v1" and manifest["software"] == "sunless_map"
        for a in manifest["artifacts"]:
            png = Path(res["_bundle_dir"]) / a["path"]
            assert png.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n"
            im = Image.open(png).convert("RGB")
            assert im.size == (800, 400)
            # the base is drawn: the picture is not one flat colour
            assert len(set(im.resize((40, 20)).get_flattened_data())) > 3
            print(f"\n  preview: {png}")
        cached = self._run(env, ["-p", proj, "preview", "capture", "--recipe", "overview", "--width", "800"])
        assert cached["cached"]
        latest = self._run(env, ["-p", proj, "preview", "latest", "--recipe", "overview"])
        assert latest["_bundle_dir"] == res["_bundle_dir"]


def _game_dir():
    env = os.environ.get("SUNLESS_GAME")
    if env and Path(env, "project.godot").is_file():
        return env
    ed = Path(__file__).resolve().parents[4]
    sib = ed.parent / "SunLess"
    return str(sib) if (sib / "project.godot").is_file() else None


@pytest.mark.skipif(_game_dir() is None, reason="game folder SunLess not found (SUNLESS_GAME)")
class TestRealGame:
    def test_shore_open_unchanged_export_and_route(self, tmp_path):
        g = _game_dir()
        base = CLI + ["--json", "--library", str(tmp_path / "lib.json"), "--game", g]
        proj = str(tmp_path / "shore.mapproj")
        run = lambda a: json.loads(subprocess.run(base + a, capture_output=True, text=True, encoding="utf-8").stdout)
        assert run(["project", "open-game", "--region", "forgotten_shore", "-o", proj])["places"] == 29
        assert run(["-p", proj, "check"])["errors"] == 0
        dry = run(["-p", proj, "export", "--dry-run"])
        assert [i for i in dry["items"] if i["status"] != "same"] == []
        rt = run(["-p", proj, "route", "Каменная платформа", "Костяной хребет"])
        assert rt["steps"] == 4 and rt["names"][0] == "Каменная платформа"
