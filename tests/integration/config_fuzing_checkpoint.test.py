#!/usr/bin/env python3
"""Narrow native-root checkpoint; broad fuzing integration is deliberately deferred."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile

source = Path(__file__).with_name("config_definitions.test.py")
spec = importlib.util.spec_from_file_location("definitions_fixture", source)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


def test_checkpoint():
    with tempfile.TemporaryDirectory(prefix="fuzing-checkpoint-", dir="/tmp/opencode") as tmp:
        temporary = Path(tmp)
        definition = {"native": {"configs": {"main.conf": {"processor": "concat", "inputs": [{"glob": "pieces/*.conf", "name": "fragments", "fuzings": {"roots": "fuze.d", "paths": ["native/*.conf"]}}]}}}}
        deployment, _ = fixture.generate(temporary, {"CONFIG_DEFINITIONS": definition})
        producer = temporary / "producer"
        (producer / "native").mkdir(parents=True)
        first = producer / "native/10-one.conf"
        first.write_text("one\n")
        inputs = deployment / "bin/config-inputs.sh"
        assemble = deployment / "bin/config-assemble.sh"
        sync = deployment / "bin/config-sync-inputs.sh"
        fixture.run([inputs, "fuze", "put", "main/fragments", "producer", producer], deployment)
        missing = fixture.run([assemble], deployment, check=False)
        assert missing.returncode and "not delivered" in missing.stderr
        fixture.run([sync, "--strategy", "copy"], deployment)
        fixture.run([assemble], deployment)
        output = deployment / "etc/main.conf"
        assert output.read_text() == "one\n"
        first.write_text("updated\n")
        fixture.run([assemble, "--check", "--quiet"], deployment)
        assert output.read_text() == "one\n"
        fixture.run([sync, "--strategy", "copy"], deployment)
        fixture.run([assemble], deployment)
        assert output.read_text() == "updated\n"
        second = producer / "native/20-two.conf"
        second.write_text("two\n")
        missing = fixture.run([assemble], deployment, check=False)
        assert missing.returncode and output.read_text() == "updated\n"
        fixture.run([sync, "--strategy", "link"], deployment)
        fixture.run([assemble], deployment)
        assert output.read_text() == "updated\ntwo\n"
        second.write_text("live\n")
        fixture.run([assemble], deployment)
        assert output.read_text() == "updated\nlive\n"
        fixture.run([inputs, "fuze", "disable", "main/fragments", "producer"], deployment)
        fixture.run([inputs, "fuze", "put", "main/fragments", "producer", producer], deployment)
        fixture.run([assemble], deployment)
        assert output.read_text() == "" and (deployment / "etc/pieces/.fuzings/producer/native/20-two.conf").exists()
        fixture.run([inputs, "fuze", "enable", "main/fragments", "producer"], deployment)
        fixture.run([assemble], deployment)
        assert output.read_text() == "updated\nlive\n"


if __name__ == "__main__":
    test_checkpoint()
    print("ok: explicit native-root delivery checkpoint (copy/link, disabled/idempotent, no implicit refresh)")
