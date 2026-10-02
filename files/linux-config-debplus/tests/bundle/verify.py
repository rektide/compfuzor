#!/usr/bin/env python3
"""Verify a rendered linux-config-debplus stage against the bundle's receipts.

Maintenance tool, not part of any automatic test run. From a repository
checkout the playbook declaring the bundle is discovered above this script,
so only the stage is needed:

    python3 files/linux-config-debplus/tests/bundle/verify.py \
        --stage .test-agent/<domain>/stage

Checks performed: every declared FILES entry exists in the stage,
byte-identical to the controller input, with the declared mode; the set of
repository-tracked material files equals the declared set; no __pycache__
leaked into the stage; the compression registry in
baselines/7.1/validation.json matches compressed and decompressed hashes of
its artifacts; every debian snapshots audit.json output_sha256 entry matches
the file next to it; and relative markdown links in bundled README files
resolve.

From a deployed bundle copy (no linux-config-debplus.src.pb above this
script) the declaration, mode, and tracked-set checks are skipped with a
note; receipt and link checks still run. Exits non-zero when any performed
check fails.
"""

import argparse
import hashlib
import json
import lzma
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent              # .../tests/bundle
BUNDLE = HERE.parents[1]                            # controller tree or deployed copy
PLAYBOOK_NAME = "linux-config-debplus.src.pb"
CONTROLLER_PREFIX = "files/linux-config-debplus/"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def find_playbook():
    for parent in HERE.parents:
        candidate = parent / PLAYBOOK_NAME
        if candidate.is_file():
            return candidate
    return None


def parse_files_entries(text):
    """Read the playbook's FILES rows without a YAML dependency.

    Every declared row has the same three-line shape (name / copyDir: True /
    mode); matching it directly keeps this tool stdlib-only so it also runs
    from a deployed copy of the bundle.
    """
    pattern = re.compile(
        r'^[ \t]*-[ \t]+name:[ \t]*(\S+)[ \t]*$\n'
        r'^[ \t]*copyDir:[ \t]*True[ \t]*$\n'
        r'^[ \t]*mode:[ \t]*"(\d{4})"[ \t]*$',
        re.M)
    return [(match[1], match[2]) for match in pattern.finditer(text)]


def tracked_material_files(playbook_dir):
    """Bundle-relative names of tracked material files, or None without a repo."""
    repo_relative = Path("files") / BUNDLE.name
    for command in (["git", "ls-files", str(repo_relative)],
                    ["jj", "file", "list", str(repo_relative)]):
        result = subprocess.run(command, cwd=playbook_dir, text=True,
                                capture_output=True)
        if result.returncode == 0:
            return {str(Path(line).relative_to(repo_relative))
                    for line in result.stdout.splitlines() if line.strip()}
    return None


def verify(stage, playbook):
    """Return (failures, notes); each note explains a deliberately skipped check."""
    failures, notes = [], []

    def check(condition, message):
        if not condition:
            failures.append(message)
        return condition

    # Declared files: presence, byte identity, and mode in the stage.
    entries = None
    if playbook is None:
        notes.append("no playbook found above this script; "
                     "declared byte/mode/tracked-set checks skipped")
    else:
        entries = parse_files_entries(playbook.read_text())
        names = [name for name, _ in entries]
        check(len(names) == len(set(names)), "duplicate FILES declarations")
        for name, mode in entries:
            source, rendered = BUNDLE / name, stage / name
            if not (check(source.is_file(), f"controller input missing: {name}")
                    and check(rendered.is_file(), f"stage file missing: {name}")):
                continue
            check(source.read_bytes() == rendered.read_bytes(),
                  f"content differs from controller input: {name}")
            check(rendered.stat().st_mode & 0o777 == int(mode, 8),
                  f"mode differs from declaration: {name}")
        tracked = tracked_material_files(playbook.parent)
        if tracked is None:
            notes.append("no usable git/jj repository above the playbook; "
                         "tracked-set check skipped")
        else:
            declared = set(names)
            check(tracked == declared,
                  "tracked material files and declarations differ: "
                  + repr(sorted(tracked ^ declared)))

    # The render must not carry Python bytecode caches.
    leaked = [str(path.relative_to(stage)) for path in stage.rglob("__pycache__")]
    check(not leaked, f"__pycache__ leaked into the stage: {leaked}")

    # Compression registry: compressed and decompressed hashes and sizes.
    registry_path = BUNDLE / "baselines/7.1/validation.json"
    if check(registry_path.is_file(), "compression registry missing"):
        registry = json.loads(registry_path.read_text())
        for key, item in registry["compression"]["artifacts"].items():
            recorded = item["path"]
            artifact = (BUNDLE / recorded.removeprefix(CONTROLLER_PREFIX)
                        if recorded.startswith(CONTROLLER_PREFIX)
                        else (playbook.parent / recorded if playbook else None))
            if not (artifact and check(artifact.is_file(),
                                       f"registry artifact missing: {key}")):
                notes.append(f"registry artifact not present here: {key}")
                continue
            encoded = artifact.read_bytes()
            check(digest(encoded) == item["sha256"],
                  f"compressed hash differs: {key}")
            decoded = lzma.decompress(encoded)
            check(digest(decoded) == item["plaintext_sha256"],
                  f"decompressed hash differs: {key}")
            check(len(encoded) == item["xz_bytes"], f"compressed size differs: {key}")
            check(len(decoded) == item["plaintext_bytes"],
                  f"decompressed size differs: {key}")

    # Saved audit receipts: every recorded output hash matches the file next
    # to the audit.json that recorded it.
    for audit_path in sorted(BUNDLE.glob("debian/snapshots/**/audit.json")):
        audit = json.loads(audit_path.read_text())
        for name, expected in audit.get("output_sha256", {}).items():
            output = audit_path.parent / name
            label = str(output.relative_to(BUNDLE))
            if check(output.is_file(), f"audited output missing: {label}"):
                check(digest(output.read_bytes()) == expected,
                      f"audited output hash differs: {label}")

    # Relative markdown links inside bundled README files must resolve.
    broken = []
    for readme in BUNDLE.rglob("README.md"):
        for target in re.findall(r"\]\(([^)]+)\)", readme.read_text()):
            if target.startswith(("https://", "http://", "/", "#")):
                continue
            path = target.split("#", 1)[0]
            if path and not (readme.parent / path).exists():
                broken.append(f"{readme.relative_to(BUNDLE)} -> {target}")
    check(not broken, f"broken README links: {broken}")
    return failures, notes


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--stage", required=True, type=Path,
                        help="rendered bundle directory to verify")
    parser.add_argument("--playbook", type=Path, default=None,
                        help="playbook declaring the bundle "
                             "(default: search parent directories of this script)")
    args = parser.parse_args()
    stage = args.stage.resolve()
    if not stage.is_dir():
        parser.exit(2, f"verify: stage directory not found: {stage}\n")
    playbook = (args.playbook.resolve() if args.playbook else find_playbook())
    failures, notes = verify(stage, playbook)
    for note in notes:
        print(f"note: {note}")
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        sys.exit(1)
    print(f"verified stage {stage}: declared bytes/modes, hashes, and links")


if __name__ == "__main__":
    main()
