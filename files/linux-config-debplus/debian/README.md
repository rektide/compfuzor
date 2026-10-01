# Debian config retrieval and the two configuration layers

This domain keeps **Debian versus upstream** separate from **our declared policy versus Debian**. Full configs are compressed evidence, not the primary explanation. It does not replace the bundle's historical seed or [policy fragments](/files/linux-config-debplus/overrides.config).

## First checkpoint: October 1, 2026

| Suite | Authenticated metadata result | Config source |
|---|---|---|
| unstable | **7.2.8-1**, generic amd64 | `linux-headers-7.2.8+deb14-amd64`, 1,751,872-byte `.deb`; only `usr/src/linux-headers-7.2.8+deb14-amd64/.config` is read |
| experimental | **No Linux packages in the current amd64 index** | No config, no implicit fallback to unstable |

Both suites' `InRelease` signatures verified using the host Debian archive keyring. Receipts pin each signed release, package index and selected package SHA256; package bytes are verified **before** invoking `ar` or reading the intended regular config member. No package installation or system apt-list writes occur.

Receipts: [unstable](/files/linux-config-debplus/debian/snapshots/unstable/receipt.json), [experimental](/files/linux-config-debplus/debian/snapshots/experimental/receipt.json). Experimental absence is useful leading-edge information: the helper queries experimental independently every time, rather than assuming it is always ahead of unstable.

### Read the useful differences first

- [Declared policy versus native Debian](/files/linux-config-debplus/debian/snapshots/unstable/audit-7.3/policy-declared-vs-debian.diff): **33 entries** from common+LLVM declarations only. `<absent>` means not represented in that full config, not necessarily disabled. GCC-produced configs do not expose several Clang choices; these availability differences are not claims that Debian deliberately chose a different Clang policy.
- [Debian versus upstream, both projected onto 7.3](/files/linux-config-debplus/debian/snapshots/unstable/audit-7.3/target-debian-vs-upstream.diff): **7,468 entries**, mostly Debian's broad hardware/modules/subsystem coverage. This is the first layer; it is not our custom policy.
- [Our effective policy atop projected Debian](/files/linux-config-debplus/debian/snapshots/unstable/audit-7.3/target-policy-vs-debian.diff): **47 entries**, including dependency consequences. Built-in filesystems, BBR, reduced hardening, host-native CPU/TSX-off, LZ4 hibernation and pstore frontend choices dominate.
- [Unfulfilled policy](/files/linux-config-debplus/debian/snapshots/unstable/audit-7.3/target-policy-unfulfilled.diff): **empty**; every declared common+LLVM symbol was fulfilled on this host.
- [Toolchain metadata](/files/linux-config-debplus/debian/snapshots/unstable/audit-7.3/target-toolchain-metadata.diff): kept separate, not attributed to deliberate custom policy.

Debian already enables Rust and the panic QR screen here; restating them in our durable fragment does not make them a Debian difference. Pstore console/pmsg/ftrace and built-in ramoops do differ.

### Required intent: fulfilled, but five expectations still rely on inheritance

[required-intent.config](/files/linux-config-debplus/debian/required-intent.config) is an **audit-only expectation list**. It is never automatically merged into the configuration. The audit JSON separately reports fulfillment and whether a value is explicitly declared. All nine Rust/debug/QR expectations are fulfilled in fresh unstable and the effective 7.3 projection; [target-required-intent-unfulfilled.diff](/files/linux-config-debplus/debian/snapshots/unstable/audit-7.3/target-required-intent-unfulfilled.diff) is empty.

The current common fragment already declares Rust, panic enablement, the `qr_code` screen and QR enablement. It does **not** declare the QR URL/version or debug/BTF choices. Proposed small additions, **pending parent approval**, are:

```config
CONFIG_DRM_PANIC_SCREEN_QR_CODE_URL="https://deb.li/panic#"
CONFIG_DRM_PANIC_SCREEN_QR_VERSION=40
CONFIG_DEBUG_KERNEL=y
# CONFIG_DEBUG_INFO_NONE is not set
CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT=y
CONFIG_DEBUG_INFO_BTF=y
CONFIG_DEBUG_INFO_BTF_MODULES=y
```

`DEBUG_INFO` itself is a derived, promptless bool: selecting the DWARF choice preserves it correctly instead of pretending it is independently selectable. BTF additionally depends on inherited `BPF_SYSCALL`, valid pahole, module support for module BTF, and compatible debug-info options. The evaluator reports losses rather than installing tools or copying the entire old config. No shared overrides were changed by this slice.

[Running 7.1 versus native Debian 7.2.8, raw](/files/linux-config-debplus/debian/snapshots/unstable/audit-running-7.1/our-current-vs-debian.raw.diff) is retained as a separately labeled historical cross-version/toolchain audit; [declared-policy symbols only](/files/linux-config-debplus/debian/snapshots/unstable/audit-running-7.1/our-current-declared-policy-vs-debian.diff) is the pertinent view. Neither is the canonical deliberate policy layer.

