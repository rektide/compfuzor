#!/usr/bin/env python3
"""Retrieve Debian's generic amd64 config; audit distinct configuration layers."""
import argparse
import datetime
import email.utils
import hashlib
import io
import json
import lzma
import os
from pathlib import Path
import re
import subprocess
import tarfile
import urllib.request

MIRROR = "https://deb.debian.org/debian/"
INDEX = "main/binary-amd64/Packages.xz"
DEFAULT_KEYRING = Path("/usr/share/keyrings/debian-archive-keyring.gpg")
METADATA = re.compile(r"^(CC_VERSION_TEXT|CC_IS_.*|GCC_VERSION|CLANG_VERSION|AS_IS_.*|AS_VERSION|LD_IS_.*|LD_VERSION|LLD_VERSION|RUSTC_VERSION.*|RUSTC_LLVM_VERSION|PAHOLE_VERSION|TOOLS_SUPPORT_.*)$")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def checked(data, expected):
    if sha(data) != expected:
        raise ValueError(f"SHA-256 mismatch: expected {expected}, got {sha(data)}")
    return data


def records(text):
    for paragraph in text.split("\n\n"):
        record = {}
        key = None
        for line in paragraph.splitlines():
            if line.startswith((" ", "\t")) and key:
                record[key] += "\n" + line[1:]
            elif ": " in line:
                key, value = line.split(": ", 1)
                record[key] = value
        if record:
            yield record


def newest(items):
    result = None
    for item in items:
        if result is None or subprocess.run(
            ["dpkg", "--compare-versions", item["Version"], "gt", result["Version"]],
            check=False,
        ).returncode == 0:
            result = item
    return result


def select_package(items):
    items = list(items)
    meta = newest(r for r in items if r.get("Package") == "linux-headers-amd64")
    generic = [r for r in items if re.fullmatch(r"linux-headers-[0-9].*-amd64", r.get("Package", ""))
               and not re.search(r"-(cloud|rt)-amd64$", r["Package"])]
    if meta:
        targets = re.findall(r"\b(linux-headers-[0-9][^ ,|()]*)\s*\(=\s*([^ )]+)\)", meta.get("Depends", ""))
        matches = [r for r in generic if (r["Package"], r["Version"]) in targets]
        if len(matches) != 1:
            raise ValueError("Generic headers metapackage does not resolve to exactly one indexed package")
        return matches[0], meta, "linux-headers-amd64 exact dependency"
    return newest(generic), None, "latest generic headers by Debian version (no metapackage)"


def get(url):
    with urllib.request.urlopen(url, timeout=90) as response:
        return response.read()


def release_index(release):
    # Signed plaintext lines remain in InRelease; signature verification happens first.
    inside = False
    for line in release.decode().splitlines():
        if line == "SHA256:":
            inside = True
        elif inside and not line.startswith(" "):
            break
        elif inside:
            digest, size, name = line.split()
            if name == INDEX:
                return digest, int(size)
    raise ValueError(f"InRelease has no SHA256 entry for {INDEX}")


