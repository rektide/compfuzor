#!/usr/bin/env python3
"""Isolated Ansible generation + built-runtime execution; no live deployments."""
from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile

import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent/action-audiences"


def render(payload: Path, bins: list, policy: dict) -> None:
    payload.mkdir(parents=True, exist_ok=True)
    playbook = payload.parent / (payload.name + ".render.pb")
    playbook.write_text(yaml.safe_dump([{
        "hosts": "all", "gather_facts": False,
        "vars": {"TYPE": "audience-fixture", "DIR": str(payload), "BINS_DIR": str(payload / "bin"), "BINS": bins, "ACTION_AUDIENCES": policy},
        "tasks": [
            {"import_tasks": str(ROOT / "tasks/compfuzor/gen_bins.tasks")},
            {"file": {"path": "{{ item }}", "state": "directory"}, "loop": [str(payload / "bin"), str(payload / "etc/compfuzor-actions")]},
            {"template": {"src": "{{ '" + str(ROOT / "files/_bin.node") + "' if item.runtime | default('shell') == 'node' else '" + str(ROOT / "files/_bin") + "' }}", "dest": str(payload / "bin") + "/{{ item.dest | default(item.name) }}", "mode": "0755"}, "loop": "{{ BINS }}", "when": "item.content is defined or item.generated is defined or item.exec is defined or item.run_all is defined"},
            {"copy": {"src": "{{ item.src }}", "dest": str(payload / "bin") + "/{{ item.name }}", "mode": "0755"}, "loop": "{{ BINS }}", "when": "item.raw | default(false)"},
            {"import_tasks": str(ROOT / "tasks/compfuzor/bins_link.tasks")},
            {"copy": {"dest": str(payload / "etc/compfuzor-actions/spec.json"), "content": "{{ _ACTION_AUDIENCES.spec | to_nice_json }}"}},
        ],
    }], sort_keys=False))
    result = subprocess.run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)], cwd=ROOT, env={**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}, text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr


def run(path: Path, env: dict, args: list | None = None, expected: int = 0):
    result = subprocess.run([str(path), *(args or [])], cwd=SCRATCH, env=env, text=True, capture_output=True)
    assert result.returncode == expected, f"{path}: {result.returncode}\n{result.stdout}\n{result.stderr}"
    return result


def lines(path: Path) -> list[str]:
    return path.read_text().splitlines() if path.exists() else []


