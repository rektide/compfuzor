#!/usr/bin/env python3
"""Exercise real CONFIG receivers, remote plugin delivery and tmux root adoption."""

import os
from pathlib import Path
import runpy
import tempfile

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

        # A missing active tmux session must not invoke any restoration.
        environment = {key: value for key, value in os.environ.items() if key != "TMUX"}
        result = run([resurrect / "bin/restore-session.sh"], resurrect, env=environment, check=False)
        assert result.returncode != 0 and "inside a tmux session" in result.stderr


if __name__ == "__main__":
    test_receivers()
    print("ok: TPM/Ahiru CONFIG receivers, remote persistence plugins and manual restore")
