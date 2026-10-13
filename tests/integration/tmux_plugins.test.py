#!/usr/bin/env python3
"""Exercise real CONFIG receivers, remote plugin delivery and tmux root adoption."""

import os
from pathlib import Path
import runpy
import tempfile
import time

import yaml


ROOT = Path(__file__).resolve().parents[2]
helpers = runpy.run_path(str(ROOT / "tests/integration/config_definitions.test.py"))
generate, run = helpers["generate"], helpers["run"]


def render(parent, playbook):
    parent.mkdir()
    play = yaml.safe_load((ROOT / playbook).read_text())[0]
    variables = {}
    for source in play.get("vars_files", []):
        variables.update(yaml.safe_load((ROOT / source).read_text()))
    variables.update(play["vars"])
    variables["NAME"] = playbook.split(".")[0]
    # The partial renderer establishes deployment facts in its first task;
    # bind these two host references before that task evaluates nested values.
    variables = yaml.safe_load(yaml.safe_dump(variables)
        .replace("{{NAME}}", variables["NAME"])
        .replace("{{DIR}}", str(parent / "deployment")))
    if "CONFIG_DEFINITIONS" in variables:
        # A second complete CONFIG deliberately reuses the local input name.
        variables["CONFIG_DEFINITIONS"]["other"] = {
            "configs": {"other.conf": {"processor": "concat", "inputs": [
                {"glob": "other.d/*.conf", "name": "plugins", "remote": True}]}},
            "contexts": {"user": {"scope": "user", "root": "config", "subpath": "other"}}}
    return generate(parent, variables)[0]


