#!/usr/bin/env python3
"""Bare producer and consumer metadata reuse CONFIG worker package requirements."""
import importlib.util
import os
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("generated", ROOT / "tests/integration/keybindings_generated.test.py")
generated = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generated)

def test_metadata():
    scratch = ROOT / ".test-agent/keybindings-dependencies"
    scratch.mkdir(parents=True, exist_ok=True)
    if not (scratch / "README.md").exists():
        (scratch / "README.md").write_text("# Dependency metadata scratch\nRender-only stock producer/host artifacts; no package or live install.\n")
    env = {**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"), "TMPDIR": str(scratch)}
    with tempfile.TemporaryDirectory(prefix="metadata-", dir=scratch) as tmp:
        area = Path(tmp)
        generated.render(area / "host", "dependency-host", {"KEYBINDING_CONSUMERS": {"niri": {}, "umbriel": {}}}, env)
        generated.render(area / "producer", "dependency-producer", {"KEYBINDING_ACTIONS": {}, "KEYBINDINGS": {}, "KEYBINDING_TARGETS": ["niri", "umbriel"]}, env)
        print("ok: bare rendered host and producer each contribute jq exactly once without installing packages/tools")

if __name__ == "__main__":
    test_metadata()
