#!/usr/bin/env python3
"""Version-manager generator only synthesizes an ordered build bin."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "build-mise" / "emit"
GEN_TASKS = ROOT / "tasks" / "compfuzor" / "gen_tool_versions.tasks"


def run_gen(tmp: Path, extra_vars: dict) -> dict:
    deploy = tmp / "deploy"
    deploy.mkdir()
    repo = tmp / "repo"
    repo.mkdir()
    out = tmp / "out.json"
    playbook = tmp / "emit.pb"
    vars_lines = "\n    ".join(f"{key}: {json.dumps(value)}" for key, value in extra_vars.items())
    playbook.write_text(
        f"""---
- hosts: all
  gather_facts: false
  vars:
    DIR: {str(deploy)!r}
    REPO_DIR: {str(repo)!r}
    ETC_FILES: []
    LINKS: []
    BINS: [{{name: build-nodejs.sh, generated: 'echo node', run: true}}]
    {vars_lines}
  tasks:
    - import_tasks: {str(GEN_TASKS)!r}
    - ansible.builtin.copy:
        dest: {str(out)!r}
        content: "{{{{ {{'etc': ETC_FILES, 'links': LINKS, 'bins': BINS, 'composers': BINS | bin_composers}} | to_nice_json }}}}"
""",
        encoding="utf-8",
    )
    env = os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
        cwd=ROOT, env=env, check=False, capture_output=True, text=True,
    )
    if result.returncode:
        raise AssertionError(f"ansible-playbook failed:\n{result.stdout}\n{result.stderr}")
    return json.loads(out.read_text())


def test_tool_versions_emit_build_step_only() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        for name, settings in (
            (".tool-versions", {"TOOL_VERSIONS": {"rust": "1.85"}}),
            ("mise.toml", {"MISE_VERSIONS": {"nodejs": "26"}}),
            ("mise.toml", {"TOOL_VERSIONS": {"rust": "1.85"}, "MISE_VERSIONS": {"nodejs": "26"}}),
        ):
            case = tmp / name.replace(".", "-")
            if case.exists():
                case = tmp / "combined"
            case.mkdir()
            payload = run_gen(case, settings)
            assert payload["etc"] == [] and payload["links"] == []
            assert not (case / "deploy" / name).exists()
            assert payload["bins"][0]["name"] == "build-mise.sh"
            assert "mise install" in payload["bins"][0]["generated"]
            build = next(bin for bin in payload["composers"] if bin["name"] == "build.sh")
            assert build["run_all"] == ["build-mise.sh", "build-nodejs.sh"]


if __name__ == "__main__":
    test_tool_versions_emit_build_step_only()
    print("ok: tool-version pins are build-time only")
