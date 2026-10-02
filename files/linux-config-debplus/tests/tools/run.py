#!/usr/bin/env python3
"""Exercise tools/diff-configs.py against durable fixtures already in the bundle.

Covers the preserved 22-symbol 7.1 state, default metadata exclusion, the
--keys-from fragment restriction, and mixed .xz/plain input. Results are
written to a scratch directory under .test-agent/ (gitignored) and removed on
success; a failure keeps them in place for diagnosis. This is a maintenance
test, not part of any automatic test run.
"""

import argparse
import lzma
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent              # tests/tools
BUNDLE = HERE.parent.parent
TOOL = BUNDLE / "tools" / "diff-configs.py"
RUNNING = BUNDLE / "baselines/7.1/config-running.xz"
SEED_ARCHIVE = BUNDLE / "archive/previous-normalization/config-debian-plus.7.1.0.xz"
FRAGMENT = BUNDLE / "overrides.config"
DEFCONFIG = BUNDLE / "baselines/7.3/config-upstream-defconfig.xz"
CURRENT = BUNDLE / "config-debian-plus.xz"

# The preserved 22 symbol states between the exact running 7.1 configuration
# and the saved seed (which equals the old checkout's .config.old), as
# recorded in the bundle README and baselines/7.1/README.md: Rust support and
# availability, Rust-dependent drivers/panic-QR options, one compiler
# capability probe, and three toolchain metadata symbols. The transitions
# below run old=running config, new=saved seed, matching the invocation order.
PRESERVED_22 = {
    "AMCC_QT2025_PHY", "ANDROID_BINDER_IPC_RUST", "AX88796B_RUST_PHY",
    "BINDGEN_VERSION_TEXT", "BLK_DEV_RUST_NULL", "CC_HAS_KCFI_ARITY",
    "DRM_PANIC_SCREEN_QR_CODE", "DRM_PANIC_SCREEN_QR_CODE_URL",
    "DRM_PANIC_SCREEN_QR_VERSION", "FIND_BIT_BENCHMARK_RUST", "NOVA_CORE",
    "RUST", "RUST_BITMAP_HARDENED", "RUST_BUILD_ASSERT_ALLOW",
    "RUST_DEBUG_ASSERTIONS", "RUST_FW_LOADER_ABSTRACTIONS",
    "RUST_IS_AVAILABLE", "RUST_OVERFLOW_CHECKS", "RUST_PHYLIB_ABSTRACTIONS",
    "RUSTC_LLVM_VERSION", "RUSTC_VERSION", "RUSTC_VERSION_TEXT",
}
# The subset of PRESERVED_22 that the default metadata exclusion must hide.
METADATA_SYMBOLS = {"RUSTC_LLVM_VERSION", "RUSTC_VERSION", "RUSTC_VERSION_TEXT"}


def run_tool(*arguments):
    result = subprocess.run(
        [sys.executable, str(TOOL), *arguments], text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
    return result.stdout.splitlines()


def symbols(lines):
    return {line.split(":", 1)[0] for line in lines}


def transitions(lines):
    return {head: tuple(tail.split(" -> ", 1))
            for head, tail in (line.split(": ", 1) for line in lines)}


def declared_symbols(text):
    """Fragment symbol names, treating "# ... is not set" as declared too."""
    found = set()
    for line in text.splitlines():
        if line.startswith("CONFIG_"):
            found.add(line.split("=", 1)[0].removeprefix("CONFIG_"))
        elif line.startswith("# CONFIG_") and line.endswith(" is not set"):
            found.add(line[len("# CONFIG_"):-len(" is not set")])
    return found


def run_tests(scratch):
    # The preserved 22-state shape, metadata included (recorded count).
    included = run_tool(str(RUNNING), str(SEED_ARCHIVE), "--include-metadata")
    (scratch / "running-vs-seed-22.txt").write_text("\n".join(included) + "\n")
    assert len(included) == 22, f"expected 22 differences, got {len(included)}"
    assert symbols(included) == PRESERVED_22, sorted(PRESERVED_22 ^ symbols(included))

    # Default output excludes toolchain metadata symbols; exactly the
    # 19 non-metadata states of the same preserved shape remain.
    default = run_tool(str(RUNNING), str(SEED_ARCHIVE))
    (scratch / "running-vs-seed-default.txt").write_text("\n".join(default) + "\n")
    assert len(default) == 19, f"expected 19 differences, got {len(default)}"
    assert symbols(default) == PRESERVED_22 - METADATA_SYMBOLS

    # --keys-from restricts the comparison to symbols declared in the
    # fragment; the defconfig->current pair then shows only declared policy.
    fragment = run_tool(str(DEFCONFIG), str(CURRENT), "--keys-from", str(FRAGMENT))
    (scratch / "defconfig-keys-from-overrides.txt").write_text("\n".join(fragment) + "\n")
    assert fragment, "expected declared-policy differences against the defconfig"
    assert symbols(fragment) <= declared_symbols(FRAGMENT.read_text()), \
        sorted(symbols(fragment) - declared_symbols(FRAGMENT.read_text()))
    changes = transitions(fragment)
    for symbol, expected in [("X86_NATIVE_CPU", ("n", "y")),
                             ("DEFAULT_TCP_CONG", ('"cubic"', '"bbr"')),
                             ("RUST", ("n", "y"))]:
        assert changes.get(symbol) == expected, (symbol, changes.get(symbol))

    # Mixed input: the seed as decompressed plain text must yield the
    # identical comparison to its .xz container.
    plain = scratch / SEED_ARCHIVE.with_suffix("").name
    plain.write_bytes(lzma.decompress(SEED_ARCHIVE.read_bytes()))
    mixed = run_tool(str(RUNNING), str(plain), "--include-metadata")
    (scratch / "running-vs-seed-plain.txt").write_text("\n".join(mixed) + "\n")
    assert mixed == included, "plain-text input changed the comparison"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-dir", type=Path,
                        default=Path.cwd() / ".test-agent/linux-debplus-tools",
                        help="temporary test root (default: cwd/.test-agent/linux-debplus-tools)")
    args = parser.parse_args()
    scratch = args.scratch_dir.resolve()
    scratch.mkdir(parents=True, exist_ok=True)
    try:
        run_tests(scratch)
    except AssertionError:
        print(f"results kept for diagnosis: {scratch}", file=sys.stderr)
        raise
    shutil.rmtree(scratch)


if __name__ == "__main__":
    main()
