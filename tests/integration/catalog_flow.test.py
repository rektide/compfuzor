#!/usr/bin/env python3
"""Exercise opt-in catalog flow execution, ordering, failures, and status folding."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "build" / "runtime" / "compfuzor-runtime.mjs"


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def run(deployment: Path, flow: str, *options: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [str(RUNTIME), "flow", "--deployment", str(deployment), *options, flow],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if check and result.returncode:
        raise AssertionError(f"flow failed\n{result.stdout}\n{result.stderr}")
    return result


def invocation(identity: str, flow: str, script: str, args: list[str], *, exit2: str = "not-applicable") -> dict:
    protocol = "legacy-status-v1" if flow == "status" else "legacy-exit-v1"
    return {
        "version": 1,
        "id": identity,
        "flow": flow,
        "scope": "system",
        "index": 50,
        "phase": "inspect" if flow == "status" else "publish",
        "native": False,
        "invoke": {
            "action": f"command:{script}",
            "args": args,
            "handler": {
                "kind": "exec",
                "path": f"bin/{script}",
                "protocol": protocol,
                "exit2": exit2,
            },
        },
        "contributors": ["deployment:test"],
        "source": {"kind": "test"},
    }


def test_catalog_flow_execution() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-catalog-flow-") as tmp:
        deployment = Path(tmp)
        root = deployment / "etc" / "compfuzor-runtime"
        compiled = root / "workflows" / "compiled"
        (root / "workflows" / "site").mkdir(parents=True)
        (deployment / "bin").mkdir()
        log = deployment / "flow.log"
        script = deployment / "bin" / "step.sh"
        script.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$2"\nexit "$3"\n', encoding="utf-8")
        script.chmod(0o755)

        install_entries = ["install.first", "install.second"]
        status_entries = ["status.drift", "status.na", "status.after"]
        catalog = {
            "version": 1,
            "deployment": {"id": "deployment:test", "name": "test"},
            "contributors": [{"id": "deployment:test", "kind": "deployment"}],
            "resources": [],
            "commands": [],
            "actions": [],
            "flows": {
                "build": {"name": "build", "entries": []},
                "install": {"name": "install", "entries": install_entries},
                "status": {"name": "status", "entries": status_entries},
            },
            "execution": {"authority": "catalog", "catalogOnly": False},
        }
        write_json(root / "catalog.json", catalog)
        write_json(
            compiled / "50-install-001-first.json",
            invocation("install.first", "install", "step.sh", ["first", str(log), "0"]),
        )
        write_json(
            compiled / "50-install-002-second.json",
            invocation("install.second", "install", "step.sh", ["second", str(log), "0"]),
        )
        write_json(
            compiled / "50-status-001-drift.json",
            invocation("status.drift", "status", "step.sh", ["drift", str(log), "1"]),
        )
        write_json(
            compiled / "50-status-002-na.json",
            invocation("status.na", "status", "step.sh", ["na", str(log), "2"]),
        )
        write_json(
            compiled / "50-status-003-after.json",
            invocation("status.after", "status", "step.sh", ["after", str(log), "0"]),
        )

        run(deployment, "install")
        assert log.read_text(encoding="utf-8").splitlines() == ["first", "second"]
        log.unlink()

        dry = run(deployment, "install", "--dry-run")
        assert "would run" in dry.stderr
        assert not log.exists()

        status = run(deployment, "status", check=False)
        assert status.returncode == 1
        assert log.read_text(encoding="utf-8").splitlines() == ["drift", "na", "after"]

        catalog["execution"] = {"authority": "legacy-shell", "catalogOnly": True}
        write_json(root / "catalog.json", catalog)
        disabled = run(deployment, "install", check=False)
        assert disabled.returncode == 2
        assert "execution is disabled" in disabled.stderr


if __name__ == "__main__":
    test_catalog_flow_execution()
    print("ok: opt-in catalog flow execution")
