"""Примеры новых карт, собранные редактором через агентский интерфейс (cli-anything-sunless-map).

Запуск (нужны Godot 4.7, установленный agent-harness и комплекты игры в ../SunLess/docs/assets/kits):

    python examples/build_examples.py            # собрать все три карты, проверить, сделать снимки
    python examples/build_examples.py ash_pass   # одну

Каждая карта: новый проект → основа и места из паков → тропы, высоты, лагеря → особые правила →
проверка (как в игре) → снимки редактора (карта, граф, «как у игрока») → снимок отрисовкой самой игры.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GAME = Path(os.environ.get("SUNLESS_GAME", HERE.parent.parent / "SunLess")).resolve()
KITS = GAME / "docs" / "assets" / "kits"
OUT = HERE / "previews"
CLI = ["cli-anything-sunless-map", "--json", "--game", str(GAME)]

CH4 = "sunless_chapter4_map_kit"
EVENTS = "sunless_map_events_kit"
SHORE = "sunless_map_kit"
ACADEMY = "academy_map_kit"
CITY = "real_city_map_kit"


def cli(*args: str, project: str | None = None) -> dict:
    cmd = CLI + (["-p", project] if project else []) + list(args)
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError:
        raise SystemExit(f"не JSON от {' '.join(args)}:\n{r.stdout}\n{r.stderr}")
    if r.returncode != 0 or not data.get("ok", False):
        raise SystemExit(f"ошибка {' '.join(args)}: {data.get('error')}\n{json.dumps(data, ensure_ascii=False)[:2000]}")
    return data


def place(pack: str, src: str, pid: str, at: tuple[float, float], size: float, name: str | None = None) -> dict:
    op = {"op": "place.add", "pack": pack, "place": src, "id": pid, "at": list(at), "size": size}
    if name:
        op["name"] = name
    return op


def sets(pid: str, **kw) -> dict:
    return {"op": "place.set", "id": pid, **kw}


def path(a: str, b: str, water: bool = False) -> dict:
    return {"op": "path.add", "a": a, "b": b, "kind": "water" if water else "path"}


CAMP_GOOD = {"rest": 25, "beds": 2, "danger": 0.05, "services": ["view"]}
CAMP_OK = {"rest": 14, "beds": 1, "danger": 0.15, "services": []}
CAMP_BAD = {"rest": 6, "beds": 0, "danger": 0.35, "services": []}


# --- 1. Пепельный перевал ------------------------------------------------------------------------

def ash_pass() -> tuple[str, str, list, str]:
    ops = [{"op": "base.set", "pack": CH4, "tex": "base"}, {"op": "tile.set", "slot": "fog", "pack": "game_forgotten_shore", "tex": "fog_tile"}]
    P = [
        (EVENTS, "strangers_camp", "pass_camp", (0.86, 0.5), 0.13, "Перевальный лагерь"),
        (CH4, "ash_dunes", "pass_dunes", (0.8, 0.36), 0.16, "Пепельные дюны"),
        (CH4, "giant_graveyard", "pass_graveyard", (0.7, 0.36), 0.12, "Кладбище гигантов"),
        (CH4, "ash_lord", "pass_lord", (0.63, 0.24), 0.2, "Трон Владыки Пепла"),
        (CH4, "stone_hulk", "pass_hulk", (0.67, 0.5), 0.14, "Каменный остов"),
        (CH4, "death_beacon", "pass_beacon", (0.53, 0.4), 0.13, "Маяк на перевале"),
        (CH4, "abyss_bridge", "pass_bridge", (0.44, 0.3), 0.14, "Мост над Бездной"),
        (CH4, "ash_bones", "pass_bones", (0.74, 0.66), 0.18, "Кости в пепле"),
        (CH4, "demon_trail", "pass_trail", (0.56, 0.68), 0.13, "Тропа Демона"),
        (CH4, "abyss_edge", "pass_edge", (0.45, 0.66), 0.13, "Край Бездны"),
        (EVENTS, "fallen_star", "pass_star", (0.86, 0.76), 0.12, "Упавшая звезда"),
        (EVENTS, "sleeping_golem", "pass_golem", (0.76, 0.8), 0.13, "Спящий голем"),
        (CH4, "sunken_idol", "pass_idol", (0.3, 0.34), 0.12, "Затонувший идол"),
        (CH4, "soul_tree", "pass_tree", (0.24, 0.46), 0.2, "Древо за Бездной"),
        (CH4, "lake_shore", "pass_lake", (0.35, 0.52), 0.12, "Чёрное озеро"),
    ]
    ops += [place(*p) for p in P]
    ops += [{"op": "state.default", "id": "pass_camp", "state": "occupied"}, {"op": "state.default", "id": "pass_star", "state": "glowing"},
            {"op": "state.default", "id": "pass_golem", "state": "dormant"}]
    for a, b in [("pass_camp", "pass_dunes"), ("pass_camp", "pass_hulk"), ("pass_dunes", "pass_graveyard"), ("pass_graveyard", "pass_lord"),
                 ("pass_graveyard", "pass_hulk"), ("pass_hulk", "pass_beacon"), ("pass_beacon", "pass_lord"), ("pass_beacon", "pass_bridge"),
                 ("pass_bridge", "pass_idol"), ("pass_idol", "pass_tree"), ("pass_tree", "pass_lake"), ("pass_lake", "pass_edge"),
                 ("pass_hulk", "pass_bones"), ("pass_bones", "pass_trail"), ("pass_trail", "pass_edge"), ("pass_bones", "pass_golem"),
                 ("pass_golem", "pass_star"), ("pass_star", "pass_camp")]:
        ops.append(path(a, b))
    camps = {"pass_camp": CAMP_GOOD, "pass_hulk": CAMP_OK, "pass_tree": CAMP_OK, "pass_lake": CAMP_OK, "pass_bones": CAMP_BAD,
             "pass_lord": CAMP_BAD, "pass_dunes": CAMP_BAD}
    for pid, camp in camps.items():
        ops.append(sets(pid, camp=camp))
    ops.append(sets("pass_camp", text="Остатки чужого каравана у входа на перевал: стены из повозок, костёр, который не гаснет."))
    m = {
        "fragile": {"pass_bridge": {"crossings": 4, "storm": True, "warn": "cracked"}},
        "risky": [{"pair": ["pass_trail", "pass_edge"], "name": "Спуск к Краю Бездны", "req": {"power": 7}, "tags": ["climb"]}],
        "phase_states": {"pass_tree": {"night": "night_glow", "blood_moon": "night_glow"}, "pass_lord": {"night": "wrath", "blood_moon": "wrath"},
                         "pass_dunes": {"ash_storm": "storm"}, "pass_bones": {"ash_storm": "storm"}},
        "zones": {"wrath": {"name": "Гнев Владыки Пепла", "center": "pass_lord", "radius": {"default": 0, "night": 1, "blood_moon": 2},
                            "camp": {"danger": 0.8}, "pass_psyche": -4, "color": [1.0, 0.3, 0.2], "decal": "decal_zone_wrath"}},
        "movers": {"demon": {"name": "Демон-следопыт", "start": "pass_bones", "target": "camp", "step": 1, "enemy": "M05",
                             "token": "decal_token_demon", "tracks": "decal_tracks_demon"}},
        "storm_band": {"tex": "decal_ash_storm_band", "phase": ["ash_storm"]},
    }
    for k, v in m.items():
        ops.append({"op": "map.set", "key": k, "value": v})
    for tex in ("decal_zone_wrath", "decal_token_demon", "decal_tracks_demon", "decal_ash_storm_band"):
        ops.append({"op": "texture.set", "pack": CH4, "tex": tex})   # откуда картинка зоны, Демона, бури
    ops.append({"op": "decal.add", "pack": CH4, "tex": "decal_beacon_fire", "place": "pass_beacon", "phase": ["night", "blood_moon"]})
    return "ash_pass", "Пепельный перевал", ops, "pass_camp"


# --- 2. Ночной Берег -----------------------------------------------------------------------------

def night_shore() -> tuple[str, str, list, str]:
    ops = [{"op": "base.set", "pack": SHORE, "tex": "base"}, {"op": "height.set", "pack": SHORE, "tex": "height"},
           {"op": "tile.set", "slot": "water", "pack": SHORE, "tex": "water_tile"}, {"op": "tile.set", "slot": "fog", "pack": SHORE, "tex": "fog_tile"}]
    P = [
        (SHORE, "stone_isle", "ns_isle", (0.69, 0.712), 0.1, "Причальный камень", "high"),
        (SHORE, "low_tide", "ns_shallows", (0.34, 0.7), 0.15, "Мёртвая отмель", "low"),
        (SHORE, "coral_maze", "ns_maze", (0.428, 0.54), 0.16, "Кровавый лабиринт", "low"),
        (SHORE, "shelter", "ns_shelter", (0.606, 0.53), 0.12, "Тёмная расщелина", "high"),
        (SHORE, "centurion_gate", "ns_gate", (0.33, 0.37), 0.13, "Ворота Центуриона", "mid"),
        (SHORE, "high_ground", "ns_watch", (0.492, 0.35), 0.12, "Ночной дозор", "high"),
        (SHORE, "hunting_grounds", "ns_hunt", (0.636, 0.375), 0.13, "Охотничьи тропы", "low"),
        (SHORE, "drowned_hall", "ns_hall", (0.762, 0.255), 0.14, "Утонувший зал", "mid"),
        (SHORE, "statue_hill", "ns_statue", (0.396, 0.225), 0.12, "Безликая статуя", "high"),
        (SHORE, "legion_ruins", "ns_legion", (0.555, 0.205), 0.13, "Лагерь Легиона", "mid"),
        (SHORE, "spire_view", "ns_ridge", (0.245, 0.255), 0.2, "Хребет у Шпиля", "high"),
        (EVENTS, "whale_carcass", "ns_whale", (0.53, 0.7), 0.13, "Туша исполина", "low"),
        (EVENTS, "legion_well", "ns_well", (0.3, 0.508), 0.11, "Колодец Легиона", "mid"),
        (EVENTS, "messenger_nest", "ns_nest", (0.65, 0.275), 0.11, "Гнездо посланника", "mid"),
    ]
    for pack, src, pid, at, size, name, h in P:
        ops.append(place(pack, src, pid, at, size, name))
        ops.append(sets(pid, height=h))
    ops += [{"op": "state.default", "id": "ns_whale", "state": "fresh"}, {"op": "state.default", "id": "ns_well", "state": "buried"},
            {"op": "state.default", "id": "ns_nest", "state": "occupied"}]
    for a, b in [("ns_isle", "ns_shelter"), ("ns_shelter", "ns_watch"), ("ns_watch", "ns_statue"), ("ns_statue", "ns_ridge"),
                 ("ns_watch", "ns_nest"), ("ns_nest", "ns_shelter"), ("ns_isle", "ns_shallows"), ("ns_ridge", "ns_gate"),
                 ("ns_shallows", "ns_maze"), ("ns_maze", "ns_well"), ("ns_well", "ns_gate"), ("ns_maze", "ns_shelter"),
                 ("ns_hunt", "ns_shelter"), ("ns_hunt", "ns_hall"), ("ns_hall", "ns_nest"), ("ns_legion", "ns_statue"),
                 ("ns_legion", "ns_watch"), ("ns_whale", "ns_shallows"), ("ns_whale", "ns_isle")]:
        ops.append(path(a, b))
    for pid, camp in {"ns_isle": CAMP_GOOD, "ns_watch": dict(CAMP_GOOD, services=["view"]), "ns_statue": CAMP_OK, "ns_ridge": CAMP_OK,
                      "ns_shelter": CAMP_OK, "ns_maze": CAMP_BAD, "ns_hall": CAMP_BAD}.items():
        ops.append(sets(pid, camp=camp))
    # появляющиеся места отлива — на площадках ила
    for at in [(0.783, 0.583), (0.215, 0.79), (0.44, 0.88), (0.3, 0.105)]:
        ops.append({"op": "socket.add", "at": list(at)})
    ops.append({"op": "map.set", "key": "ebb_sockets", "value": [0, 1, 2, 3]})
    for src, pid, name in [("sunken_watch", "ns_tower", "Утонувшая башня"), ("shell_field", "ns_shells", "Поле раковин")]:
        ops.append(place(SHORE, src, pid, (0.5, 0.5), 0.11, name))
        ops.append(sets(pid, emerge=True, height="low", camp=CAMP_BAD))
    # облики и метки ночи и Кровавой луны
    ops.append({"op": "state.add", "id": "ns_watch", "pack": EVENTS, "tex": "high_ground_beacon", "state": "beacon"})
    ops.append({"op": "state.add", "id": "ns_maze", "pack": EVENTS, "tex": "coral_maze_burning", "state": "burning"})
    ops.append({"op": "map.set", "key": "phase_states", "value": {"ns_watch": {"night": "beacon", "blood_moon": "beacon"},
                                                                  "ns_maze": {"blood_moon": "burning"}}})
    ops.append({"op": "decal.add", "pack": EVENTS, "tex": "decal_blood_pools", "place": "ns_shallows", "phase": ["blood_moon"]})
    ops.append({"op": "decal.add", "pack": EVENTS, "tex": "decal_ghost_column", "place": "ns_legion", "phase": ["night"]})
    ops.append({"op": "decal.add", "pack": EVENTS, "tex": "decal_moon_reflection", "place": "ns_whale", "phase": ["blood_moon"]})
    ops.append({"op": "texture.set", "pack": EVENTS, "tex": "crimson_haze"})
    ops.append({"op": "map.set", "key": "haze", "value": {"tex": "crimson_haze", "phase": ["blood_moon"]}})
    ops.append({"op": "map.set", "key": "view_top", "value": 0.08})
    return "night_shore", "Ночной Берег", ops, "ns_isle"


# --- 3. Город у Врат -----------------------------------------------------------------------------

def gate_town() -> tuple[str, str, list, str]:
    ops = [{"op": "base.set", "pack": ACADEMY, "tex": "base"}, {"op": "tile.set", "slot": "fog", "pack": "game_forgotten_shore", "tex": "fog_tile"}]
    P = [
        ("wall", "gt_wall", (0.512, 0.775), 0.15, "Пролом в стене"),
        ("bunker", "gt_bunker", (0.27, 0.555), 0.16, "Убежище под общежитием"),
        ("market", "gt_market", (0.518, 0.548), 0.15, "Рынок у ворот"),
        ("hospital", "gt_hospital", (0.776, 0.54), 0.17, "Полевой госпиталь"),
        ("gov_quarter", "gt_council", (0.705, 0.33), 0.17, "Совет города"),
        ("industry", "gt_works", (0.275, 0.39), 0.17, "Мастерские"),
        ("old_center", "gt_center", (0.52, 0.335), 0.16, "Старая площадь"),
        ("monorail", "gt_station", (0.53, 0.11), 0.15, "Станция монорельса"),
        ("metro_hub", "gt_metro", (0.35, 0.19), 0.11, "Спуск в подземку"),
        ("park", "gt_park", (0.2, 0.2), 0.15, "Заросший парк"),
        ("academy_link", "gt_road", (0.83, 0.18), 0.13, "Дорога к Академии"),
    ]
    for src, pid, at, size, name in P:
        ops.append(place(CITY, src, pid, at, size, name))
    for a, b in [("gt_wall", "gt_market"), ("gt_wall", "gt_bunker"), ("gt_wall", "gt_hospital"), ("gt_bunker", "gt_market"),
                 ("gt_bunker", "gt_works"), ("gt_market", "gt_center"), ("gt_market", "gt_hospital"), ("gt_hospital", "gt_council"),
                 ("gt_works", "gt_center"), ("gt_works", "gt_park"), ("gt_works", "gt_metro"), ("gt_center", "gt_council"),
                 ("gt_center", "gt_metro"), ("gt_metro", "gt_station"), ("gt_park", "gt_metro"), ("gt_council", "gt_road"),
                 ("gt_station", "gt_road")]:
        ops.append(path(a, b))
    for pid, camp in {"gt_bunker": CAMP_GOOD, "gt_hospital": dict(CAMP_OK, services=["repair"]), "gt_council": CAMP_OK,
                      "gt_station": dict(CAMP_OK, services=["view"]), "gt_wall": CAMP_BAD, "gt_park": CAMP_BAD}.items():
        ops.append(sets(pid, camp=camp))
    ops.append({"op": "decal.add", "pack": CITY, "tex": "decal_police_tape", "place": "gt_market", "phase": ["night"]})
    ops.append({"op": "decal.add", "pack": CITY, "tex": "decal_bus_evac", "place": "gt_bunker"})
    ops.append({"op": "decal.add", "pack": CITY, "tex": "decal_barricade", "place": "gt_wall"})
    ops.append({"op": "decal.add", "pack": CITY, "tex": "road_cracks", "path": ["gt_wall", "gt_market"]})
    ops.append({"op": "map.set", "key": "phase_states", "value": {"gt_wall": {"night": "breached"}, "gt_market": {"night": "alarm"}}})
    ops.append({"op": "map.set", "key": "view_top", "value": 0.04})
    return "gate_town", "Город у Врат", ops, "gt_bunker"


EXAMPLES = {"ash_pass": ash_pass, "night_shore": night_shore, "gate_town": gate_town}


def build(key: str) -> dict:
    region, title, ops, camp = EXAMPLES[key]()
    proj = str(HERE / f"{region}.mapproj")
    if Path(proj).exists():
        Path(proj).unlink()
    cli("project", "new", "--region", region, "--chapter", region, "-o", proj)
    ops_file = HERE / "ops" / f"{region}.json"
    ops_file.parent.mkdir(exist_ok=True)
    ops_file.write_text(json.dumps(ops, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    applied = cli("batch", str(ops_file), project=proj)
    check = cli("check", project=proj)
    print(f"{title}: операций {applied['applied']}, ошибок {check['errors']}, предупреждений {check['warnings']}")
    for r in check["rows"]:
        print("   ", "✗" if r["level"] == "error" else "⚠", r["text"])
    OUT.mkdir(exist_ok=True)
    shots = {}
    for recipe, extra in (("plain", []), ("graph", []), ("game", ["--from", camp])):
        res = cli("preview", "capture", "--recipe", recipe, "--width", "1600", "--force", *extra, project=proj)
        src = Path(res["_bundle_dir"]) / res["artifacts"][0]["path"]
        dst = OUT / f"{region}_{recipe}.png"
        dst.write_bytes(src.read_bytes())
        shots[recipe] = str(dst)
    if check["errors"] == 0:
        game = cli("game-shot", "--camp", camp, "-o", str(OUT / f"{region}_in_game.png"), project=proj)
        shots["in_game"] = game["out"]
    portable(proj)
    return {"region": region, "title": title, "project": proj, "check": check, "shots": shots}


def portable(proj: str) -> None:
    """Пути к игре и пакам — относительно файла проекта (пример открывается на любой машине с ../SunLess рядом)."""
    data = json.loads(Path(proj).read_text(encoding="utf-8"))
    base = Path(proj).resolve().parent
    def rel(p: str) -> str:
        try:
            return os.path.relpath(Path(p).resolve(), base).replace("\\", "/")
        except ValueError:
            return p
    data["game"] = rel(data.get("game", ""))
    for pk in data.get("packs", []):
        pk["path"] = rel(pk.get("path", ""))
    Path(proj).write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")


def main() -> None:
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")
    for kit in ("sunless-chapter4-map-kit", "sunless-map-events-kit", "sunless-map-kit", "academy-map-kit", "real-city-map-kit"):
        cli("pack", "add", str(KITS / kit))
    cli("project", "open-game", "--region", "forgotten_shore", "-o", str(HERE / "_shore_from_game.mapproj"))   # пак «Из игры» с общей плиткой тумана
    Path(HERE / "_shore_from_game.mapproj").unlink()
    keys = sys.argv[1:] or list(EXAMPLES)
    rep_file = OUT / "report.json"
    report = json.loads(rep_file.read_text(encoding="utf-8")) if rep_file.exists() else {}
    if isinstance(report, list):
        report = {r["region"]: r for r in report}
    for k in keys:
        r = build(k)
        report[r["region"]] = r
    rep_file.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
