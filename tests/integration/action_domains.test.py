#!/usr/bin/env python3
"""Compiled typed CONFIG/keybinding aggregates, isolated receivers and invocation transport."""
from __future__ import annotations
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent/action-domains"


def render(area: Path, declarations: dict) -> Path:
    area.mkdir(parents=True, exist_ok=True)
    (area / "files").symlink_to(ROOT / "files", target_is_directory=True)
    payload = area / "deployment"
    variables = {"TYPE": "action-domain-fixture", "NAME": "action-domain-fixture", "DIR": str(payload), "ETC": str(payload / "etc"), "BINS_DIR": str(payload / "bin"), "DIRSET": ["etc"], "FILES": [], "ETC_FILES": [], "BINS": [], "DIRS": [], "STATUSES": [], "PKGS": [], "ENV": {}, "BINS_RUN_BYPASS": True, "ACTION_AUDIENCES": {}, **declarations}
    tasks = [{"set_fact": {"SUBSYSTEM": {}}}]
    tasks.extend({"import_tasks": str(ROOT / f"tasks/compfuzor/{name}.tasks")} for name in ["sub_attribution", "sub_config", "gen_keybindings", "gen_config", "gen_bins", "gen_attribution", "gen_runtime_catalog", "compile_artifacts"])
    tasks += [
        {"file": {"path": str(payload), "state": "directory"}},
        {"import_tasks": str(ROOT / "tasks/compfuzor/fs_hierarchy.tasks"), "vars": {"include": "etc"}},
        {"file": {"path": "{{item}}", "state": "directory"}, "loop": "{{DIRS}}"},
        {"import_tasks": str(ROOT / "tasks/compfuzor/bins.tasks")},
        {"import_tasks": str(ROOT / "tasks/compfuzor/bins_link.tasks")},
    ]
    playbook = area / "render.pb"
    playbook.write_text(yaml.safe_dump([{"hosts": "all", "gather_facts": False, "vars_files": [str(ROOT / "vars/common.yaml")], "vars": variables, "tasks": tasks}], sort_keys=False))
    result = subprocess.run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook), "-e", json.dumps({"TYPE": variables["TYPE"], "NAME": variables["NAME"], "CONFIG_CONTEXT": variables.get("CONFIG_CONTEXT", "user")})], cwd=ROOT, env={**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}, text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    return payload


def invoke(path: Path, env: dict, args=(), expected=0):
    result = subprocess.run([str(path), *args], cwd=SCRATCH, env=env, text=True, capture_output=True)
    assert result.returncode == expected, f"{path}: {result.returncode}\n{result.stdout}\n{result.stderr}"
    return result


def session_dirs() -> set[Path]:
    return set(SCRATCH.glob("compfuzor-actions-*"))