def test_generation_and_execution(temporary: Path) -> None:
    payload = temporary / "payload"
    trace = temporary / "trace"
    # Authored user/system bodies are deliberately different. User body exports
    # state to children; dirname($0) must stay bin/. Existing _bin places late
    # inside a guarded body BEFORE composed children, and that is retained.
    bins = [
        {"name": "install.sh", "content": "echo system-body >> \"$TRACE\""},
        {"name": "install-user.sh", "bypass": "OWN", "content": 'export BODY_STATE=kept\nprintf "body:%s\\n" "$(dirname "$0")" >> "$TRACE"', "late": 'echo late >> "$TRACE"'},
        {"name": "install-late-user.sh", "phase": "records", "content": 'echo records >> "$TRACE"'},
        {"name": "install-service-user.sh", "phase": "units", "subsystem": "systemd", "content": 'echo user-manager >> "$TRACE"'},
        {"name": "install-service.sh", "phase": "units", "subsystem": "systemd", "content": 'echo system-manager >> "$TRACE"'},
        {"name": "install-package.sh", "phase": "packages", "content": 'echo packages >> "$TRACE"'},
        {"name": "install-main-user.sh", "content": 'printf "main:%s:%s:%s:%s:%s\\n" "$PWD" "$DIR" "$COMPFUZOR_ACTION_AUDIENCE" "${BODY_STATE:-unset}" "${1:-missing}" >> "$TRACE"'},
        {"name": "assemble-receiver-user.sh", "content": 'echo assembled-user >> "$TRACE"'},
        {"name": "assemble-receiver.sh", "content": 'echo assembled-system >> "$TRACE"'},
        {"name": "build-tool.sh", "content": 'echo built-system >> "$TRACE"'},
        {"name": "echo-target.sh", "content": 'printf "alias:%s\\n" "$(basename "$0")" >> "$TRACE"'},
        {"name": "install-lexical-user.sh", "dest": "install-lexical-user.sh", "link": "echo-target.sh", "scope": "user"},
    ]
    render(payload, bins, {})
    output = payload / "bin"
    spec = json.loads((payload / "etc/compfuzor-actions/spec.json").read_text())
    assert spec["actions"]["install"]["entry"] == "install-user.mjs"
    assert not (output / "install-user.mjs").is_symlink()
    assert (output / "install.mjs").readlink().name == "install-user.mjs"
    assert (output / "install-system.mjs").readlink().name == "install-user.mjs"
    assert not (output / "build.mjs").exists() and (output / "build-system.mjs").exists()
    assert "actionEntry" in (output / "install-user.mjs").read_text()
    assert len((output / "install-user.mjs").read_text()) < 220
    assert sum(path.name == "compfuzor-runtime.mjs" for path in output.iterdir()) == 1

    env = {**os.environ, "TRACE": str(trace), "DIR": str(temporary / "foreign"), "COMPFUZOR_ENV_BYPASS": "1"}
    run(output / "install.mjs", env, ["argument with spaces"])
    assert lines(trace) == [f"body:{output}", "late", f"main:{payload}:{payload}:user:kept:argument with spaces", "alias:install-lexical-user.sh", "user-manager", "records"], lines(trace)
    trace.unlink()
    run(output / "install-system.mjs", env)
    assert lines(trace) == ["system-body", "packages", "system-manager"]
    trace.unlink()
    run(output / "assemble.mjs", env)
    run(output / "assemble-system.mjs", env)
    assert lines(trace) == ["assembled-user", "assembled-system"]
    trace.unlink()
    run(output / "install.mjs", {**env, "COMPFUZOR_OWN_BYPASS": "1"}, ["x"])
    assert lines(trace) == [f"main:{payload}:{payload}:user:unset:x", "alias:install-lexical-user.sh", "user-manager", "records"], lines(trace)
    trace.unlink()
    assert "Audience: user" in run(output / "install.mjs", env, ["--help"]).stdout
    assert not trace.exists()

    # External same-name aliases retain identity but root in the real deployment.
    external = temporary / "aliases"
    external.mkdir()
    alias = external / "assemble-system.mjs"
    alias.symlink_to(output / "assemble.mjs")
    run(alias, env)
    assert lines(trace) == ["assembled-system"]
    trace.unlink()
    typo = external / "assemble-custom.mjs"
    typo.symlink_to(output / "assemble.mjs")
    assert "unknown or unavailable action alias" in run(typo, env, expected=2).stderr
    assert not trace.exists()

    # Switching default updates the declared representations, without pruning.
    render(payload, bins, {"default": "system", "actions": {"build": {"default": "system"}}})
    assert not (output / "install-system.mjs").is_symlink()
    assert (output / "install-user.mjs").is_symlink()
    run(output / "install.mjs", env)
    assert lines(trace) == ["system-body", "packages", "system-manager"]
    trace.unlink()
    run(output / "build.mjs", env)
    assert lines(trace) == ["built-system"]
    trace.unlink()

    # Restricting availability leaves stale files in place, but current spec wins.
    render(payload, bins, {"actions": {"install": {"available": ["user"]}}})
    stale = run(output / "install-system.mjs", env, expected=2)
    assert "unavailable" in stale.stderr, stale.stderr
    assert not trace.exists()
    render(payload, bins, {"actions": {"install": False}})
    assert "stale action entry" in run(output / "install.mjs", env, expected=2).stderr
    assert "stale authored action body" in run(output / "install-user.sh", env, expected=2).stderr
    assert not trace.exists()
    print("ok: generated real/alias families, both defaults, body semantics, lexical identity and omission")