def extract_config(package, package_name):
    members = subprocess.check_output(["ar", "t", str(package)], text=True).splitlines()
    data_members = [name for name in members if name.startswith("data.tar.") or name == "data.tar"]
    if len(data_members) != 1:
        raise ValueError("Expected exactly one data archive in headers package")
    name = data_members[0]
    data = subprocess.check_output(["ar", "p", str(package), name])
    if name.endswith(".zst"):
        data = subprocess.run(["zstd", "-dc"], input=data, stdout=subprocess.PIPE, check=True).stdout
    expected = "usr/src/" + package_name + "/.config"
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as archive:
        matches = [entry for entry in archive.getmembers() if entry.name.removeprefix("./") == expected]
        if len(matches) != 1 or not matches[0].isfile():
            raise ValueError(f"Expected one regular {expected}; no other package files will be extracted")
        config = archive.extractfile(matches[0]).read()
    if not parse_config(config.decode()):
        raise ValueError("Embedded file contains no configuration symbols")
    return config, expected


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def fetch(args):
    cache = args.cache_dir.resolve()
    output = args.output_dir.resolve()
    suites = ["unstable", "experimental"] if args.suite == "both" else [args.suite]
    cache.mkdir(parents=True, exist_ok=True)
    for suite in suites:
        destination = output / suite
        destination.mkdir(parents=True, exist_ok=True)
        receipt_path = destination / "receipt.json"
        if args.offline:
            receipt = json.loads(receipt_path.read_text())
            release = checked((cache / receipt["release_cache"]).read_bytes(), receipt["release_sha256"])
            index = checked((cache / receipt["index_cache"]).read_bytes(), receipt["index_sha256"])
            if receipt["trust"] == "Debian InRelease signature + SHA256 chain":
                verify_release(cache / receipt["release_cache"], args.keyring)
            digest, size = release_index(release)
            checked(index, digest)
            if len(index) != size:
                raise ValueError("Index size differs from InRelease")
        else:
            release_url = MIRROR + f"dists/{suite}/InRelease"
            release = get(release_url)
            release_cache = sha(release) + ".InRelease"
            (cache / release_cache).write_bytes(release)
            fingerprints = verify_release(cache / release_cache, args.keyring) if not args.tls_only else []
            expires = re.search(r"^Valid-Until: (.+)$", release.decode(), re.M)
            if expires and email.utils.parsedate_to_datetime(expires.group(1)) < datetime.datetime.now(datetime.timezone.utc):
                raise ValueError("Expired current InRelease; use --offline only for deliberate pinned replay")
            digest, size = release_index(release)
            index_url = MIRROR + f"dists/{suite}/" + INDEX
            index = checked(get(index_url), digest)
            if len(index) != size:
                raise ValueError("Index size differs from InRelease")
            index_cache = digest + ".Packages.xz"
            (cache / index_cache).write_bytes(index)
            receipt = {
                "schema": 1, "suite": suite, "architecture": "amd64", "flavour": "generic",
                "retrieved_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "release_url": release_url, "release_sha256": sha(release), "release_cache": release_cache,
                "index_url": index_url, "index_sha256": digest, "index_cache": index_cache,
                "trust": "TLS + SHA256 only (no archive signature verification)" if args.tls_only
                         else "Debian InRelease signature + SHA256 chain",
                "keyring": str(args.keyring) if not args.tls_only else None,
                "verified_signing_fingerprints": fingerprints,
                "release_valid_until": expires.group(1) if expires else None,
                "release_date": re.search(r"^Date: (.+)$", release.decode(), re.M).group(1),
            }
        package, meta, selection = select_package(records(lzma.decompress(index).decode()))
        receipt["selection"] = selection
        receipt["metapackage"] = meta
        receipt["package"] = package
        receipt["status"] = "available" if package else "unavailable-in-suite-index"
        (destination / "InRelease.xz").write_bytes(lzma.compress(release))
        if package:
            filename = package["Filename"]
            if not filename.startswith("pool/") or ".." in Path(filename).parts:
                raise ValueError("Unexpected package filename")
            package_cache = package["SHA256"] + ".deb"
            receipt["package_url"] = MIRROR + filename
            receipt["package_cache"] = package_cache
            if not args.inspect_only:
                package_path = cache / package_cache
                if not package_path.exists():
                    if args.offline:
                        raise FileNotFoundError(f"Pinned package absent from cache: {package_path}")
                    package_path.write_bytes(checked(get(receipt["package_url"]), package["SHA256"]))
                package_data = checked(package_path.read_bytes(), package["SHA256"])
                if len(package_data) != int(package["Size"]):
                    raise ValueError("Package size mismatch")
                config, member = extract_config(package_path, package["Package"])
                config_name = f"config-{package['Version']}-amd64.xz"
                (destination / config_name).write_bytes(lzma.compress(config))
                receipt["config"] = {"file": config_name, "sha256": sha(config), "member": member,
                                     "header": [line for line in config.decode().splitlines()[:8] if "Kernel Configuration" in line]}
        dump(receipt_path, receipt)
        print(f"{suite}: {package['Version'] if package else 'unavailable'}; {receipt_path}")


def verify_release(path, keyring):
    if not keyring.is_file():
        raise FileNotFoundError("Archive keyring unavailable; supply --keyring or explicitly choose --tls-only")
    result = subprocess.run(["gpgv", "--status-fd", "1", "--keyring", str(keyring.resolve()), str(path)],
                            stdout=subprocess.PIPE, text=True, check=True)
    return re.findall(r"^\[GNUPG:\] VALIDSIG ([0-9A-F]+) ", result.stdout, re.M)


def parse_config(text):
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


def config_text(path):
    data = path.read_bytes()
    return (lzma.decompress(data) if path.suffix == ".xz" else data).decode()


