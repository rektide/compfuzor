#!/usr/bin/env python3

"""Verify version-manager artifact emission: real file in DIR, repo link only."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
GEN_TASKS = ROOT / "tasks" / "compfuzor" / "gen_tool_versions.tasks"


def check(label: str, actual: object, expected: object) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"ok: {label}")


def run_gen(tmp: Path, extra_vars: dict) -> tuple[dict, dict]:
    """Run gen_tool_versions.tasks; return (etc_files, links) it produced."""
    deploy = tmp / "deploy"
    (deploy / "etc").mkdir(parents=True, exist_ok=True)
    repo = tmp / "repo"
    repo.mkdir(exist_ok=True)
    out = tmp / "out.json"
    playbook = tmp / "emit.pb"
    playbook.write_text(
        f"""---
- hosts: all
  gather_facts: false
  vars:
    DIR: {str(deploy)!r}
    REPO_DIR: {str(repo)!r}
    ETC_FILES: []
    LINKS: []
    BINS: []
    {extra_vars_text(extra_vars)}
  tasks:
    - import_tasks: {str(GEN_TASKS)!r}
    - ansible.builtin.copy:
        dest: {str(out)!r}
        content: "{{{{ {{'etc': ETC_FILES, 'links': LINKS}} | to_nice_json }}}}"
""",
        encoding="utf-8",
    )
    env = os.environ.copy()
    env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
        cwd=ROOT,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise AssertionError(f"ansible-playbook failed:\n{result.stdout}\n{result.stderr}")
    payload = json.loads(out.read_text(encoding="utf-8"))
    return payload["etc"], payload["links"]


def extra_vars_text(extra_vars: dict) -> str:
    return "\n    ".join(f"{key}: {json.dumps(value)}" for key, value in extra_vars.items())


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-tv-emit-") as tmp:
        root = Path(tmp)
        deploy = root / "deploy"
        repo = root / "repo"

        etc, links = run_gen(root, {"TOOL_VERSIONS": {"rust": "1.85"}})
        check(
            "tool-versions file is a DIR-rooted ETC_FILES entry",
            etc,
            [{"name": ".tool-versions", "dest": str(deploy / ".tool-versions"), "content": "rust 1.85\n"}],
        )
        check(
            "only the repo link is emitted, pointing at DIR's file",
            links,
            [{"src": str(deploy / ".tool-versions"), "dest": str(repo / ".tool-versions")}],
        )

        etc, links = run_gen(root, {"MISE_VERSIONS": {"nodejs": "26"}})
        check(
            "mise.toml file is a DIR-rooted ETC_FILES entry",
            etc[0]["dest"],
            str(deploy / "mise.toml"),
        )
        check(
            "mise repo link points at DIR's file",
            links[0]["src"],
            str(deploy / "mise.toml"),
        )

        _, links = run_gen(
            root, {"TOOL_VERSIONS": {"rust": "1.85"}, "TOOL_VERSIONS_LINK_BYPASS": True}
        )
        check("TOOL_VERSIONS_LINK_BYPASS emits no links", links, [])

        _, links = run_gen(root, {"TOOL_VERSIONS": {"rust": "1.85"}, "REPO_DIR": str(root / "absent")})
        check("missing repo dir emits no links", links, [])

    print("all tool-version emission checks passed")


if __name__ == "__main__":
    main()
