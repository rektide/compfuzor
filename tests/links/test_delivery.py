#!/usr/bin/env python3
"""Focused safety and equivalence tests for shared delivery primitives."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
MODULE = (ROOT / "files" / "links" / "delivery.ts").as_uri()
NODE = subprocess.run(["node", "-p", "process.execPath"], check=True, text=True, capture_output=True).stdout.strip()


def invoke(function: str, source: Path, destination: Path) -> subprocess.CompletedProcess[str]:
    script = f"""
const delivery = await import({json.dumps(MODULE)});
await delivery.{function}({json.dumps(str(source))}, {json.dumps(str(destination))});
"""
    return subprocess.run([NODE, "--input-type=module", "--eval", script], text=True, capture_output=True, check=False)


def test_alias_parent_cannot_target_donor_entry(tmp_path: Path) -> None:
    donor = tmp_path / "donor"
    donor.mkdir()
    source = donor / "a.conf"
    source.write_text("donor\n", encoding="utf-8")
    alias = tmp_path / "alias"
    alias.symlink_to(donor, target_is_directory=True)
    destination = alias / "a.conf"

    copied = invoke("replaceWithCopy", source, destination)
    assert copied.returncode != 0
    assert "same directory entry" in copied.stderr
    assert source.read_text(encoding="utf-8") == "donor\n" and not source.is_symlink()

    linked = invoke("replaceWithLink", source, destination)
    assert linked.returncode != 0
    assert "same directory entry" in linked.stderr
    assert source.read_text(encoding="utf-8") == "donor\n" and not source.is_symlink()


def test_final_symlink_replacement_remains_permissive(tmp_path: Path) -> None:
    donor = tmp_path / "donor.conf"
    donor.write_text("donor\n", encoding="utf-8")
    destination = tmp_path / "consumer" / "config.conf"
    destination.parent.mkdir()
    destination.symlink_to(donor)

    copied = invoke("replaceWithCopy", donor, destination)
    assert copied.returncode == 0, copied.stderr
    assert not destination.is_symlink()
    assert destination.read_bytes() == donor.read_bytes()
    assert donor.read_text(encoding="utf-8") == "donor\n"


def test_referent_equivalence_and_dangling_chains(tmp_path: Path) -> None:
    producer = tmp_path / "producer.conf"
    producer.write_text("producer\n", encoding="utf-8")
    donor = tmp_path / "donor.conf"
    donor.symlink_to(producer)
    alias_parent = tmp_path / "alias-parent"
    alias_parent.symlink_to(tmp_path, target_is_directory=True)
    consumer = tmp_path / "consumer"
    consumer.mkdir()

    direct = consumer / "direct.conf"
    direct.symlink_to(producer)
    relative = consumer / "relative.conf"
    relative.symlink_to(os.path.relpath(producer, consumer))
    alias = consumer / "alias.conf"
    alias.symlink_to(alias_parent / producer.name)
    dangling = consumer / "dangling.conf"
    dangling.symlink_to(tmp_path / "missing.conf")

    script = f"""
const delivery = await import({json.dumps(MODULE)});
const source = {json.dumps(str(donor))};
const paths = {json.dumps([str(direct), str(relative), str(alias), str(dangling)])};
const result = [];
for (const path of paths) {{
  const entry = await delivery.inspectDeliveryEntry(path);
  result.push(await delivery.linkResolvesToSameFile(entry, source));
}}
console.log(JSON.stringify(result));
"""
    result = subprocess.run([NODE, "--input-type=module", "--eval", script], text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == [True, True, True, False]
