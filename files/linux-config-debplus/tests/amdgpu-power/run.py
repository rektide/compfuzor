#!/usr/bin/env python3
"""Archive pristine pinned kernel files; never modify the kernel checkout."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tarfile
import io
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SCRIPT = HERE.parents[1] / "hotfixes/amdgpu-power.sh"
TIP = "551c722f40809618230001baccf219193e22fc5a"
RC5 = "72d3fcf802c45d00b300f25b848a93c3a2bd7c7e"
AMD = "drivers/gpu/drm/amd/"
FILES = ["Makefile", AMD + "amdgpu/amdgpu.h", AMD + "amdgpu/amdgpu_drv.c",
         AMD + "pm/amdgpu_pm.c", AMD + "pm/swsmu/amdgpu_smu.c"]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def function(source, name):
    """Extract the actual C function, not a rewritten approximation."""
    match = re.search(r"^(?:static )?(?:int|ssize_t) " + name + r"\([^;]*?\n\{", source, re.M)
    assert match, name
    start = source.index("{", match.start())
    depth = 1
    end = start + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[match.start():end] + "\n"


def snapshot(tree):
    return {p: hashlib.sha256((tree / p).read_bytes()).hexdigest() for p in FILES}


def invoke(tree, check=False, success=True):
    result = subprocess.run([str(SCRIPT), *(["--check"] if check else []), str(tree)],
                            text=True, capture_output=True)
    assert (result.returncode == 0) == success, result.stdout + result.stderr
    return result.stdout


def test_tree(repo, revision, work):
    tree = work / revision[:12]
    tree.mkdir()
    archive = run("git", "-C", str(repo), "archive", revision, *FILES, capture_output=True).stdout
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(tree, filter="data")
    pristine = snapshot(tree)
    assert "applies cleanly" in invoke(tree, check=True)
    assert snapshot(tree) == pristine, "--check modified source"
    invoke(tree)
    patched = snapshot(tree)
    assert all(patched[p] != pristine[p] for p in FILES[1:])
    assert "already applied" in invoke(tree)
    assert "already applied" in invoke(tree, check=True)
    assert snapshot(tree) == patched, "second application modified source"
    patch = SCRIPT.read_text().split("<<'PATCH'\n", 1)[1].split("\nPATCH\n", 1)[0] + "\n"
    patch_path = work / "hotfix.patch"
    patch_path.write_text(patch)
    env = dict(os.environ, GIT_CEILING_DIRECTORIES=str(tree.parent))
    run("git", "-C", str(tree), "apply", "--reverse", "--check", str(patch_path), env=env)

    # Compile the patched functions verbatim with explicit kernel/firmware stubs.
    smu = (tree / FILES[-1]).read_text()
    pm = (tree / FILES[-2]).read_text()
    c = (HERE / "stubs.h").read_text()
    c += function(smu, "smu_get_ppt_limit") + function(smu, "smu_set_ppt_limit")
    c += function(pm, "amdgpu_hwmon_show_power_cap_min")
    c += (HERE / "assertions.c").read_text()
    harness = work / (revision[:12] + ".c")
    harness.write_text(c)
    binary = harness.with_suffix(".test")
    run(os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Wextra", "-Werror",
        str(harness), "-o", str(binary))
    run(str(binary))

    # Partial application must fail, without applying remaining hunks.
    header = run("git", "-C", str(repo), "show", revision + ":" + FILES[1], capture_output=True).stdout
    (tree / FILES[1]).write_bytes(header)
    partial = snapshot(tree)
    invoke(tree, check=True, success=False)
    invoke(tree, success=False)
    assert snapshot(tree) == partial, "partial failure modified source"
    # An incompatible driver hunk likewise must not modify other files.
    run("git", "-C", str(tree), "apply", "--reverse", "--include=" + FILES[2],
        "--include=" + FILES[3], "--include=" + FILES[4], str(patch_path), env=env)
    driver = tree / FILES[2]
    driver.write_text(driver.read_text().replace("unsigned int amdgpu_vram_limit = UINT_MAX;",
                                               "unsigned int incompatible_fixture;"))
    incompatible = snapshot(tree)
    invoke(tree, check=True, success=False)
    invoke(tree, success=False)
    assert snapshot(tree) == incompatible, "incompatible failure modified source"
    print(revision + ": lifecycle and compiled semantic tests passed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel-repo", type=Path, default=Path("/usr/local/src/linux"))
    args = parser.parse_args()
    for path in FILES[1:]:
        contents = [run("git", "-C", str(args.kernel_repo), "show", rev + ":" + path,
                        capture_output=True).stdout for rev in (RC5, TIP)]
        assert contents[0] == contents[1], "rc5/tip differ: " + path
    scratch = ROOT / ".test-agent/linux-debplus-7.3/hotfix"
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="tests-", dir=scratch) as work:
        for revision in (RC5, TIP):
            test_tree(args.kernel_repo, revision, Path(work))
    print("rc5/tip four-file identity verified; original checkout untouched")


if __name__ == "__main__":
    main()
