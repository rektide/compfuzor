#!/usr/bin/env python3
"""Exercise the persistent credential source operation without service effects."""

import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def test_credential():
    with tempfile.TemporaryDirectory(prefix="opencode-credential-", dir="/tmp/opencode") as temporary:
        root = Path(temporary)
        secrets = root / "account" / "secrets"
        source = secrets / "OPENCODE_PASSWORD"
        script = root / "credential.sh"
        script.write_text("#!/bin/bash\n" + (ROOT / "files/opencode/credential.sh").read_text().replace("{{PASSWORDS_DIR}}", str(secrets)))

        def run(action, success=True):
            result = subprocess.run(["bash", str(script), action], capture_output=True, text=True)
            assert (result.returncode == 0) == success, result.stderr
            return result

        run("status", False)
        assert not secrets.exists(), "status must not create a source"
        run("ensure")
        value = source.read_bytes()
        assert len(value.rstrip()) == 43
        assert source.stat().st_mode & 0o777 == 0o600
        assert secrets.stat().st_mode & 0o777 == 0o700
        run("ensure")
        run("status")
        assert source.read_bytes() == value, "ensure must not rotate"
        source.chmod(0o644)
        secrets.chmod(0o755)
        run("status", False)
        run("ensure")
        assert source.read_bytes() == value
        assert source.stat().st_mode & 0o777 == 0o600
        assert secrets.stat().st_mode & 0o777 == 0o700
        source.write_bytes(b"")
        run("ensure", False)
        assert source.read_bytes() == b"", "invalid existing source is not silently replaced"
        source.unlink()
        unrelated = root / "other-password"
        unrelated.write_bytes(value)
        source.symlink_to(unrelated)
        run("ensure", False)
        assert unrelated.read_bytes() == value
        source.unlink()
        os.mkfifo(source)
        run("ensure", False)
        source.unlink()
        run("ensure")
        result = run("status")
        assert source.read_text().strip() not in result.stdout + result.stderr


if __name__ == "__main__":
    test_credential()
    print("ok: private credential creation, no rotation, permissions, read-only status, invalid-file refusal")