**Version distinction:** native Debian is 7.2.8, target upstream is **7.3.0-rc5**, pin `551c722f40809618230001baccf219193e22fc5a`. The recorded first layer is explicitly **projected**, not a native 7.2.8 upstream comparison. All three evaluated layers use the same clean exported 7.3 source and LLVM invocation. No source tree was modified and only Kconfig/host configuration tools were compiled. [Audit receipt](/files/linux-config-debplus/debian/snapshots/unstable/audit-7.3/audit.json) identifies inputs and source fingerprints. The three generated `.config.xz` files are replay/audit evidence.

## Portable standalone commands

Run from the bundle root (the directory containing `overrides.config`). Paths below are chosen by the operator; neither downloads nor make outputs land in a system source directory.

```sh
# Refresh both suites. Requires python3, dpkg, ar, gpgv and a trusted Debian keyring.
./debian/retrieve.py fetch --suite both \
  --cache-dir "$HOME/.cache/debplus-debian" --output-dir ./debian-latest

# Select/pin metadata without downloading the headers package.
./debian/retrieve.py fetch --inspect-only --suite both \
  --cache-dir "$HOME/.cache/debplus-debian" --output-dir ./debian-inspected

# Replay existing receipts with exclusively pinned cached bytes, including signatures.
./debian/retrieve.py fetch --offline --suite both \
  --cache-dir "$HOME/.cache/debplus-debian" --output-dir ./debian-latest

# Declaration-only audit: no make invocation, no source required.
./debian/retrieve.py diff \
  --debian-config ./debian-latest/unstable/config-7.2.8-1-amd64.xz \
  --output-dir ./debian-policy-audit

# Optional same-target upstream -> projected Debian -> projected policy evaluation.
# --work-dir MUST be new/empty and outside --kernel-tree.
./debian/retrieve.py diff \
  --debian-config ./debian-latest/unstable/config-7.2.8-1-amd64.xz \
  --kernel-tree /path/to/user-managed/clean-linux-export \
  --kernel-revision 551c722f40809618230001baccf219193e22fc5a \
  --work-dir "$HOME/build/debplus-layer-audit" --output-dir ./debian-layer-audit
```

Use the versioned config filename from the receipt after a refresh. The script resolves default policy fragments relative to itself, so copying the entire bundle preserves operation. `--policy PATH` may be repeated to choose ordered declarations; `--toolchain gcc` chooses common+GCC instead. `--our-config` and `--upstream-config` accept plain or `.xz` config evidence and produce explicitly **raw**, potentially cross-version audits. They never turn thousands of inherited/metadata differences into a policy fragment. `--kernel-revision` is caller-provided provenance, not proof of an exported tree's identity.

Package selection uses the `linux-headers-amd64` exact dependency where present; otherwise it chooses the latest indexed generic headers using **Debian version ordering**, never cloud/RT. Experimental can lack a metapackage or all kernel packages. Missing exact dependencies fail rather than selecting an unrelated build. Headers are substantially smaller than image packages and contained the complete config in the observed unstable package. If Debian changes that layout, extraction fails explicitly; this first slice does not invent a source-fragment or image fallback.

The default trust chain requires `gpgv` and `/usr/share/keyrings/debian-archive-keyring.gpg`, replaceable with `--keyring`. Verified signing fingerprints and release expiration (when supplied) are recorded; expired current releases are rejected, while deliberate offline replay accepts old pinned metadata. Signed release evidence is retained as `InRelease.xz` per suite. `--tls-only` is an explicit weaker mode recorded in the receipt; it is not the default. No automatic key download, apt install, git checkout, source fetch, full kernel build, cleanup or pruning is performed. Keep the explicit cache to reproduce pinned receipts offline; receipts/config evidence alone do not contain the complete package indexes. Debian can remove an old package from the live mirror, so retaining cached bytes matters.

## Checks and references

```sh
./debian/test_retrieve.py
```

Ten focused tests cover folded Debian control fields, exact dependency selection, Debian version ordering, cloud/RT exclusion, missing suite packages, broken dependencies, checksum failure, release-index parsing, absent-versus-disabled/metadata semantics, inherited-versus-declared intent, and ordered duplicate-free policy merging. Both real suite retrieval and offline pinned replay passed. An intentionally corrupted pinned package cache was rejected with a SHA256 mismatch before extraction; no config was emitted. The real clean-source projected policy audit fulfilled every declared symbol and every required Rust/debug/QR expectation; Debian normalization reported one expected upstream boolification (`ANDROID_BINDER_IPC=m` no longer valid).

- [Debian unstable primary metadata](https://deb.debian.org/debian/dists/unstable/InRelease) and [experimental metadata](https://deb.debian.org/debian/dists/experimental/InRelease): source of suite/package selection.
- [Preserved running 7.1 baseline](/files/linux-config-debplus/baselines/7.1/README.md): historical exact running config and its upstream audit; distinct from current Debian retrieval.
- [7.3 export/projection evidence](/.test-agent/linux-debplus-7.3/config/README.md): source pin, archive SHA and host toolchain context reused by this independent layer evaluation.

**Proposed next slice:** accept this projected leading-edge comparison or supply a matching upstream 7.2.8 export for a separately labeled native Debian layer. Do not silently treat the projected result as a native-version delta, and do not replace the preserved running configuration based on retrieval alone.
