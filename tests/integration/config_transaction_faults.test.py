#!/usr/bin/env python3
"""Fault-inject the standalone CONFIG transaction runner."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "config-transaction"


def run(command: list[str], *, cwd: Path, env: dict[str, str], check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, check=False, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"command failed ({result.returncode}): {command}\n{result.stdout}\n{result.stderr}")
    return result


def write_leaf(path: Path, marker: Path, fail: bool = False) -> None:
    path.write_text(
        f"""#!/bin/bash
printf '%s\n' "$1" >> {str(marker)!r}
while IFS=$'\t' read -r _kind _identity source _block; do cat "$source" >> "$CONFIG_CANDIDATE"; done < "$CONFIG_INPUTS_FILE"
{"exit 7" if fail else ":"}
""",
        encoding="utf-8",
    )
    path.chmod(0o755)


def assert_preserved(root: Path, expected: dict[str, bytes]) -> None:
    for name, content in expected.items():
        assert (root / "etc" / "outputs" / f"{name}.conf").read_bytes() == content
    assert not list(root.rglob(".config-candidate.*"))
    assert not list(root.rglob(".config-backup.*"))


def failing_tool(directory: Path, tool: str, body: str) -> None:
    path = directory / tool
    path.write_text(f"#!/bin/bash\n{body}\n", encoding="utf-8")
    path.chmod(0o755)


def test_transaction_faults() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="faults-", dir=SCRATCH) as tmp:
        root = Path(tmp)
        runner = root / "bin" / "config" / "run.sh"
        leaves = root / "bin" / "internal" / "config"
        inputs = root / "etc" / "inputs"
        outputs = root / "etc" / "outputs"
        runner.parent.mkdir(parents=True)
        leaves.mkdir(parents=True)
        inputs.mkdir(parents=True)
        outputs.mkdir(parents=True)
        runner.write_bytes((ROOT / "files" / "config-run.sh").read_bytes())
        runner.chmod(0o755)
        marker = root / "processor.log"
        for name in ("one", "two"):
            (inputs / f"{name}.conf").write_text(f"{name}=new\n", encoding="utf-8")
            (outputs / f"{name}.conf").write_text(f"{name}=old\n", encoding="utf-8")
            write_leaf(leaves / name, marker)
        spec = {
            "configs": {
                name: {
                    "output": str(outputs / f"{name}.conf"),
                    "inputs": [{"file": str(inputs / f"{name}.conf")}],
                    "validate": None,
                    "apply": True,
                }
                for name in ("one", "two")
            }
        }
        (root / "etc" / "config.spec.json").write_text(json.dumps(spec), encoding="utf-8")
        env = os.environ.copy()
        env.update({"DIR": str(root), "TMPDIR": str(root), "PATH": "/usr/bin:/bin"})
        expected = {name: (outputs / f"{name}.conf").read_bytes() for name in ("one", "two")}

        # Multi-recipe stdout rejects before any processor is launched, both
        # for explicit names and zero-name apply selection.
        marker.unlink(missing_ok=True)
        explicit_stdout = run([str(runner), "--stdout", "one", "two"], cwd=root, env=env, check=False)
        assert explicit_stdout.returncode == 2 and not marker.exists()
        default_stdout = run([str(runner), "--stdout"], cwd=root, env=env, check=False)
        assert default_stdout.returncode == 2 and not marker.exists()
        assert run([str(runner), "--stdout", "one"], cwd=root, env=env).stdout == "one=new\n"
        marker.unlink()

        # A late candidate-stage failure never reaches output staging.
        write_leaf(leaves / "two", marker, fail=True)
        candidate_failure = run([str(runner), "one", "two"], cwd=root, env=env, check=False)
        assert candidate_failure.returncode == 1
        assert_preserved(root, expected)
        write_leaf(leaves / "two", marker)

        for tool in ("cp", "chmod"):
            shims = root / f"{tool}-shims"
            shims.mkdir()
            failing_tool(shims, tool, "exit 73")
            failure = run(
                [str(runner), "one", "two"],
                cwd=root,
                env=env | {"PATH": f"{shims}:/usr/bin:/bin"},
                check=False,
            )
            assert failure.returncode == 73
            assert_preserved(root, expected)

        # Fail the second staged-output move after the first output committed.
        # Existing-output backup moves are calls 1 and 3, staged moves 2 and 4.
        shims = root / "mv-shims"
        shims.mkdir()
        counter = root / "mv-count"
        failing_tool(
            shims,
            "mv",
            f'''count=0; [ ! -f {str(counter)!r} ] || count=$(cat {str(counter)!r})
count=$((count + 1)); printf '%s' "$count" > {str(counter)!r}
[ "$count" -ne 4 ] || exit 74
exec /usr/bin/mv "$@"''',
        )
        move_failure = run(
            [str(runner), "one", "two"],
            cwd=root,
            env=env | {"PATH": f"{shims}:/usr/bin:/bin"},
            check=False,
        )
        assert move_failure.returncode == 1
        assert_preserved(root, expected)


if __name__ == "__main__":
    test_transaction_faults()
    print("ok: strict CONFIG transaction faults")