def delta(before, after, keys=None, exclude_metadata=False):
    lines = []
    for symbol in sorted(keys if keys is not None else before.keys() | after.keys()):
        if exclude_metadata and METADATA.fullmatch(symbol):
            continue
        old, new = before.get(symbol, "<absent>"), after.get(symbol, "<absent>")
        if old != new:
            lines.append(f"{symbol}: {old} -> {new}")
    return "\n".join(lines) + ("\n" if lines else "")


def required_audit(required, actual, declared):
    return {symbol: {"expected": value, "actual": actual.get(symbol, "<absent>"),
                     "fulfilled": actual.get(symbol) == value,
                     "declaration": "explicit" if declared.get(symbol) == value else "inherited/not explicitly declared"}
            for symbol, value in sorted(required.items())}


def merged_config(base, policy):
    values = parse_config(base) | parse_config(policy)
    return "\n".join(f"# CONFIG_{key} is not set" if value == "n" else f"CONFIG_{key}={value}"
                     for key, value in sorted(values.items())) + "\n"


def kernel_version(tree):
    values = {}
    for line in (tree / "Makefile").read_text().splitlines():
        match = re.fullmatch(r"(VERSION|PATCHLEVEL|SUBLEVEL|EXTRAVERSION)\s*=\s*(.*)", line)
        if match:
            values[match[1]] = match[2]
    return ".".join(values[k] for k in ["VERSION", "PATCHLEVEL", "SUBLEVEL"]) + values.get("EXTRAVERSION", "")


