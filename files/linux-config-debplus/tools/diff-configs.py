#!/usr/bin/env python3
"""Compare two kernel configuration files and print their symbol differences.

Output matches the bundle's recorded layer diffs: one "SYMBOL: old -> new"
line per difference and nothing else. Inputs may be plain text or .xz
compressed files; "-" reads standard input (compressed input there is
detected by its magic bytes). The exit status is 0 whether or not symbols
differ, and non-zero only for usage or input errors.

Toolchain version/identity symbols are excluded by default: Kconfig records
them at normalize time, so they describe the invoking machine, not policy.
"""

import argparse
import lzma
import re
import sys
from pathlib import Path

# Same toolchain-metadata symbol family as debian/retrieve.py's METADATA
# pattern (compiler/tool version probes). The regex is deliberately
# duplicated rather than imported so this tool stays standalone when the
# bundle directory is copied out of the repository.
METADATA = re.compile(
    r"^(CC_VERSION_TEXT|CC_IS_.*|GCC_VERSION|CLANG_VERSION|AS_IS_.*|AS_VERSION"
    r"|LD_IS_.*|LD_VERSION|LLD_VERSION|RUSTC_VERSION.*|RUSTC_LLVM_VERSION"
    r"|PAHOLE_VERSION|TOOLS_SUPPORT_.*)$")


def parse_config(text):
    """Map symbol name to value; "# CONFIG_X is not set" becomes "n"."""
    values = {}
    for line in text.splitlines():
        match = re.fullmatch(r"CONFIG_(\w+)=(.*)", line)
        if match:
            values[match[1]] = match[2]
        else:
            match = re.fullmatch(r"# CONFIG_(\w+) is not set", line)
            if match:
                values[match[1]] = "n"
    return values


def config_bytes(location):
    """Read a config from a path (".xz" honored by suffix) or stdin ("-")."""
    if str(location) == "-":
        data = sys.stdin.buffer.read()
        return lzma.decompress(data) if data.startswith(b"\xfd7zXZ\x00") else data
    data = Path(location).read_bytes()
    return lzma.decompress(data) if Path(location).suffix == ".xz" else data


def delta(before, after, keys=None, exclude_metadata=True):
    """Sorted "SYMBOL: old -> new" lines, restricted to keys when given."""
    lines = []
    for symbol in sorted(keys if keys is not None else before.keys() | after.keys()):
        if exclude_metadata and METADATA.fullmatch(symbol):
            continue
        old, new = before.get(symbol, "<absent>"), after.get(symbol, "<absent>")
        if old != new:
            lines.append(f"{symbol}: {old} -> {new}")
    return lines


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("old", help="old configuration file, or - for stdin")
    parser.add_argument("new", help="new configuration file, or - for stdin")
    parser.add_argument("--include-metadata", action="store_true",
                        help="also report toolchain version/identity symbols")
    parser.add_argument("--keys-from", type=Path, metavar="PATH",
                        help="only compare symbols declared in this policy fragment")
    parser.add_argument("--quiet", action="store_true",
                        help="print only the number of differences")
    args = parser.parse_args()
    try:
        before = parse_config(config_bytes(args.old).decode())
        after = parse_config(config_bytes(args.new).decode())
        keys = (parse_config(config_bytes(args.keys_from).decode()).keys()
                if args.keys_from else None)
    except (OSError, lzma.LZMAError, UnicodeDecodeError) as err:
        parser.exit(2, f"diff-configs: {err}\n")
    lines = delta(before, after, keys, not args.include_metadata)
    if args.quiet:
        print(len(lines))
    else:
        for line in lines:
            print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
