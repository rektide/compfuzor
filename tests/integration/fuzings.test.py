#!/usr/bin/env python3
"""Real declaration synthesis + filesystem writer + read-only source planner."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = Path("/home/rektide/tmp-opencode")


def run(command, env):
    result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)
    if result.returncode:
        raise AssertionError(f"failed {command}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def render(area, name, declarations, env):
    deployment = area / name
    deployment.mkdir(exist_ok=True)
    variables = {
        "TYPE": name, "NAME": name, "DIR": str(deployment), "ETC": str(deployment / "etc"),
        "DIRSET": ["etc"], "FILES": [], "ETC_FILES": [], "ETC_DIRS": [],
        "BINS": [], "DIRS": [], "ENV": {}, "STATUSES": [], "PKGS": [],
        "BINS_RUN_BYPASS": True, "PKGS_BYPASS": True, "APT_BYPASS": True,
        "REPO_BYPASS": True, "GIT_BYPASS": True, "GLOBAL_BINS_BYPASS": True,
        "SYSTEMD_THUNK_BYPASS": True, "SYSTEMD_INSTALL_BYPASS": True,
        **declarations,
    }
    playbook = area / f"{name}.pb"
    playbook.write_text(json.dumps([{
        "hosts": "all", "gather_facts": False,
        "vars_files": [str(ROOT / "vars/common.yaml")], "vars": variables,
        "tasks": [
            {"import_tasks": str(ROOT / "tasks/compfuzor/gen_fuzings.tasks")},
            {"import_tasks": str(ROOT / "tasks/compfuzor/compile_artifacts.tasks")},
            {"import_tasks": str(ROOT / "tasks/compfuzor/fs_hierarchy.tasks"), "vars": {"include": "etc"}},
        ],
    }]))
    run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook),
         "-e", json.dumps({"TYPE": name, "NAME": name})], env)
    return deployment


def test_render_and_plan():
    with tempfile.TemporaryDirectory(prefix="fuzings-render-", dir=SCRATCH) as temporary:
        area = Path(temporary)
        env = {**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"), "TMPDIR": str(area),
               "HOME": str(area / "home"), "XDG_CONFIG_HOME": str(area / "config"),
               "XDG_DATA_HOME": str(area / "data"), "XDG_STATE_HOME": str(area / "state")}
        owner = render(area, "owner", {"FUZE": {
            "id": "opencode", "scope": "user", "actions": {
                "refresh": {"kind": "zim-import"}, "restart": {"kind": "exec"},
            }}}, env)
        declarations = {"TARGET_DIR": str(owner), "TEST_ORDER": 42, "FUZINGS": [{
            "id": "proxy", "target": {"dir": "{{TARGET_DIR}}", "fuze": "opencode", "scope": "user"},
            "actions": {"refresh": {"kind": "zim-import", "order": "{{TEST_ORDER}}"},
                        "restart": {"kind": "exec", "order": 70, "path": "bin/restart.sh", "args": ["literal ${PORT}"]}},
        }]}
        producer = render(area, "proxy", declarations, env)
        source = producer / "etc/fuzings/proxy.json"
        descriptor = json.loads(source.read_text())
        assert descriptor["target"]["dir"] == str(owner)
        assert descriptor["actions"]["refresh"]["order"] == 42
        assert list((owner / "etc/fuze.d").iterdir()) == [], "render must not enroll"
        assert not (area / "config").exists() and not (area / "data").exists()

        # Installation is the next slice: this fixture explicitly supplies native membership.
        link = owner / "etc/fuze.d/proxy.json"
        link.symlink_to(source)
        cli = ["node", "files/fuzings/inspect.ts", "--deployment", str(owner)]
        planned = json.loads(run([*cli, "refresh"], env))
        assert [step["member"] for step in planned["invocations"]] == ["proxy"]
        assert planned["invocations"][0]["contribution"] == {"kind": "zim-import", "order": 42}
        assert json.loads(run([*cli, "restart"], env))["invocations"][0]["contribution"]["args"] == ["literal ${PORT}"]
        link.rename(str(link) + ".disabled")
        render(area, "proxy", declarations, env)
        assert json.loads(source.read_text()) == descriptor
        assert json.loads(run([*cli, "refresh"], env))["invocations"] == []
        render(area, "proxy", {"FUZINGS": []}, env)
        assert json.loads((producer / "etc/fuzings.json").read_text())["sources"] == []
        assert source.exists(), "withdrawal must not prune historical owned artifacts"
        assert Path(str(link) + ".disabled").is_symlink(), "render must retain membership controls"
        print("ok: fuzing render/interpolation, no enrollment, plan separation, repeatability and no pruning")


if __name__ == "__main__":
    test_render_and_plan()
