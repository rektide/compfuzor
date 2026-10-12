#!/usr/bin/env python3
"""Real proxy rendering, selected ENV assembly, and isolated normal Zim import.

Requires Ansible, Node, Zsh, envdefault, and the house block-in-file checkout
(path may be overridden). Uses vendored zimfw. No proxy/OpenCode build or live activation.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import pwd
import shlex
import shutil
import subprocess
import tempfile

import yaml


ROOT = Path(__file__).resolve().parents[2]


def run(args, *, cwd=ROOT, env=None, check=True):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, env=env, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"failed {args} ({result.returncode})\n{result.stdout}\n{result.stderr}")
    return result


def isolated_environment(temporary):
    environment = os.environ.copy()
    for key in list(environment):
        if key in ("DIR", "NAME", "TYPE", "ENV_BYPASS") or key.startswith(("OPENCODE_", "BUS_PROXY_", "COMPFUZOR_", "ZIM_", "RUST_", "CONFIG_")):
            environment.pop(key)
    node = run(["node", "-p", "process.execPath"]).stdout.strip()
    environment.update({"PATH": os.pathsep.join((str(Path(node).parent), "/usr/local/bin", "/usr/bin", "/bin")),
                        "HOME": str(temporary / "home"), "ZDOTDIR": str(temporary / "home"),
                        "XDG_CONFIG_HOME": str(temporary / "home/.config"),
                        "XDG_STATE_HOME": str(temporary / "home/.local/state"),
                        "XDG_CACHE_HOME": str(temporary / "home/.cache"),
                        "XDG_DATA_HOME": str(temporary / "home/.local/share"),
                        "TMPDIR": str(temporary), "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")})
    Path(environment["HOME"]).mkdir(exist_ok=True)
    return environment


def render(temporary, deployment, playbook, environment, overrides=None):
    # Every writable hierarchy, account path, checkout, unit/link target and
    # package/build/lifecycle lane is confined or bypassed. USER=false avoids
    # user creation; unit files/install scripts are rendered, NEVER invoked.
    checkout = temporary / "empty-checkout"
    checkout.mkdir(exist_ok=True)
    variables = {
        "type": "src" if playbook.name.endswith(".src.pb") else "opt",
        "DIR": str(deployment), "ETC": str(deployment / "etc"), "BINS_DIR": str(deployment / "bin"),
        "USERMODE": True, "USER": False, "OWNER": pwd.getpwuid(os.getuid()).pw_name, "GROUP": str(os.getgid()), "BECOME": False,
        "HOMEDIR": environment["HOME"], "ansible_user_dir": environment["HOME"],
        "REPO_DIR": str(checkout), "GIT_DIR": str(checkout), "SRC": str(deployment / "src"),
        "GLOBAL_BINS_DIR": str(temporary / "global-bin"),
        "SYSTEMD_USER_UNIT_DIR": str(temporary / "units"), "SYSTEMD_SYSTEM_UNIT_DIR": str(temporary / "system-units"),
        "GET_URLS": [], "PKGS": [], "ARCH_PKGS": [],
        "REPO_BYPASS": True, "GIT_BYPASS": True, "GET_URLS_BYPASS": True,
        "PKGS_BYPASS": True, "APT_BYPASS": True, "MODULES_BYPASS": True,
        "BINS_RUN_BYPASS": True, "BUILD_RUN_BYPASS": True,
        "SYSTEMD_THUNK_BYPASS": True, "LINKS_BYPASS": True, "GLOBAL_BINS_BYPASS": True,
        "FS_SRCS_BYPASS": True, "TOOL_VERSIONS_LINK_BYPASS": True,
    }
    for family in ("SRV", "OPT", "ETC", "VAR", "LOG", "SPOOL", "CACHE", "SRC", "PID", "RUN", "SHARE", "REPO"):
        variables[family + "S_DIR"] = str(temporary / (family.lower() + "-material"))
    variables.update(overrides or {})
    for source in ("files", "vars", "roles"):
        link = temporary / source
        if not link.exists():
            link.symlink_to(ROOT / source, target_is_directory=True)
    # These are authored test defaults, NOT extra-vars: Ansible extra-vars
    # would mask the play's conditional ENV_PRIO set_fact updates.
    scenario = temporary / "scenario.pb"
    scenario.write_text(yaml.safe_dump([{"import_playbook": str(playbook), "vars": variables}], sort_keys=False))
    # Shared vars_files defaults outrank imported play vars. Port/feature
    # switches are genuine command-line controls; only those go in extra-vars.
    switches = {key: value for key, value in variables.items() if key.startswith("OPENCODE_")}
    run(["ansible-playbook", "-i", "localhost,", "-c", "local", scenario, "-e", json.dumps(switches)], env=environment)


def assemble(deployment, environment, *, check=False):
    args = [deployment / "bin/config-assemble.sh", "--definition", "env", "--context", "canonical"]
    if check:
        args.append("--check")
    return run(args, env={**environment, "DIR": "/foreign-deployment"})


def exported(path, environment):
    result = run(["bash", "-c", 'set -a; source "$1"; set +a; python3 -c "import json,os;print(json.dumps(dict(os.environ)))"', "bash", path], env=environment)
    return json.loads(result.stdout)


def client(module, environment, setup="", *, check=True):
    # Start Zsh without startup profiles and inspect exported process ENV,
    # proving native OPENCODE_ARGS rather than a shell alias/function wrapper.
    script = setup + '\nsource "$1" || exit $?\npython3 -c "import json,os;print(json.dumps(dict(os.environ)))"'
    result = run(["zsh", "-dfc", script, "zsh", module], env=environment, check=check)
    return json.loads(result.stdout) if check else result


def command_environment(deployment, environment):
    # Execute the actual generated Rust operation's setup only. Never reach its
    # cwd/body or run cargo/install a binary, even in this disposable fixture.
    generated = (deployment / "bin/install-rust.sh").read_text()
    prefix, separator, _body = generated.partition("# setopts helper:")
    assert separator and "# env helper:" in prefix
    result = run(["bash", "-c", prefix + '\npython3 -c "import json,os;print(json.dumps(dict(os.environ)))"'], env=environment)
    return json.loads(result.stdout)


def check_projection(deployment, environment, primary, proxy, discovery, watcher):
    etc = deployment / "etc"
    service = etc / "env-projections/proxy-service.env"
    client_export = etc / "env-projections/proxy-client.env.export"
    # These simple fixture values also parse as shell assignments; source only
    # in a disposable Bash subprocess, not as the systemd parsing oracle.
    daemon = exported(service, environment)
    selected_client = exported(client_export, environment)
    unit = (etc / "opencode-bus-proxy.service").read_text()
    assert f"EnvironmentFile={service}" in unit and unit.count("EnvironmentFile=") == 1
    assert "Wants=opencode.service" in unit and "After=opencode.service" in unit
    assert "Restart=always" in unit and "ExecStartPre=/bin/sh" in unit
    assert daemon["BUS_PROXY_UPSTREAM"] == f"http://127.0.0.1:{primary}"
    assert daemon["BUS_PROXY_LISTEN"] == f"127.0.0.1:{proxy}"
    assert daemon["BUS_PROXY_PASSWORD_FILE"] == environment["HOME"] + "/.config/opencode/secrets/OPENCODE_PASSWORD"
    assert daemon["KEEP"] == "seed"
    assert ("BUS_PROXY_SERVICE_FILE" in daemon) == discovery, (discovery, watcher, daemon)
    assert ("BUS_PROXY_SERVICE_WATCH_HELPER" in daemon) == (discovery and watcher)
    assert ("BUS_PROXY_SERVICE_WATCH_SOURCE" in daemon) == (discovery and watcher)
    if discovery:
        assert daemon["BUS_PROXY_SERVICE_MODE"] == "cooperate" and daemon["BUS_PROXY_SERVICE_METADATA"] == "true"
    for name in ("DIR", "NAME", "TYPE", "RUST_COPY", "ZIM_HOST_DIR", "APP_LOCAL", "OPENCODE_ARGS", "OPENCODE_PROXY_URL", "BUS_PROXY_STALE"):
        assert name not in daemon, name
    assert selected_client["OPENCODE_PROXY_URL"] == f"http://127.0.0.1:{proxy}"
    assert not any(key.startswith("BUS_PROXY_") for key in selected_client)
    for name in ("DIR", "NAME", "TYPE", "RUST_COPY", "ZIM_HOST_DIR", "KEEP", "OPENCODE_ARGS"):
        assert name not in selected_client, name
    # Inspect exact compiled membership, not only current output bytes.
    spec = json.loads((etc / "config/env/spec.json").read_text())
    projections = {Path(recipe["output"]).name: recipe for recipe in spec["configs"].values()}
    assert [Path(row["file"]).name for row in projections[service.name]["inputs"]] == ["50-proxy-service.env", "99-local-priority.env"]
    assert [Path(row["file"]).name for row in projections[client_export.name]["inputs"]] == ["60-proxy-client.env"]
    assert set(json.loads((etc / "config/instances.json").read_text())["definitions"]) == {"env"}
    assert not (etc / "zim.spec.json").exists()  # Producer, not an invented host.
    return service, client_export


def check_shell(deployment, environment, proxy):
    module = deployment / "etc/zim-modules/opencode-bus-proxy-client-env/init.zsh"
    run(["zsh", "-dfn", module], env=environment)
    run(["zsh", "-dfn", deployment / "etc/env-projections/proxy-client.env.export"], env=environment)
    default = f"http://127.0.0.1:{proxy}"
    for setup, url, args in (
        ("", default, "--server " + default),
        ('OPENCODE_PROXY_URL=""; OPENCODE_ARGS=""', default, "--server " + default),
        ('OPENCODE_PROXY_URL=http://operator.test:8080', "http://operator.test:8080", "--server http://operator.test:8080"),
        ('OPENCODE_PROXY_URL=http://operator.test:8080; export OPENCODE_ARGS="--standalone --continue"', "http://operator.test:8080", "--standalone --continue"),
        ('export OPENCODE_ARGS="--server http://explicit.test:9090"', default, "--server http://explicit.test:9090"),
    ):
        values = client(module, environment, setup)
        assert values["OPENCODE_PROXY_URL"] == url and values["OPENCODE_ARGS"] == args
        assert not any(key.startswith("BUS_PROXY_") for key in values)
        assert "DIR" not in values and "NAME" not in values
    # Source-time defaults are not a managed existing-shell refresh.
    values = client(module, environment, f'source {shlex.quote(str(module))}; OPENCODE_PROXY_URL=http://later.test:8080')
    assert values["OPENCODE_PROXY_URL"] == "http://later.test:8080" and values["OPENCODE_ARGS"] == "--server " + default
    projection = deployment / "etc/env-projections/proxy-client.env.export"
    retained = projection.read_bytes()
    projection.unlink()
    missing = client(module, environment, check=False)
    assert missing.returncode and "no such file" in missing.stderr.lower()
    # A deliberate URL override needs no default, so absent projection is inert.
    values = client(module, environment, "OPENCODE_PROXY_URL=http://operator.test:8080")
    assert values["OPENCODE_ARGS"] == "--server http://operator.test:8080"
    projection.write_bytes(retained)
    return module


def normal_zim_import(temporary, producer, environment):
    block = Path(os.environ.get("PROXY_TEST_BLOCK_IN_FILE", str(Path.home() / "src/block-in-file/dist/block-in-file.mjs")))
    controller = Path(os.environ.get("PROXY_TEST_ZIMFW", str(ROOT / "runtime/zimfw.zsh")))
    assert block.is_file() and controller.is_file(), "set PROXY_TEST_BLOCK_IN_FILE/PROXY_TEST_ZIMFW to available checkouts"
    node = shutil.which("node")
    wrapper = temporary / "block-in-file"
    wrapper.write_text(f"#!/bin/sh\nexec {shlex.quote(node)} {shlex.quote(str(block))} \"$@\"\n")
    wrapper.chmod(0o755)
    host = temporary / "zim-host"
    render(temporary, host, ROOT / "zim.opt.pb", environment, {"ZIM_MODULES": [], "type": "opt"})
    assert not list((host / "etc/zimrc.d").iterdir()) and not list((host / "etc/zimenv.d").iterdir()), "fixture host must contain no remote modules"
    (host / "src").mkdir(exist_ok=True)
    shutil.copyfile(controller, host / "src/zimfw.zsh")
    runtime_env = {**environment, "CONFIG_BLOCK_IN_FILE": str(wrapper)}
    run([host / "bin/install-zim.sh"], env=runtime_env)
    # The producer's authored ordinary ENV contains a deliberately wrong host.
    # Its generated helper must preserve this explicit invocation override.
    projection = producer / "etc/env-projections/proxy-client.env.export"
    projection.unlink()  # Import must assemble its prerequisite, not trust stale render state.
    run([producer / "bin/install-zimfw.sh"], env={**runtime_env, "ZIM_HOST_DIR": str(host), "DIR": "/foreign-deployment"})
    assert projection.is_file()
    imported = Path(environment["XDG_CONFIG_HOME"]) / "zsh/zimrc.d/56-opencode-bus-proxy-client-env.conf"
    assert imported.is_symlink() and imported.resolve().is_relative_to(producer)
    cache = Path(environment["HOME"]) / ".cache/zim/init.zsh"
    assert str(producer / "etc/zim-modules/opencode-bus-proxy-client-env/init.zsh") in cache.read_text()
    values = client(cache, runtime_env)
    assert values["OPENCODE_ARGS"] == "--server http://127.0.0.1:49372"
    assert not any(key.startswith("BUS_PROXY_") for key in values)
    run([producer / "bin/install-zimfw.sh"], env={**runtime_env, "ZIM_HOST_DIR": str(host)})
    assert imported.is_symlink()


def main():
    assert shutil.which("envdefault"), "envdefault required to verify invocation-default policy"
    with tempfile.TemporaryDirectory(prefix="proxy-env-adoption-", dir="/tmp/opencode") as tmp:
        temporary = Path(tmp)
        environment = isolated_environment(temporary)
        deployment = temporary / "proxy"
        overrides = {"ENV": {"RUST_COPY": "true", "ZIM_HOST_DIR": str(temporary / "wrong-host"), "APP_LOCAL": "local",
                              "DIR": "/application-not-execution", "NAME": "application-not-execution"},
                     "ENV_PRIO": {"KEEP": "seed"}}
        # All four off/on combinations, including changed flags on one retained
        # deployment; no automatic cleanup is assumed.
        for discovery, watcher in ((False, False), (False, True), (True, False), (True, True)):
            render(temporary, deployment, ROOT / "opencode-bus-proxy.src.pb", environment,
                   {**overrides, "OPENCODE_BUS_PROXY_DISCOVERY": discovery, "OPENCODE_BUS_PROXY_EFFECT_WATCH": watcher})
            assemble(deployment, environment)
            check_projection(deployment, environment, 49373, 49372, discovery, watcher)
        values = command_environment(deployment, {**environment, "DIR": "/foreign", "NAME": "foreign", "RUST_COPY": "false", "ZIM_HOST_DIR": "/invocation-host"})
        assert values["DIR"] == str(deployment) and values["NAME"] == "opencode-bus-proxy-git"
        assert values["RUST_COPY"] == "false" and values["ZIM_HOST_DIR"] == "/invocation-host"
        values = command_environment(deployment, {**environment, "RUST_COPY": "", "DIR": "/foreign"})
        assert values["RUST_COPY"] == "" and values["APP_LOCAL"] == "local" and values["DIR"] == str(deployment)
        values = command_environment(deployment, {**environment, "RUST_COPY": "", "ENV_BYPASS": "true", "DIR": "/foreign"})
        assert values["RUST_COPY"] == "" and values["DIR"] == str(deployment) and "APP_LOCAL" not in values
        check_shell(deployment, environment, 49372)
        normal_zim_import(temporary, deployment, environment)
        # A retired optional contribution remains on disk, but exact service
        # and client membership never pulls it back into either consumer.
        stale = deployment / "etc/env.d/70-retired-watch.env"
        stale.write_text('BUS_PROXY_STALE="retained"\nBUS_PROXY_SERVICE_WATCH_HELPER="/obsolete"\n')
        custom = {**overrides, "OPENCODE_PRIMARY_PORT": 51001, "OPENCODE_BUS_PROXY_PORT": 51000,
                  "OPENCODE_BUS_PROXY_DISCOVERY": False, "OPENCODE_BUS_PROXY_EFFECT_WATCH": False}
        render(temporary, deployment, ROOT / "opencode-bus-proxy.src.pb", environment, custom)
        assemble(deployment, environment)
        service, projection = check_projection(deployment, environment, 51001, 51000, False, False)
        check_shell(deployment, environment, 51000)
        assert stale.exists() and "BUS_PROXY_STALE" in (deployment / "env.export").read_text()
        before = (service.read_bytes(), projection.read_bytes())
        render(temporary, deployment, ROOT / "opencode-bus-proxy.src.pb", environment, custom)
        assemble(deployment, environment)
        assemble(deployment, environment, check=True)
        assert before == (service.read_bytes(), projection.read_bytes())
    print("ok: real proxy ENV adoption, separated projections, shell policy, and normal Zim import")


if __name__ == "__main__":
    main()
