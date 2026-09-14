#!/usr/bin/env python3
"""Exercise read-only runtime catalog inspection and site placement overrides."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "build" / "runtime" / "compfuzor-runtime.mjs"


def run(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [str(RUNTIME), "catalog", *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if check and result.returncode:
        raise AssertionError(f"catalog failed\n{result.stdout}\n{result.stderr}")
    return result


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def test_catalog_and_site_placement() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-runtime-catalog-") as tmp:
        deployment = Path(tmp)
        root = deployment / "etc" / "compfuzor-runtime"
        compiled = root / "workflows" / "compiled"
        site = root / "workflows" / "site"
        site.mkdir(parents=True)
        catalog = {
            "version": 1,
            "deployment": {"id": "deployment:test", "name": "test"},
            "contributors": [
                {"id": "deployment:test", "kind": "deployment", "name": "test"},
                {"id": "subsystem:links", "kind": "subsystem", "name": "links"},
            ],
            "resources": [{"id": "links", "contract": "compfuzor.links/v2", "path": "links.json"}],
            "commands": [{"id": "command:install-links.sh", "name": "install-links.sh"}],
            "actions": [{"id": "command:install-links.sh", "action": "install"}],
            "flows": {
                "build": {"name": "build", "entries": ["build.tool"]},
                "install": {"name": "install", "entries": ["links.install"]},
                "status": {"name": "status", "entries": []},
            },
            "execution": {"authority": "legacy-shell", "catalogOnly": True},
        }
        invocation = {
            "version": 1,
            "id": "links.install",
            "flow": "install",
            "scope": "system",
            "index": 95,
            "phase": "record",
            "native": False,
            "invoke": {
                "action": "command:install-links.sh",
                "handler": {"kind": "exec", "path": "bin/install-links.sh", "protocol": "legacy-exit-v1"},
            },
            "contributors": ["subsystem:links"],
            "source": {"kind": "legacy-bin", "name": "install-links.sh"},
        }
        write_json(root / "catalog.json", catalog)
        source = compiled / "95-install-links.json"
        write_json(source, invocation)
        write_json(
            compiled / "50-build-001-build-rust-sh.json",
            {
                **invocation,
                "id": "build.tool",
                "flow": "build",
                "index": 50,
                "phase": "compile",
            },
        )
        write_json(
            compiled / "40-install-stale.json",
            {**invocation, "id": "stale.install", "index": 40},
        )

        summary = json.loads(run("--deployment", str(deployment), "--json").stdout)
        assert summary["authority"] == "legacy-shell"
        assert summary["contributors"] == 2
        flow = json.loads(run("--deployment", str(deployment), "--json", "flow", "install").stdout)
        assert flow[0]["effectiveIndex"] == 95
        assert flow[0]["effectivePhase"] == "record"
        assert flow[0]["selectedLayer"] == "compiled"

        reordered = site / "55-install-links.json"
        reordered.symlink_to(source)
        flow = json.loads(run("--deployment", str(deployment), "--json", "flow", "install").stdout)
        assert flow[0]["effectiveIndex"] == 55
        assert flow[0]["effectivePhase"] == "publish"
        assert flow[0]["selectedLayer"] == "site"
        assert flow[0]["shadowedPath"] == str(source)

        reordered.unlink()
        write_json(reordered, {"id": "links.install", "state": "absent"})
        assert json.loads(run("--deployment", str(deployment), "--json", "flow", "install").stdout) == []
        assert json.loads(run("--deployment", str(deployment), "--json", "flows").stdout) == {
            "build": "1",
            "install": "0",
            "status": "0",
        }

        write_json(site / "60-install-unknown.json", {**invocation, "id": "unknown.site"})
        rejected = run("--deployment", str(deployment), "flow", "install", check=False)
        assert rejected.returncode == 2
        assert "undeclared contribution" in rejected.stderr


if __name__ == "__main__":
    test_catalog_and_site_placement()
    print("ok: runtime catalog inspection and site placement")
