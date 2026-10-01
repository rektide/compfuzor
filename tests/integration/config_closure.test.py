#!/usr/bin/env python3
"""The optional closure hook sees every candidate before the sole CONFIG commit."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent/config-closure"


def test_closure():
    SCRATCH.mkdir(parents=True, exist_ok=True)
    (SCRATCH / "README.md").write_text("# CONFIG closure scratch\nIsolated runner hook and link-publication fixtures.\n")
    with tempfile.TemporaryDirectory(prefix="hook-", dir=SCRATCH) as tmp:
        root = Path(tmp)
        (root / "bin/internal/config").mkdir(parents=True)
        source = root / "donor"
        source.write_text("captured body")
        old = root / "old"
        old.write_text("old body")
        output = root / "output"
        output.symlink_to("old")
        unchanged = root / "unchanged"
        unchanged.write_text("same")
        for name, content in [("linked", "captured body"), ("unchanged", "same")]:
            leaf = root / "bin/internal/config" / name
            leaf.write_text(f'#!/bin/bash\nprintf %s {shlex.quote(content)} > "$CONFIG_CANDIDATE"\n')
            leaf.chmod(0o755)
        hook = root / "validate.py"
        hook.write_text('''import json, os
from pathlib import Path
entries = json.loads(Path(os.environ["CONFIG_CANDIDATES_FILE"]).read_text())["candidates"]
assert all(Path(entry["candidate"]).is_file() for entry in entries)
assert len(entries) == int(os.environ.get("EXPECTED", "2"))
assert Path(os.environ["OLD_OUTPUT"]).is_symlink()
assert Path(os.environ["OLD_OUTPUT"]).readlink().as_posix() == os.environ.get("OLD_LINK", "old")
assert Path(os.environ["OLD_OUTPUT"]).read_text() == os.environ.get("OLD_BYTES", "old body")
assert os.environ["CONFIG_MODE"] in ["check", "stdout", "apply"]
if os.environ.get("REJECT") == "1": raise ValueError("reject closure")
''')
        spec = {"configs": {
            "linked": {"output": str(output), "link": str(source), "inputs": [], "apply": True},
            "unchanged": {"output": str(unchanged), "inputs": [], "apply": True},
        }, "transaction_validate": "python " + shlex.quote(str(hook))}
        path = root / "spec.json"
        path.write_text(json.dumps(spec))
        env = {**os.environ, "DIR": str(root), "CONFIG_SPEC": str(path), "OLD_OUTPUT": str(output), "TMPDIR": str(SCRATCH)}
        def run(args=(), **extra):
            return subprocess.run(["bash", str(ROOT / "files/config-run.sh"), *args], env=env | extra, capture_output=True, text=True)
        for mode in [[], ["--check", "--quiet"], ["--stdout", "linked"]]:
            failed = run(mode, REJECT="1", EXPECTED="1" if "--stdout" in mode else "2")
            assert failed.returncode != 0 and output.readlink().as_posix() == "old", failed
        preview = run(["--stdout", "linked"], EXPECTED="1")
        assert preview.returncode == 0 and preview.stdout == "captured body", preview
        assert run(["--check", "--quiet"]).returncode == 1 and output.readlink().as_posix() == "old"
        installed = run()
        assert installed.returncode == 0 and output.readlink() == source, installed
        assert run(["--check", "--quiet"], OLD_LINK=str(source), OLD_BYTES="captured body").returncode == 0
        print("ok: candidate closure hook, unchanged candidates, modes and transactional symlink publication")


if __name__ == "__main__":
    test_closure()
