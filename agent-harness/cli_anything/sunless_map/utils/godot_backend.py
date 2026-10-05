"""Backend: invokes the real SunLess map editor (a Godot 4.7 project) without a window.

Every rule — edits, checks, routes, export, rendering — runs inside the editor itself
(``res://cli/cli.gd``), so the agent CLI and the GUI can never disagree.

    godot --headless --path <editor> -s res://cli/cli.gd -- <command> [--key value ...]

Rendering (``render``) needs the real renderer, so it runs Godot without ``--headless``
(a tiny window flashes for a moment).
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any, Iterable

MARK = "@@SUNLESS_JSON@@"

_GODOT_CANDIDATES = [
    r"D:\Godot_v4.7.2-stable_win64_console.exe",
    r"C:\Godot\Godot_v4.7.2-stable_win64_console.exe",
    r"C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe",
]


class BackendError(RuntimeError):
    """The editor backend failed or returned {ok: false}."""

    def __init__(self, message: str, payload: dict | None = None):
        super().__init__(message)
        self.payload = payload or {}


def find_godot() -> str:
    """Godot 4.7 console executable (stdout must reach us)."""
    for env in ("SUNLESS_GODOT", "GODOT"):
        val = os.environ.get(env, "").strip()
        if val and Path(val).is_file():
            return val
    for cand in _GODOT_CANDIDATES:
        if Path(cand).is_file():
            return cand
    for name in ("Godot_v4.7.2-stable_win64_console", "godot4", "godot"):
        found = shutil.which(name)
        if found:
            return found
    raise RuntimeError(
        "Godot 4.7 not found. Install Godot 4.7.2 (https://godotengine.org/download) and set "
        "SUNLESS_GODOT to the *console* executable, e.g. "
        "set SUNLESS_GODOT=D:\\Godot_v4.7.2-stable_win64_console.exe"
    )


def find_editor() -> str:
    """Folder of the SunLess map editor (project.godot)."""
    env = os.environ.get("SUNLESS_MAP_EDITOR", "").strip()
    if env and (Path(env) / "project.godot").is_file():
        return str(Path(env).resolve())
    for parent in Path(__file__).resolve().parents:
        proj = parent / "project.godot"
        if proj.is_file() and (parent / "cli" / "cli.gd").is_file():
            return str(parent)
    raise RuntimeError(
        "SunLess map editor not found. Set SUNLESS_MAP_EDITOR to the editor folder "
        "(the one with project.godot and cli/cli.gd)."
    )


def build_args(command: str, positional: Iterable[str] = (), options: dict[str, Any] | None = None,
               render: bool = False, godot: str | None = None, editor: str | None = None) -> list[str]:
    """Command line for one backend call (pure function — unit-tested)."""
    godot = godot or find_godot()
    editor = editor or find_editor()
    args = [godot]
    if render:
        args += ["--resolution", "64x64", "--position", "0,0"]
    else:
        args += ["--headless"]
    args += ["--path", editor, "-s", "res://cli/cli.gd", "--", command]
    args += [str(p) for p in positional]
    for key, val in (options or {}).items():
        if val is None or val is False:
            continue
        flag = "--" + key.replace("_", "-")
        if val is True:
            args.append(flag)
        elif isinstance(val, (dict, list)):
            args += [flag, json.dumps(val, ensure_ascii=False)]
        else:
            args += [flag, str(val)]
    return args


def parse_output(stdout: str) -> dict:
    """Find the backend's JSON line among Godot's own log lines."""
    for line in reversed(stdout.splitlines()):
        idx = line.find(MARK)
        if idx >= 0:
            return json.loads(line[idx + len(MARK):])
    raise BackendError("backend printed no result line", {"stdout_tail": stdout[-2000:]})


def run(command: str, positional: Iterable[str] = (), options: dict[str, Any] | None = None,
        render: bool = False, timeout: int = 600, check: bool = True) -> dict:
    """Run one editor command and return its JSON result."""
    args = build_args(command, positional, options, render=render)
    proc = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    try:
        data = parse_output(proc.stdout)
    except BackendError as exc:
        tail = (proc.stdout + "\n" + proc.stderr)[-2500:]
        raise BackendError(f"editor backend failed (exit {proc.returncode}). Output tail:\n{tail}") from exc
    if check and not data.get("ok", False):
        raise BackendError(str(data.get("error", "backend error")), data)
    return data
