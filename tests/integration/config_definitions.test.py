#!/usr/bin/env python3
"""Isolated Ansible packaging and real shared-worker multi-CONFIG/ENV proofs."""

from __future__ import annotations

import json
import os
import shlex
from pathlib import Path
import subprocess
import tempfile

import yaml


ROOT = Path(__file__).resolve().parents[2]


def run(args, cwd, *, check=True, env=None):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, text=True, capture_output=True, env=env)
    if check and result.returncode:
        raise AssertionError(f"failed {args} ({result.returncode})\n{result.stdout}\n{result.stderr}")
    return result


def generate(temporary, variables, *, env_config=False, preliminary_tasks=None):
    deployment = temporary / "deployment"
    (temporary / "files").symlink_to(ROOT / "files", target_is_directory=True) if not (temporary / "files").exists() else None
    base = {"TYPE": "fixture", "NAME": "fixture", "DIR": str(deployment), "ETC": str(deployment / "etc"),
            "BINS_DIR": str(deployment / "bin"), "BINS": [], "DIRS": [], "ETC_DIRS": [], "FILES": [],
            "ETC_FILES": [], "STATUSES": [], "PKGS": [], "SUBSYSTEM": {"sentinel": {"keep": True}},
            "INSTANCE": "", "REPO": "", "BUILD_DIR": "", "GLOBAL_BINS_DIR": ""}
    tasks = [{"set_fact": {**base, **variables}}]
    tasks += preliminary_tasks or []
    if env_config:
        if "discovery_enabled" in variables:
            tasks += [{"set_fact": {"ENV_PRIO": "{{ ENV_PRIO | combine({'CONDITIONAL': 'enabled', 'WIN': 'priority'}) }}"}, "when": "discovery_enabled"}]
        tasks += [{"import_tasks": str(ROOT / "tasks/compfuzor/sub_env_config.tasks")}]
    tasks += [{"import_tasks": str(ROOT / "tasks/compfuzor/sub_config.tasks")},
              {"import_tasks": str(ROOT / "tasks/compfuzor/gen_config.tasks")},
              {"import_tasks": str(ROOT / "tasks/compfuzor/gen_bins.tasks")},
              {"file": {"path": "{{ item }}", "state": "directory", "mode": "0700"},
               "loop": "{{ DIRS + [DIR, ETC, BINS_DIR] + (ETC_DIRS | map('regex_replace', '^', ETC + '/') | list) }}"},
              {"file": {"path": "{{ ETC }}/{{ item.name | dirname }}", "state": "directory"}, "loop": "{{ ETC_FILES }}"},
              {"copy": {"dest": "{{ ETC }}/{{ item.name }}", "content": "{{ (item.json | to_nice_json) if item.json is defined else item.content }}", "mode": "0600"}, "loop": "{{ ETC_FILES }}"},
              {"copy": {"dest": "{{ DIR }}/{{ item.name }}", "content": "{{ item.content }}", "mode": "0600"}, "loop": "{{ FILES }}"},
              {"import_tasks": str(ROOT / "tasks/compfuzor/bins.tasks")},
              {"import_tasks": str(ROOT / "tasks/compfuzor/bins_link.tasks")},
              {"copy": {"dest": str(temporary / "plan.json"), "content": "{{ {'subsystem': SUBSYSTEM, 'bins': BINS, 'files': ETC_FILES, 'statuses': STATUSES} | to_nice_json }}"}}]
    playbook = temporary / "generate.pb"
    playbook.write_text(yaml.safe_dump([{"hosts": "all", "gather_facts": False, "vars_files": [str(ROOT / "vars/common.yaml")], "vars": {**base, **variables}, "tasks": tasks}], sort_keys=False))
    environment = os.environ.copy()
    environment["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
    run(["ansible-playbook", "-i", "localhost,", "-c", "local", playbook], ROOT, env=environment)
    return deployment, json.loads((temporary / "plan.json").read_text())


def test_definitions():
    with tempfile.TemporaryDirectory(prefix="multi-config-", dir="/tmp/opencode") as tmp:
        temporary = Path(tmp)
        deployment = temporary / "deployment"
        consumer = temporary / "consumer"
        definitions = {}
        for identity in ("beta", "alpha"):
            definitions[identity] = {
                "etc": str(deployment / "etc" / identity),
                "configs": {"main.conf": {"name": "main", "processor": "concat", "validate": '! grep -q BROKEN "$CONFIG_CANDIDATE"', "inputs": [{"glob": "pieces/*.conf", "name": "fragments", "remote": True}]}},
                "contexts": {"user": {"scope": "user", "root": str(consumer / identity), "dropins": "link" if identity == "alpha" else "copy"}},
            }
        deployment, plan = generate(temporary, {"CONFIG_DEFINITIONS": definitions, "CONFIG_DEFAULT": "beta"})
        subsystem = plan["subsystem"]["config"]
        assert plan["subsystem"]["sentinel"] == {"keep": True}
        assert subsystem["default"] == "beta"
        assert set(subsystem["instances"]) == {"alpha", "beta"}
        assert len([bin for bin in plan["bins"] if bin["name"] == "config/run.sh"]) == 1
        for identity in definitions:
            source = deployment / f"etc/{identity}/pieces/10-local.conf"
            source.write_text(identity + "\n")
            command = deployment / f"bin/config-{identity}-assemble.sh"
            run([command, "--context", "canonical"], deployment)
            assert (deployment / f"etc/{identity}/main.conf").read_text() == identity + "\n"
            run([deployment / "bin/config-install.sh", "--definition", identity], deployment)
            local = consumer / identity / "pieces/10-local.conf"
            assert local.is_symlink() == (identity == "alpha")
            assert (consumer / identity / "main.conf").read_text() == identity + "\n"
            run([deployment / "bin/config-status.sh", "--definition", identity], deployment)
        remote = temporary / "extra.conf"
        remote.write_text("extra\n")
        run([deployment / "bin/config-remote.mjs", "put-matching", remote], deployment)
        for identity in definitions:
            assert (deployment / f"etc/{identity}/main.conf").read_text() == identity + "\nextra\n"
        # A failing target does not stop other admitted matches; its input rolls back.
        beta_spec = deployment / "etc/config/beta/spec.json"
        data = json.loads(beta_spec.read_text())
        data["configs"]["main"]["validate"] = "false"
        beta_spec.write_text(json.dumps(data))
        before = (deployment / "etc/beta/main.conf").read_text()
        remote.write_text("new\n")
        failure = run([deployment / "bin/config-remote.mjs", "put-matching", remote, "other.conf"], deployment, check=False)
        assert failure.returncode == 1 and "beta/fragments" in failure.stderr
        assert not (deployment / "etc/beta/pieces/other.conf").exists()
        assert (deployment / "etc/beta/main.conf").read_text() == before
        assert (deployment / "etc/alpha/pieces/other.conf").is_symlink()
        no_match = run([deployment / "bin/config-remote.mjs", "put-matching", remote, "wrong.json"], deployment, check=False)
        assert no_match.returncode == 1 and "no matching" in no_match.stderr
        selected = run([deployment / "bin/config-remote.mjs", "--definition", "alpha", "disable", "fragments", "extra.conf"], deployment)
        assert (deployment / "etc/alpha/pieces/extra.conf.disabled").is_symlink()
        run([deployment / "bin/config-remote.mjs", "--definition", "alpha", "put", "fragments", remote, "extra.conf"], deployment)
        assert (deployment / "etc/alpha/pieces/extra.conf.disabled").is_symlink()
        # Selected target bindings/specs are held through effects, not reloaded
        # between targets. Simulate another writer replacing beta's spec while
        # alpha's fixture validator is running.
        beta_spec.write_text(json.dumps(subsystem["instances"]["beta"]["spec"]))
        alpha_spec = deployment / "etc/config/alpha/spec.json"
        alpha_data = json.loads(alpha_spec.read_text())
        alpha_data["configs"]["main"]["validate"] = "printf '{' > " + shlex.quote(str(beta_spec))
        alpha_spec.write_text(json.dumps(alpha_data))
        run([deployment / "bin/config-remote.mjs", "put-matching", remote, "frozen.conf"], deployment)
        assert (deployment / "etc/beta/pieces/frozen.conf").is_symlink()
        # Repeat generation in the opposite authored order preserves all bindings.
        _, again = generate(temporary, {"CONFIG_DEFINITIONS": dict(reversed(list(definitions.items()))), "CONFIG_DEFAULT": "beta"})
        assert subsystem == again["subsystem"]["config"]


def test_env():
    with tempfile.TemporaryDirectory(prefix="env-config-", dir="/tmp/opencode") as tmp:
        temporary = Path(tmp)
        variables = {"ENV_CONFIG": {"projections": {"client.zsh": {"files": ["50-client.env"], "format": "env-zsh"}}},
                     "ENV": {"WIN": "ordinary", "EMPTY": "", "ODD": "quote'\" dollar$ slash\\ snow☃", "ARRAY": ["one", "two"], "lookup_value": True},
                     "ENV_LIST": ["lower_name"], "lower_name": "exact", "LOWER_NAME": "fallback",
                     "ENV_PRIO": {"PRIO": "preserved"}, "discovery_enabled": True,
                     "lookup_value": "exact-lookup", "contribution_lookup": "from-contribution",
                     "ENV_CONTRIBUTIONS": {"50-client.env": {"ENDPOINT": "http://example.test:8080", "WIN": "contribution", "contribution_lookup": True}},
                     "BINS": [{"name": "context-probe.sh", "content": 'printf "%s|%s\\n" "$DIR" "$NAME"', "basedir": False, "compose": False, "bypass": False}]}
        deployment, plan = generate(temporary, variables, env_config=True)
        run([deployment / "bin/config-assemble.sh", "--definition", "env"], deployment, env={**os.environ, "DIR": "/foreign"})
        app = (deployment / "env.export").read_text()
        assert "export DIR=" not in app and "export TYPE=" not in app and "export NAME=" not in app
        script = 'source "$1"; python3 -c "import json,os;print(json.dumps(dict(os.environ)))"'
        result = run(["bash", "-c", script, "bash", deployment / "env.export"], deployment)
        effective = json.loads(result.stdout)
        assert effective["WIN"] == "priority" and effective["PRIO"] == "preserved" and effective["CONDITIONAL"] == "enabled"
        assert effective["LOWER_NAME"] == "exact" and effective["ARRAY"] == "one two" and effective["EMPTY"] == ""
        assert effective["ODD"] == variables["ENV"]["ODD"]
        assert effective["LOOKUP_VALUE"] == "exact-lookup" and effective["CONTRIBUTION_LOOKUP"] == "from-contribution"
        assert (deployment / "env").read_text().count("WIN=") == 1
        projection = deployment / "etc/env-projections/client.zsh"
        result = run(["zsh", "-dfc", 'unset ENDPOINT; WIN=""; source "$1"; print -r -- "$ENDPOINT|$WIN"', "zsh", projection], deployment)
        assert result.stdout.strip() == "http://example.test:8080|"
        # Literal data resembling a command is never evaluated while assembling.
        marker = temporary / "executed"
        input_file = deployment / "etc/env.d/60-inert.env"
        input_file.write_text('INERT="$(touch ' + str(marker) + ')"\nDIR="/producer/application"\n')
        run([deployment / "bin/config-assemble.sh", "--definition", "env"], deployment)
        assert not marker.exists()
        result = run([deployment / "bin/context-probe.sh"], deployment, env={**os.environ, "DIR": "/foreign", "NAME": "foreign"})
        assert result.stdout.strip() == f"{deployment}|fixture"
        before = (deployment / "env.export").read_text()
        input_file.write_text('BAD="multi\\nline"\n')
        failed = run([deployment / "bin/config-assemble.sh", "--definition", "env"], deployment, check=False)
        assert failed.returncode and (deployment / "env.export").read_text() == before
        variables["discovery_enabled"] = False
        _, plan = generate(temporary, variables, env_config=True)
        priority = (deployment / "etc/env.d/99-local-priority.env").read_text()
        assert "CONDITIONAL" not in priority and 'PRIO="preserved"' in priority


def test_current_proxy_priority_preservation():
    # Read only the current user's proxy declarations and pre-include conditions.
    # Never import its compfuzor play, fetch/build it, or generate/run service work.
    proxy = yaml.safe_load((ROOT / "opencode-bus-proxy.src.pb").read_text())[0]
    shared = yaml.safe_load((ROOT / "vars/opencode.yaml").read_text())
    for discovery, watcher in ((False, True), (True, False), (True, True)):
        with tempfile.TemporaryDirectory(prefix="proxy-env-preservation-", dir="/tmp/opencode") as tmp:
            temporary = Path(tmp)
            variables = {**shared, **{key: value for key, value in proxy["vars"].items() if key in ("ENV", "ENV_CONTRIBUTIONS", "_bus_proxy_listen", "_bus_proxy_url")},
                         "ENV_CONFIG": True, "ENV_PRIO": {"KEEP": "seed"},
                         "OPENCODE_BUS_PROXY_DISCOVERY": discovery, "OPENCODE_BUS_PROXY_EFFECT_WATCH": watcher,
                         "ansible_user_dir": str(temporary / "home"), "ansible_env": {"XDG_STATE_HOME": str(temporary / "state")}}
            deployment, _ = generate(temporary, variables, env_config=True, preliminary_tasks=proxy["tasks"][:-1])
            run([deployment / "bin/config-assemble.sh", "--definition", "env"], deployment)
            result = run(["bash", "-c", 'source "$1"; python3 -c "import json,os;print(json.dumps(dict(os.environ)))"', "bash", deployment / "env.export"], deployment)
            env = json.loads(result.stdout)
            assert env["KEEP"] == "seed"
            assert env["BUS_PROXY_UPSTREAM"] == f'http://127.0.0.1:{shared["OPENCODE_PRIMARY_PORT"]}'
            assert env["BUS_PROXY_LISTEN"] == f'127.0.0.1:{shared["OPENCODE_BUS_PROXY_PORT"]}'
            assert ("BUS_PROXY_SERVICE_FILE" in env) == discovery
            assert ("BUS_PROXY_SERVICE_WATCH_HELPER" in env) == (discovery and watcher)
            if discovery:
                assert env["BUS_PROXY_SERVICE_MODE"] == shared["OPENCODE_BUS_PROXY_SERVICE_MODE"]
                assert env["BUS_PROXY_SERVICE_METADATA"] == "true"


def test_named_audience_install():
    with tempfile.TemporaryDirectory(prefix="named-config-actions-", dir="/tmp/opencode") as tmp:
        temporary = Path(tmp)
        deployment = temporary / "deployment"
        definitions = {identity: {"etc": str(deployment / "etc" / identity),
            "configs": {"main.conf": {"processor": "concat", "inputs": [{"glob": "pieces/*.conf", "name": "fragments"}]}},
            "contexts": {"user": {"scope": "user", "root": str(temporary / "consumer" / identity)}}}
            for identity in ("alpha", "beta")}
        deployment, _ = generate(temporary, {"CONFIG_DEFINITIONS": definitions, "ACTION_AUDIENCES": {"available": ["user"]}})
        for identity in definitions:
            (deployment / f"etc/{identity}/pieces/local.conf").write_text(identity + "\n")
            assert (deployment / f"bin/config-{identity}-install.sh").is_symlink()
            run([deployment / f"bin/config-{identity}-assemble.sh", "--context", "canonical"], deployment)
        run([deployment / "bin/install-user.mjs"], deployment)
        for identity in definitions:
            assert (temporary / f"consumer/{identity}/main.conf").read_text() == identity + "\n"


if __name__ == "__main__":
    test_definitions()
    test_env()
    test_current_proxy_priority_preservation()
    test_named_audience_install()
    print("ok: independent CONFIG definitions and literal env.d projections")
