#!/usr/bin/env python3
"""Verify generated tool-version links are cleared before repository updates."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
VARS_REPO_TASKS = ROOT / "tasks/compfuzor/vars_repo.tasks"


def run_playbook(playbook: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
    return subprocess.run(
        [
            "ansible-playbook",
            "-i",
            "localhost,",
            "-c",
            "local",
            str(playbook),
        ],
        cwd=ROOT,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )


def init_repo(path: Path) -> None:
    subprocess.run(["git", "init", "-q", str(path)], check=True)


def test_generated_links_are_removed_without_touching_repo_owned_paths() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-tool-version-link-") as tmp:
        temporary = Path(tmp)
        generated = temporary / "generated/etc"
        generated.mkdir(parents=True)
        (generated / ".tool-versions").write_text("nodejs 25\n", encoding="utf-8")
        (generated / "mise.toml").write_text(
            '[tools]\nnodejs = "25"\n', encoding="utf-8"
        )

        managed = temporary / "managed"
        init_repo(managed)
        (managed / ".tool-versions").symlink_to(generated / ".tool-versions")
        (managed / "mise.toml").symlink_to(generated / "mise.toml")
        # Reproduce the index state after a colocated Jujutsu repo snapshots them.
        subprocess.run(
            [
                "git",
                "-C",
                str(managed),
                "add",
                "--intent-to-add",
                "--",
                ".tool-versions",
            ],
            check=True,
        )

        owned = temporary / "owned"
        init_repo(owned)
        (owned / ".tool-versions").write_text("python 3.14\n", encoding="utf-8")
        unrelated_target = temporary / "unrelated-mise.toml"
        unrelated_target.write_text('[tools]\npython = "3.14"\n', encoding="utf-8")
        (owned / "mise.toml").symlink_to(unrelated_target)

        playbook = temporary / "cleanup.pb"
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars:
    DIR: {str(temporary / 'generated')!r}
    REPO_DIR: {str(managed)!r}
    ENV: {{}}
    GIT_BYPASS: false
    REPO_BYPASS: false
  tasks:
    - import_tasks: {str(VARS_REPO_TASKS)!r}
    - name: Point cleanup at the repository-owned fixtures
      ansible.builtin.set_fact:
        REPO_DIR: {str(owned)!r}
    - import_tasks: {str(VARS_REPO_TASKS)!r}
""",
            encoding="utf-8",
        )

        result = run_playbook(playbook)
        if result.returncode:
            raise AssertionError(
                f"ansible-playbook failed ({result.returncode})\n"
                f"{result.stdout}\n{result.stderr}"
            )

        for name in (".tool-versions", "mise.toml"):
            if (managed / name).is_symlink():
                raise AssertionError(f"managed link was not removed: {managed / name}")
        managed_status = subprocess.run(
            [
                "git",
                "-C",
                str(managed),
                "status",
                "--porcelain",
                "--",
                ".tool-versions",
                "mise.toml",
            ],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        if managed_status:
            raise AssertionError(f"managed paths remain dirty:\n{managed_status}")

        if (owned / ".tool-versions").read_text(encoding="utf-8") != "python 3.14\n":
            raise AssertionError("repository-owned .tool-versions was modified")
        if (owned / "mise.toml").readlink() != unrelated_target:
            raise AssertionError("unrelated mise.toml symlink was modified")


if __name__ == "__main__":
    test_generated_links_are_removed_without_touching_repo_owned_paths()
    print("ok: generated tool-version links are cleared safely before git update")