def audit(args):
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    debian_text = config_text(args.debian_config)
    debian = parse_config(debian_text)
    paths = args.policy or [Path(__file__).resolve().parent.parent / name for name in ("overrides.config", "overrides." + args.toolchain)]
    policy = {}
    policy_text = ""
    for path in paths:
        text = config_text(path)
        policy.update(parse_config(text))
        policy_text += text + "\n"
    report = {"debian_input": {"path": str(args.debian_config), "sha256": sha(debian_text.encode())},
              "debian_header": [line for line in debian_text.splitlines()[:8] if "Kernel Configuration" in line],
              "policy_inputs": [{"path": str(path), "sha256": sha(path.read_bytes())} for path in paths],
              "semantics": "Declared policy differs from Debian; absent symbols are not assumed disabled; metadata is not policy."}
    required = parse_config(config_text(args.required_intent))
    report["required_intent"] = {"input": str(args.required_intent), "sha256": sha(args.required_intent.read_bytes()),
                                 "native_debian": required_audit(required, debian, policy)}
    (output / "policy-declared-vs-debian.diff").write_text(delta(debian, policy, policy.keys(), True))
    if args.upstream_config:
        upstream_text = config_text(args.upstream_config)
        (output / "debian-vs-upstream.raw.diff").write_text(delta(parse_config(upstream_text), debian))
        report["upstream_input"] = {"path": str(args.upstream_config), "sha256": sha(upstream_text.encode())}
        report["upstream_comparison"] = "RAW: caller must establish matching version/architecture/toolchain; not implied native by this helper"
    if args.our_config:
        ours = parse_config(config_text(args.our_config))
        (output / "our-current-vs-debian.raw.diff").write_text(delta(debian, ours))
        (output / "our-current-declared-policy-vs-debian.diff").write_text(delta(debian, ours, policy.keys(), True))
        report["our_current_comparison"] = "RAW cross-version/toolchain audit, not attribution of all differences to policy"
    if args.kernel_tree:
        if args.work_dir is None:
            raise ValueError("--kernel-tree requires an explicit --work-dir")
        tree, work = args.kernel_tree.resolve(), args.work_dir.resolve()
        if tree == work or tree in work.parents:
            raise ValueError("Work directory must be outside the kernel source tree")
        if work.exists() and any(work.iterdir()):
            raise ValueError("Work directory must be new or empty; no existing outputs are overwritten")
        work.mkdir(parents=True, exist_ok=True)
        env = os.environ.copy()
        # Avoid an inherited KCONFIG_CONFIG redirecting writes into a source/host config.
        env["KCONFIG_CONFIG"] = ".config"
        def make(name, target, seed=None):
            build = work / name
            build.mkdir()
            if seed is not None:
                (build / ".config").write_text(seed)
            command = ["make", "-C", str(tree), f"O={build}", "ARCH=x86"]
            if args.toolchain == "llvm":
                command.append("LLVM=1")
            command.append(target)
            with (work / (name + ".log")).open("w") as log:
                subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
            result = (build / ".config").read_text()
            (output / (name + ".config.xz")).write_bytes(lzma.compress(result.encode()))
            return parse_config(result), result
        upstream, _ = make("target-upstream", "x86_64_defconfig")
        projected, projected_text = make("target-debian", "olddefconfig", debian_text)
        custom, _ = make("target-policy", "olddefconfig", merged_config(projected_text, policy_text))
        (output / "target-debian-vs-upstream.diff").write_text(delta(upstream, projected, exclude_metadata=True))
        (output / "target-policy-vs-debian.diff").write_text(delta(projected, custom, exclude_metadata=True))
        (output / "target-toolchain-metadata.diff").write_text(delta(debian, projected, [k for k in debian.keys() | projected.keys() if METADATA.fullmatch(k)]))
        (output / "target-policy-unfulfilled.diff").write_text(delta(policy, custom, policy.keys(), True))
        (output / "target-required-intent-unfulfilled.diff").write_text(delta(required, custom, required.keys(), True))
        report["required_intent"]["target_policy"] = required_audit(required, custom, policy)
        report["target"] = {"tree": str(tree), "version": kernel_version(tree), "toolchain": args.toolchain,
                            "declared_revision": args.kernel_revision,
                            "source_fingerprints": {name: sha((tree / name).read_bytes()) for name in ("Makefile", "Kconfig")},
                            "semantics": "PROJECTED: upstream -> Debian normalized on target -> declared policy normalized on same target; not native Debian defaults",
                            "work_dir": str(work)}
        result = subprocess.run(["git", "-C", str(tree), "rev-parse", "HEAD"], capture_output=True, text=True)
        report["target"]["git_head_if_available"] = result.stdout.strip() if result.returncode == 0 else None
        report["target"]["tool_versions"] = {}
        for tool in ("make", "clang" if args.toolchain == "llvm" else "gcc", "ld.lld" if args.toolchain == "llvm" else "ld", "rustc", "bindgen", "pahole"):
            try:
                result = subprocess.run([tool, "--version"], capture_output=True, text=True)
                report["target"]["tool_versions"][tool] = (result.stdout or result.stderr).splitlines()[0] if result.returncode == 0 else "unavailable"
            except FileNotFoundError:
                report["target"]["tool_versions"][tool] = "unavailable"
    report["output_sha256"] = {path.name: sha(path.read_bytes()) for path in sorted(output.iterdir())
                               if path.is_file() and path.name != "audit.json"}
    dump(output / "audit.json", report)
    print(output / "audit.json")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    p = commands.add_parser("fetch", help="Retrieve latest or replay a pinned receipt")
    p.add_argument("--suite", choices=["unstable", "experimental", "both"], default="both")
    p.add_argument("--cache-dir", required=True, type=Path)
    p.add_argument("--output-dir", required=True, type=Path)
    p.add_argument("--offline", action="store_true", help="Replay existing output receipts and verified cached bytes")
    p.add_argument("--inspect-only", action="store_true", help="Pin metadata/selection without downloading package")
    p.add_argument("--keyring", type=Path, default=DEFAULT_KEYRING)
    p.add_argument("--tls-only", action="store_true", help="Explicitly waive archive signatures; receipt labels weaker trust")
    p.set_defaults(run=fetch)
    p = commands.add_parser("diff", help="Audit declared policy; optionally evaluate layers in a user-managed kernel tree")
    p.add_argument("--debian-config", required=True, type=Path)
    p.add_argument("--output-dir", required=True, type=Path)
    p.add_argument("--policy", action="append", type=Path, help="Ordered policy fragments; defaults to common+LLVM in copied bundle")
    p.add_argument("--required-intent", type=Path, default=Path(__file__).resolve().with_name("required-intent.config"),
                   help="Audit expectations only; never silently added to policy")
    p.add_argument("--our-config", type=Path)
    p.add_argument("--upstream-config", type=Path)
    p.add_argument("--kernel-tree", type=Path)
    p.add_argument("--kernel-revision", help="Optional caller-supplied pin for an exported source tree; recorded, not verified")
    p.add_argument("--work-dir", type=Path)
    p.add_argument("--toolchain", choices=["llvm", "gcc"], default="llvm")
    p.set_defaults(run=audit)
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
