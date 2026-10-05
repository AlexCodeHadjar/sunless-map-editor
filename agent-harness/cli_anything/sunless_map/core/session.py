"""Session state: current project and undo/redo of CLI edits.

Before every mutating command the project file is snapshotted into
``<project_dir>/.cli-anything/sunless_map/<project>/history``. ``undo`` restores the
previous snapshot, ``redo`` re-applies. Writes go through a temp file (no torn files).
"""

from __future__ import annotations

import json
import os
import shutil
import time
from pathlib import Path


def _atomic_copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_suffix(dst.suffix + ".tmp")
    shutil.copyfile(src, tmp)
    os.replace(tmp, dst)


class Session:
    def __init__(self, project_path: str):
        self.project = Path(project_path).resolve()
        self.dir = self.project.parent / ".cli-anything" / "sunless_map" / self.project.stem
        self.state_file = self.dir / "session.json"
        self.state = {"undo": [], "redo": [], "counter": 0}
        if self.state_file.is_file():
            try:
                self.state.update(json.loads(self.state_file.read_text(encoding="utf-8")))
            except json.JSONDecodeError:
                pass

    def _save(self) -> None:
        self.dir.mkdir(parents=True, exist_ok=True)
        tmp = self.state_file.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.state, ensure_ascii=False, indent=1), encoding="utf-8")
        os.replace(tmp, self.state_file)

    def _snap(self) -> str:
        self.state["counter"] += 1
        name = f"{self.state['counter']:05d}.mapproj"
        _atomic_copy(self.project, self.dir / "history" / name)
        return name

    def before_edit(self, label: str) -> None:
        """Call right before a mutating command."""
        if not self.project.is_file():
            return
        name = self._snap()
        self.state["undo"].append({"label": label, "file": name, "time": time.time()})
        for item in self.state["redo"]:
            (self.dir / "history" / item["file"]).unlink(missing_ok=True)
        self.state["redo"] = []
        self._save()

    def undo(self) -> str | None:
        if not self.state["undo"]:
            return None
        item = self.state["undo"].pop()
        cur = self._snap()
        self.state["redo"].append({"label": item["label"], "file": cur, "time": time.time()})
        _atomic_copy(self.dir / "history" / item["file"], self.project)
        self._save()
        return item["label"]

    def redo(self) -> str | None:
        if not self.state["redo"]:
            return None
        item = self.state["redo"].pop()
        cur = self._snap()
        self.state["undo"].append({"label": item["label"], "file": cur, "time": time.time()})
        _atomic_copy(self.dir / "history" / item["file"], self.project)
        self._save()
        return item["label"]

    def status(self) -> dict:
        return {
            "project": str(self.project),
            "session_dir": str(self.dir),
            "undo": [i["label"] for i in self.state["undo"]],
            "redo": [i["label"] for i in self.state["redo"]],
        }