def test_receivers():
    with tempfile.TemporaryDirectory(prefix="tmux-config-", dir="/tmp/opencode") as tmp:
        temporary = Path(tmp)
        resurrect = render(temporary / "resurrect", "tmux-resurrect.etc.pb")
        continuum = render(temporary / "continuum", "tmux-continuum.etc.pb")
        for manager in ("tpm-ahiru", "tmux-tpm"):
            host = render(temporary / manager, manager + ".src.pb")
            home = temporary / (manager + "-home")
            home.mkdir()
            config = home / ".tmux.conf"
            config.write_text("# personal configuration\nset -g history-limit 12345\n")
            environment = {**os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(home / "config")}
            environment.pop("TMUX_CONF", None)
            aggregate = host / "etc/tmux-plugins.conf"
            run([host / "bin/config-assemble.sh", "--definition", "tmux", "--context", "canonical"], host)
            assert "tmux-resurrect" not in aggregate.read_text()
            assert "tmux-continuum" not in aggregate.read_text()
            run([host / "bin/install-user.sh"], host, env=environment)
            installed = home / f"config/tmux/compfuzor/{manager}/tmux-plugins.conf"
            assert installed.is_symlink() and installed.resolve() == aggregate
            root_before = config.read_text()
            assert root_before.startswith("# personal configuration\nset -g history-limit 12345\n")
            assert root_before.index("source-file") < root_before.index("run ")

            # Reverse delivery order must still yield Resurrect before Continuum.
            run([continuum / "bin/install-tmux.sh", host], continuum)
            run([resurrect / "bin/install-tmux.sh", host], resurrect)
            assembled = installed.read_text()
            assert assembled.index("tmux-resurrect") < assembled.index("tmux-continuum")
            assert "set -g @continuum-restore 'off'" in assembled
            assert "set -g @continuum-save-interval '15'" in assembled
            assert "set -g @resurrect-save ' '" in assembled
            assert "set -g @resurrect-restore ' '" in assembled
            assert "set -g @tpm-parallel 'false'" in assembled
            assert config.read_text() == root_before  # remote only touches its receiver
            assert not list((host / "etc/other.d").iterdir())
            # Whole generated aggregates must be stable on a fresh assembly;
            # block-in-file used here previously accumulated blank separators.
            run([host / "bin/config-status.sh", "--definition", "tmux", "--context", "canonical"], host)
            run([host / "bin/config-assemble.sh", "--definition", "tmux", "--context", "canonical"], host)
            assert installed.read_text() == assembled

            # Durable disabled membership survives producer reinstallation.
            remote = host / "bin/config-remote.mjs"
            run([remote, "disable", "tmux/plugins", "99-continuum.conf"], host)
            assert "tmux-continuum" not in installed.read_text()
            run([continuum / "bin/install-tmux.sh", host], continuum)
            assert "tmux-continuum" not in installed.read_text()
            run([remote, "enable", "tmux/plugins", "99-continuum.conf"], host)
            assert "tmux-continuum" in installed.read_text()

            # Repeated manager installation keeps plugin membership and root text.
            run([host / "bin/install-user.sh"], host, env=environment)
            assert config.read_text() == root_before
            assert not (home / "config/tmux/tmux.conf").exists()
            run([host / "bin/config-status.sh", "--definition", "tmux"], host, env=environment)

            # An explicit custom root remains selectable, including spaces.
            custom = home / "custom config.conf"
            custom.write_text("# custom\n")
            run([host / "bin/install-user.sh"], host,
                env={**environment, "TMUX_CONF": str(custom)})
            assert custom.read_text().startswith("# custom\n")
            assert "source-file" in custom.read_text()
            assert config.read_text() == root_before

            if manager == "tpm-ahiru":
                # Exercise the owner's activation command against real isolated
                # tmux; stub only plugin fetching/init, observing loaded options.
                fakebin = home / "fakebin"
                fakebin.mkdir()
                ahiru = fakebin / "ahiru-tpm"
                ahiru.write_text('#!/bin/sh\nprintf "%s:" "$1" >> "$HOME/activation.log"\ntmux show-option -gqv @tmux-apply-probe >> "$HOME/activation.log"\n')
                ahiru.chmod(0o755)
                fragment = continuum / "etc/99-continuum.conf"
                fragment.write_text(fragment.read_text() + "set -g @tmux-apply-probe 'fresh'\n")
                socket = home / "tmux.sock"
                command = ["tmux", "-S", socket]
                run([*command, "-f", "/dev/null", "new-session", "-d", "-s", "apply", "sh"], home)
                try:
                    tmux_env = run([*command, "display-message", "-p", "#{socket_path},#{pid},0"], home).stdout.strip()
                    run([host / "bin/apply-user.sh"], host, env={**environment,
                        "TMUX": tmux_env, "PATH": str(fakebin) + os.pathsep + os.environ["PATH"]})
                    assert (home / "activation.log").read_text() == "install:fresh\ninit:fresh\n"
                    assert "@tmux-apply-probe" in installed.read_text()
                finally:
                    run([*command, "kill-server"], home)

        # A missing active tmux session must not invoke any restoration.
        environment = {key: value for key, value in os.environ.items() if key != "TMUX"}
        result = run([resurrect / "bin/restore-session.sh"], resurrect, env=environment, check=False)
        assert result.returncode != 0 and "inside a tmux session" in result.stderr

        # Continuum status helper reports on an isolated default-socket server
        # (a private TMUX_TMPDIR keeps plain `tmux` off any real server).
        sockets = temporary / "tmux-sockets"
        sockets.mkdir()
        status_env = {**environment, "HOME": str(home), "TMUX_TMPDIR": str(sockets)}
        missing = run([continuum / "bin/status.sh"], continuum, env=status_env, check=False)
        assert missing.returncode == 2 and "no running tmux server" in missing.stderr
        run(["tmux", "-f", "/dev/null", "new-session", "-d", "-s", "status", "sh"], continuum, env=status_env)
        try:
            # Fresh server: continuum never loaded, so no hook and no engine.
            unloaded = run([continuum / "bin/status.sh"], continuum, env=status_env, check=False)
            assert unloaded.returncode == 1
            assert "save hook: MISSING from status-right" in unloaded.stderr
            assert "initialize tmux-resurrect" in unloaded.stderr

            # Simulate an initialized continuum: options, hook, engine, snapshot.
            engine = temporary / "fake-resurrect-save.sh"
            engine.write_text("#!/bin/sh\n")
            engine.chmod(0o755)
            snapshots = temporary / "resurrect-snapshots"
            snapshots.mkdir()
            snapshot = snapshots / "tmux_resurrect_20990101T000000.txt"
            snapshot.write_text("pane\n")
            (snapshots / "last").symlink_to(snapshot)
            settings = [
                ("@continuum-save-interval", "15"),
                ("@continuum-save-last-timestamp", str(int(time.time()) - 300)),
                ("@resurrect-save-script-path", str(engine)),
                ("@resurrect-dir", str(snapshots)),
                # The real plugin prepends #(...continuum_save.sh) to status-right.
                ("status-right", "#(/nonexistent/scripts/continuum_save.sh)status"),
            ]
            for option, value in settings:
                run(["tmux", "set-option", "-g", option, value], continuum, env=status_env)
            healthy = run([continuum / "bin/status.sh"], continuum, env=status_env, check=False)
            assert healthy.returncode == 0
            assert "save hook: attached" in healthy.stdout
            assert "auto-save: every 15m" in healthy.stdout
            assert "last auto-save: 5m ago" in healthy.stdout
            assert "tmux_resurrect_20990101T000000.txt" in healthy.stdout
            assert "continuum: saving every 15m" in healthy.stdout
        finally:
            run(["tmux", "kill-server"], continuum, env=status_env, check=False)


if __name__ == "__main__":
    test_receivers()
    print("ok: TPM/Ahiru CONFIG receivers, remote persistence plugins and manual restore")