def build_fixture(area: Path):
    fake = area / "validators"
    fake.mkdir(parents=True)
    for name in ["niri", "umbriel"]:
        executable = fake / name
        executable.write_text('#!/bin/sh\n[ -z "${COMPFUZOR_ACTION_SESSION:-}" ] || exit 91\n[ -z "${COMPFUZOR_ACTION_OPERATION:-}" ] || exit 92\nprintf "%s:%s\\n" "$(basename "$0")" "${BODY_EXPORT:-missing}" >> "$VALIDATOR_TRACE"\n')
        executable.chmod(0o755)
    user = area / "user"
    system = area / "system"
    wrong = area / "wrong"
    contexts = lambda subpath: {"desktop": {"scope": "user", "root": "config", "subpath": subpath}, "host": {"scope": "system", "root": str(system / subpath)}}
    body = '''
printf '%s-body\n' "$COMPFUZOR_ACTION_AUDIENCE" >> "$TRACE"
export BODY_EXPORT=from-body
mkdir -p "$RECEIVER/niri" "$RECEIVER/umbriel"
if [ ! -e "$RECEIVER/niri/config.kdl" ]; then printf '// compfuzor-keybindings-begin\n// compfuzor-keybindings-end\n' > "$RECEIVER/niri/config.kdl"; fi
if [ ! -e "$RECEIVER/umbriel/config.toml" ]; then printf '[include]\nfiles = [\n# compfuzor-keybindings-begin\n# compfuzor-keybindings-end\n]\n' > "$RECEIVER/umbriel/config.toml"; fi
printf 'created-before-domain\n' > "$DIR/etc/input.txt"
export HOME="$WRONG/home"
export XDG_CONFIG_HOME="$WRONG/config"
export NIRI_PLACEMENT_ROOT="$WRONG/niri-placement"
export NIRI_PLACEMENT_FILE="$WRONG/niri-placement/launch.binding.kdl"
export COMPFUZOR_CONFIG_INSTALL_STRATEGY=link
export COMPFUZOR_CONFIG_DROPINS_STRATEGY=link
'''
    declarations = {
        "CONFIG_CONTEXT": "desktop", "CONFIG_CONTEXTS": contexts("cfg"),
        "CONFIGS": {"result.conf": {"processor": "concat", "inputs": [{"file": "input.txt"}]}},
        "KEYBINDING_CONTEXT": "desktop",
        "KEYBINDING_CONSUMERS": {target: {"contexts": contexts(target), "baseline": [], **({"placement_directory": {"env": "NIRI_PLACEMENT_ROOT"}, "bindings": {"launch": {"placement": {"strategy": "link", "path": {"env": "NIRI_PLACEMENT_FILE"}}}}} if target == "niri" else {})} for target in ["niri", "umbriel"]},
        "KEYBINDING_ACTIONS": {"launch": {"exec": ["echo", "typed-action"]}},
        "KEYBINDINGS": {"launch": {"action": "launch", "keys": ["Mod+D"], "umbriel": {"keys": ["Mod+Space"]}}},
        "BINS": [
            {"name": "install-user.sh", "bypass": "BODY", "content": body},
            {"name": "install.sh", "content": body},
            {"name": "assemble-user.sh", "content": 'printf "assemble-body\\n" >> "$TRACE"\nexport BODY_EXPORT=assembled-body\nexport XDG_CONFIG_HOME="$WRONG/config"\nexport NIRI_PLACEMENT_ROOT="$WRONG/niri-placement"'},
            {"name": "assemble.sh", "content": 'printf "assemble-system-body\\n" >> "$TRACE"\nexport BODY_EXPORT=assembled-body'},
            {"name": "install-observe-user.sh", "phase": "records", "content": 'printf "ordinary:%s:%s\\n" "$BODY_EXPORT" "${COMPFUZOR_ACTION_SESSION:-none}" >> "$TRACE"'},
        ],
    }
    payload = render(area / "render", declarations)
    (payload / "env.export").write_text('printf "env-source\\n" >> "$ENV_TRACE"\nexport SETUP_PRESENT=verified\n')
    node = subprocess.run(["node", "-p", "process.execPath"], check=True, text=True, capture_output=True).stdout.strip()
    env = {**os.environ, "HOME": str(area / "home"), "XDG_CONFIG_HOME": str(user), "RECEIVER": str(user), "NIRI_PLACEMENT_ROOT": str(user / "niri-placement"), "NIRI_PLACEMENT_FILE": str(user / "niri-placement/launch.binding.kdl"), "WRONG": str(wrong), "TRACE": str(area / "trace"), "ENV_TRACE": str(area / "env-trace"), "VALIDATOR_TRACE": str(area / "validator-trace"), "TMPDIR": str(SCRATCH), "PATH": os.pathsep.join([str(fake), str(Path(node).parent), "/usr/bin", "/bin", "/usr/local/bin"])}
    for name in ["DIR", "COMPFUZOR_CONFIG_CONTEXT", "COMPFUZOR_CONTEXT", "COMPFUZOR_CONFIG_INSTALL_STRATEGY", "COMPFUZOR_CONFIG_DROPINS_STRATEGY", "COMPFUZOR_CONFIG_BYPASS", "COMPFUZOR_KEYBINDINGS_BYPASS", "COMPFUZOR_ACTION_SESSION", "COMPFUZOR_ACTION_OPERATION", "COMPFUZOR_ACTION_OPERATION_MODE"]:
        env.pop(name, None)
    return payload, env, user, system, wrong


