#!/usr/bin/env python3
"""The external seam retains the existing sole-candidate transaction protocol."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent/keybindings"
sys.path.insert(0, str(ROOT / "library/filter_plugins"))
from config_compile import compile_config


def test_external_processor():
    SCRATCH.mkdir(parents=True, exist_ok=True)
    readme = SCRATCH / "README.md"
    if not readme.exists():
        readme.write_text("# Keybinding scratch\n\nIsolated CONFIG and keybinding test fixtures only.\n")
    with tempfile.TemporaryDirectory(prefix="config-external-", dir=SCRATCH) as tmp:
        root = Path(tmp)
        (root / "bin/internal/config").mkdir(parents=True)
        (root / "bin/config").mkdir()
        (root / "etc").mkdir()
        command = root / "bin/config/processor space"
        command.write_text('''#!/usr/bin/env python3
import os, sys
from pathlib import Path
assert sys.argv[1:4] == ["a'b", "$(false)", ""]
assert sys.argv[4:] == ["--config", "external"]
assert Path(os.environ["CONFIG_SPEC"]).is_file()
assert Path(os.environ["CONFIG_TRANSACTION"]).is_dir()
rows = Path(os.environ["CONFIG_INPUTS_FILE"]).read_text().splitlines()
text = Path(rows[0].split("\\t")[2]).read_text()
Path(os.environ["CONFIG_CANDIDATE"]).write_text(text)
if text == "fail": sys.exit(7)
''')
        command.chmod(0o755)
        input_file = root / "etc/input"
        input_file.write_text("good")
        plan = compile_config({"output": {
            "name": "external", "processor": {"command": "config/processor space", "args": ["a'b", "$(false)", ""]},
            "inputs": [{"file": "input"}], "validate": 'grep -q good "$CONFIG_CANDIDATE"',
        }}, str(root / "etc"))
        spec = root / "etc/config.spec.json"
        spec.write_text(json.dumps(plan["spec"]))
        leaf = root / "bin/internal/config/external"
        leaf.write_text("#!/bin/bash\nset -euo pipefail\n" + plan["bins"][-1]["content"] + "\n")
        leaf.chmod(0o755)
        env = {**os.environ, "DIR": str(root), "CONFIG_SPEC": str(spec)}
        def run(*args):
            return subprocess.run(["bash", str(ROOT / "files/config-run.sh"), *args], env=env, capture_output=True, text=True)
        output = root / "etc/output"
        result = run("--stdout", "external")
        assert result.returncode == 0 and result.stdout == "good" and not output.exists(), result
        assert run("--check", "--quiet").returncode == 1 and not output.exists()
        assert run().returncode == 0 and output.read_text() == "good"
        assert output.stat().st_mode & 0o777 == 0o600
        assert run("--check", "--quiet").returncode == 0
        for bad in ["fail", "validation rejection"]:
            input_file.write_text(bad)
            result = run()
            assert result.returncode != 0 and output.read_text() == "good", result
        print("ok: external processor argv, stdout/check/apply, failure and validation preservation")


if __name__ == "__main__":
    test_external_processor()