def test_failures_and_signals(temporary: Path) -> None:
    payload = temporary / "failures"
    trace = temporary / "failure-trace"
    bins = [
        {"name": "install-fail-user.sh", "content": "exit 7"},
        {"name": "install-never-user.sh", "content": 'echo never >> "$TRACE"'},
    ]
    render(payload, bins, {})
    env = {**os.environ, "TRACE": str(trace)}
    run(payload / "bin/install.mjs", env, expected=7)
    assert not trace.exists()

    outside = temporary / "outside.sh"
    outside.write_text("#!/bin/sh\necho outside\n")
    outside.chmod(0o755)
    bins[0] = {"name": "install-start-user.sh", "content": 'echo early >> "$TRACE"'}
    bins[1] = {"name": "install-escape-user.sh", "dest": "install-escape-user.sh", "link": str(outside), "scope": "user"}
    render(payload, bins, {})
    assert "escapes deployment" in run(payload / "bin/install.mjs", env, expected=2).stderr
    assert not trace.exists()  # Whole selected graph was checked before the first effect.

    render(payload, [{"name": "install-user.sh", "run_all": ["install-user.sh"], "content": 'echo cycle >> "$TRACE"'}], {})
    assert "cyclic action plan" in run(payload / "bin/install.mjs", env, expected=2).stderr
    assert "cyclic action plan" in run(payload / "bin/install-user.sh", env, expected=2).stderr
    assert not trace.exists()

    signal_mark = temporary / "signal-mark"
    bins = [
        {"name": "install-wait-user.sh", "content": 'trap \'echo received > "$SIGNAL_MARK"; exit 0\' TERM\nsleep 60 &\nworker=$!\necho ready\nwait "$worker"'},
        {"name": "install-never-user.sh", "content": 'echo never >> "$TRACE"'},
    ]
    render(payload, bins, {})
    process = subprocess.Popen([str(payload / "bin/install.mjs")], cwd=SCRATCH, env={**env, "SIGNAL_MARK": str(signal_mark)}, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        assert process.stdout.readline().strip() == "ready"
        process.send_signal(signal.SIGTERM)
        process.communicate(timeout=15)
        assert process.returncode == -signal.SIGTERM
        assert signal_mark.read_text().strip() == "received" and not trace.exists()
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate()
    bins[0] = {"name": "install-wait-user.sh", "content": "kill -TERM $$"}
    render(payload, bins, {})
    run(payload / "bin/install.mjs", env, expected=-signal.SIGTERM)
    assert not trace.exists()
    print("ok: fail-fast exact exit status, whole-graph containment and signal propagation")


def test_real_mixed_scope_render(temporary: Path) -> None:
    """Render the real SteamOS declaration in isolation; never execute its actions."""
    payload = temporary / "steamos-render"
    scenario = temporary / "steamos-scenario.json"
    scenario.write_text(json.dumps({
        "DIR": str(payload), "ETC": str(payload / "etc"), "BINS_DIR": str(payload / "bin"),
        "ACTION_AUDIENCES": {}, "REPO_BYPASS": True, "PKGS_BYPASS": True,
        "APT_BYPASS": True, "ARCH_BYPASS": True, "MODULES_BYPASS": True,
        "SYSTEMD_THUNK_BYPASS": True, "BINS_RUN_BYPASS": True,
        "GLOBAL_BINS_BYPASS": True, "LINKS_BYPASS": True, "GET_URLS": [],
    }))
    result = subprocess.run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(ROOT / "steamos-niri.opt.pb"), "-e", "@" + str(scenario)], cwd=ROOT, env={**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}, text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    spec = json.loads((payload / "etc/compfuzor-actions/spec.json").read_text())
    install = spec["actions"]["install"]
    assert install["entry"] == "install-user.mjs" and set(install["plans"]) == {"user", "system"}
    user, system = install["plans"]["user"][0], install["plans"]["system"][0]
    assert user["path"] == "bin/install-user.sh" and system["path"] == "bin/install.sh"
    assert any(step.get("path") == "bin/install-keybindings-niri.sh" for step in user["children"]), user
    assert any(step.get("action") == "install-archlane" or step.get("path") == "bin/install-arch.sh" for step in system["children"]), system
    assert "sudo steamos-readonly disable" in (payload / "bin/install.sh").read_text()
    assert 'NIRI_CONFIG="$NIRI_DIR/config.kdl"' in (payload / "bin/install-user.sh").read_text()
    catalog = json.loads((payload / "etc/compfuzor-runtime/catalog.json").read_text())
    assert catalog["execution"] == {"authority": "action-audiences", "catalogOnly": True}
    print("ok: real mixed-scope SteamOS playbook isolated render preserves provisioning and adoption plans")


if __name__ == "__main__":
    SCRATCH.mkdir(parents=True, exist_ok=True)
    if not (SCRATCH / "README.md").exists():
        (SCRATCH / "README.md").write_text("# Action audience scratch\nIsolated Ansible fixtures, JavaScript aliases and signal tests; no live receiver/service operations.\n")
    with tempfile.TemporaryDirectory(prefix="integration-", dir=SCRATCH) as tmp:
        test_generation_and_execution(Path(tmp))
        test_failures_and_signals(Path(tmp))
        test_real_mixed_scope_render(Path(tmp))