def test_compiled_domains(area: Path):
    payload, env, user, system, wrong = build_fixture(area)
    spec = json.loads((payload / "etc/compfuzor-actions/spec.json").read_text())
    assert set(spec["actions"]["install"]["plans"]) == {"user", "system"}
    assert spec["actions"]["assemble-config"]["plans"]["user"][0]["kind"] == "domain"
    assert spec["actions"]["assemble-keybindings-niri"]["plans"]["system"][0]["context"] == "host"
    before = session_dirs()
    invoke(payload / "bin/install.mjs", env)
    assert session_dirs() == before
    assert (user / "cfg/result.conf").read_text() == "created-before-domain\n"
    assert not (user / "cfg/result.conf").is_symlink()  # late strategy=link did not redirect installation
    assert (user / "niri/config.kdl").exists() and (user / "umbriel/config.toml").exists()
    assert (user / "niri-placement/launch.binding.kdl").is_symlink(), [str(path.relative_to(user)) for path in user.rglob("*")]
    assert not wrong.exists()
    trace = Path(env["TRACE"]).read_text().splitlines()
    assert trace == ["user-body", "ordinary:from-body:none"], trace
    assert "niri:from-body" in Path(env["VALIDATOR_TRACE"]).read_text()
    assert "umbriel:from-body" in Path(env["VALIDATOR_TRACE"]).read_text()
    sysenv = {**env, "RECEIVER": str(system), "NIRI_PLACEMENT_ROOT": str(system / "niri-placement"), "NIRI_PLACEMENT_FILE": str(system / "niri-placement/launch.binding.kdl")}
    invoke(payload / "bin/install-system.mjs", sysenv)
    assert (system / "cfg/result.conf").read_text() == "created-before-domain\n"
    assert (system / "niri/config.kdl").exists() and (system / "umbriel/config.toml").exists()
    invoke(payload / "bin/assemble.mjs", env)
    invoke(payload / "bin/assemble-system.mjs", sysenv)
    assert session_dirs() == before and not wrong.exists()
    assert Path(env["TRACE"]).read_text().splitlines().count("assemble-body") == 1
    # Apply bypass remains live: bindings still admit, but actual wrapper skips its domain effects.
    old = (user / "niri/config.kdl").read_bytes()
    invoke(payload / "bin/install-keybindings-niri.mjs", {**env, "COMPFUZOR_KEYBINDINGS_BYPASS": "1"})
    assert (user / "niri/config.kdl").read_bytes() == old and session_dirs() == before
    return payload, env, before


def test_early_errors(payload: Path, env: dict, before: set[Path]):
    trace = Path(env["TRACE"])
    initial = trace.read_bytes()
    rejected = invoke(payload / "bin/install.mjs", env, ["--context", "host"], expected=2)
    assert "scope" in rejected.stderr and trace.read_bytes() == initial and session_dirs() == before
    profile = payload / "etc/keybinding-umbriel.json"
    original = profile.read_bytes()
    invalid = json.loads(original)
    invalid["contexts"]["desktop"]["scope"] = "system"
    profile.write_text(json.dumps(invalid))
    invoke(payload / "bin/install.mjs", {**env, "COMPFUZOR_KEYBINDINGS_BYPASS": "1"}, expected=2)
    assert trace.read_bytes() == initial and session_dirs() == before
    profile.write_bytes(original)
    invoke(payload / "bin/inputs.mjs", env, ["put", "result.conf/0"], expected=2)
    invoke(payload / "bin/inputs.mjs", env, ["remove", "result.conf/0", "extra"], expected=2)
    assert trace.read_bytes() == initial and session_dirs() == before
    invoke(payload / "bin/install.mjs", {**env, "COMPFUZOR_ACTION_SESSION": str(SCRATCH / "nonexistent/session.json")}, expected=2)
    assert trace.read_bytes() == initial and session_dirs() == before


if __name__ == "__main__":
    SCRATCH.mkdir(parents=True, exist_ok=True)
    if not (SCRATCH / "README.md").exists():
        (SCRATCH / "README.md").write_text("# Typed action domain scratch\nIsolated generated aggregates, named receivers, fake native validators and private invocation transport. No live configuration/services.\n")
    with tempfile.TemporaryDirectory(prefix="typed-", dir=SCRATCH) as tmp:
        payload, env, before = test_compiled_domains(Path(tmp))
        test_early_errors(payload, env, before)
        print("ok: typed CONFIG/keybinding aggregate, named audiences, frozen receivers, exports, bypass and early failure cleanup")
