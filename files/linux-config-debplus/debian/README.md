# Debian config retrieval and the two configuration layers

This domain keeps **Debian versus upstream** separate from **our declared policy versus Debian**. Full configs are compressed evidence, not the primary explanation. It does not replace the bundle's historical seed or [policy fragments](../overrides.config).

## First checkpoint: October 1, 2026

| Suite | Authenticated metadata result | Config source |
|---|---|---|
| unstable | **7.2.8-1**, generic amd64 | `linux-headers-7.2.8+deb14-amd64`, 1,751,872-byte `.deb`; only `usr/src/linux-headers-7.2.8+deb14-amd64/.config` is read |
| experimental | **No Linux packages in the current amd64 index** | No config, no implicit fallback to unstable |

Both suites' `InRelease` signatures verified using the host Debian archive keyring. Receipts pin each signed release, package index and selected package SHA256; package bytes are verified **before** invoking `ar` or reading the intended regular config member. No package installation or system apt-list writes occur.

Receipts: [unstable](snapshots/unstable/receipt.json), [experimental](snapshots/experimental/receipt.json). Experimental absence is useful leading-edge information: the helper queries experimental independently every time, rather than assuming it is always ahead of unstable.

An additional, bounded check of experimental's **signed source index** found no `linux` source package either. [Source-index receipt](snapshots/experimental/source-index-receipt.json) records the authenticated index URL, checksum and absence result; [compressed source index](snapshots/experimental/Sources.xz) preserves the input. This is a source-version clue check, not a binary-config fallback. No source package was downloaded or reconstructed, and the retrieval helper's interface is unchanged.

### Read the useful differences first

- [Declared policy versus native Debian](snapshots/unstable/audit-7.3/policy-declared-vs-debian.diff): **36 entries** from common+LLVM declarations only. `<absent>` means not represented in that full config, not necessarily disabled. GCC-produced configs do not expose several Clang choices; these availability differences are not claims that Debian deliberately chose a different Clang policy. The newest entry is `CRYPTO_ZSTD m -> y`: Debian ships the algorithm modular while our policy builds it in for early-boot zswap.
- [Debian versus upstream, both projected onto 7.3](snapshots/unstable/audit-7.3/target-debian-vs-upstream.diff): **7,468 entries**, mostly Debian's broad hardware/modules/subsystem coverage. This is the first layer; it is not our custom policy.
- [Our effective policy atop projected Debian](snapshots/unstable/audit-7.3/target-policy-vs-debian.diff): **50 entries**, including dependency consequences and two standalone-build normalizations. Built-in filesystems, BBR, reduced hardening, host-native CPU/TSX-off, LZ4 hibernation, built-in zswap zstd and pstore frontend choices dominate.
- [Unfulfilled policy](snapshots/unstable/audit-7.3/target-policy-unfulfilled.diff): **empty**; every declared common+LLVM symbol was fulfilled on this host.
- [Toolchain metadata](snapshots/unstable/audit-7.3/target-toolchain-metadata.diff): kept separate, not attributed to deliberate custom policy.

Debian already enables Rust and the panic QR screen here; restating them in our durable fragment does not make them a Debian difference. Pstore console/pmsg/ftrace and built-in ramoops do differ.

### Required intent: approved declarations, verified effective behavior

[required-intent.config](required-intent.config) is an **audit-only expectation list**. It is never automatically merged into the configuration. The audit JSON separately reports fulfillment and whether a value is explicitly declared or derived from a declared selectable choice. All nine Rust/debug/QR expectations are fulfilled in fresh unstable and the effective 7.3 projection. Two additional expectations normalize standalone build metadata; all eleven expectations are fulfilled in our projection, and [target-required-intent-unfulfilled.diff](snapshots/unstable/audit-7.3/target-required-intent-unfulfilled.diff) is empty.

The parent approved and committed seven small additions to [overrides.config](../overrides.config) in `5d5edbc0`. Alongside the existing Rust, panic enablement, `qr_code` screen and QR enablement declarations, the common fragment now explicitly contains:

```config
CONFIG_DRM_PANIC_SCREEN_QR_CODE_URL="https://deb.li/panic#"
CONFIG_DRM_PANIC_SCREEN_QR_VERSION=40
CONFIG_DEBUG_KERNEL=y
# CONFIG_DEBUG_INFO_NONE is not set
CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT=y
CONFIG_DEBUG_INFO_BTF=y
CONFIG_DEBUG_INFO_BTF_MODULES=y
```

`DEBUG_INFO` itself is a derived, promptless bool: selecting the declared DWARF choice preserves it correctly instead of pretending it is independently selectable. The receipt labels this expectation as derived from the explicit debug-information choice; the other ten expectations are directly declared. BTF additionally depends on inherited `BPF_SYSCALL`, valid pahole, module support for module BTF, and compatible debug-info options. The evaluator reports losses rather than installing tools or copying the entire old config.

The projected audit was rerun after approval, with refreshed policy hashes and output receipts. The seven intent declarations did not change effective behavior because Debian already supplied their values. A subsequent standalone-build review added two actual differences:

```config
CONFIG_MODULE_SIG_KEY="certs/signing_key.pem"
CONFIG_BUILD_SALT=""
```

Debian's `output/signing_key.pem` is supplied by its package build machinery,
not a plain upstream build. The upstream default path permits normal key
generation at build time; no key is included or copied by this policy. Clearing
the old Debian ABI build salt avoids carrying `7.2.8+deb14-amd64` into a 7.3
build. The final effective delta is **50 symbols**: the original 47 plus these
two build normalizations plus the zswap zstd declaration (`CRYPTO_ZSTD=y`,
added in `4b254ff1`). Every declaration and required expectation is
fulfilled. On 2026-10-02 the main compressed saved configuration was
regenerated so the saved artifact itself picks up the zstd declaration; that
single symbol is the only change the regeneration made, and it had already
carried these normalization values unchanged.

[Running 7.1 versus native Debian 7.2.8, raw](snapshots/unstable/audit-running-7.1/our-current-vs-debian.raw.diff) is retained as a separately labeled historical cross-version/toolchain audit; [declared-policy symbols only](snapshots/unstable/audit-running-7.1/our-current-declared-policy-vs-debian.diff) is the pertinent view. Neither is the canonical deliberate policy layer. Its policy-input hashes were also refreshed after approval.

**Version distinction:** native Debian is 7.2.8, target upstream is **7.3.0-rc5**, pin `551c722f40809618230001baccf219193e22fc5a`. The recorded first layer is explicitly **projected**, not a native 7.2.8 upstream comparison. All three evaluated layers use the same clean exported 7.3 source and LLVM invocation. No source tree was modified and only Kconfig/host configuration tools were compiled. [Audit receipt](snapshots/unstable/audit-7.3/audit.json) identifies inputs and source fingerprints. The three generated `.config.xz` files are replay/audit evidence.

Source provenance is recorded here directly rather than depending on a gitignored scratch document:

| Evidence | Value |
|---|---|
| Declared upstream pin | [`551c722f40809618230001baccf219193e22fc5a`](https://github.com/torvalds/linux/commit/551c722f40809618230001baccf219193e22fc5a) |
| Recorded original export tar SHA256 | `a3279266e0440e924a58255de3bb6378a6b833f587766cd64e1bfacd289c88b3` |
| Evaluated `Makefile` SHA256 | `de7a0fa8e0a6fafc1cc63949ad3de4aa0d1b19f05b04d2afbd7f107fa3053e0b` |
| Evaluated `Kconfig` SHA256 | `5262073fc9c710d13e6940d857ffe72f850702db12c068bbb4041d8ca9555e5f` |
| Kernel Git HEAD | `null`: the evaluated tree is a plain export, not a Git toplevel |

The helper reports a Git HEAD only when the physical Git toplevel equals the supplied kernel tree. It never attributes the containing bundle repository's HEAD to a nested source export. The caller-supplied revision and recorded original tar digest are provenance labels; the helper independently fingerprints the evaluated `Makefile` and `Kconfig`, not the entire source tree. Tool versions are retained in the receipt.

## Portable standalone commands

Run from the bundle root (the directory containing `overrides.config`). Paths below are chosen by the operator; neither downloads nor make outputs land in a system source directory.

```sh
# Refresh both suites. Requires Node.js, xz, dpkg, ar, gpgv and a trusted Debian keyring.
./debian/retrieve.ts fetch --suite both \
  --cache-dir "$HOME/.cache/debplus-debian" --output-dir ./debian-latest

# Select/pin metadata without downloading the headers package.
./debian/retrieve.ts fetch --inspect-only --suite both \
  --cache-dir "$HOME/.cache/debplus-debian" --output-dir ./debian-inspected

# Replay existing receipts with exclusively pinned cached bytes, including signatures.
./debian/retrieve.ts fetch --offline --suite both \
  --cache-dir "$HOME/.cache/debplus-debian" --output-dir ./debian-latest

# Declaration-only audit: no make invocation, no source required.
./debian/retrieve.ts diff \
  --debian-config ./debian-latest/unstable/config-7.2.8-1-amd64.xz \
  --output-dir ./debian-policy-audit

# Optional same-target upstream -> projected Debian -> projected policy evaluation.
# --work-dir MUST be new/empty and outside --kernel-tree.
./debian/retrieve.ts diff \
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
./debian/test-retrieve.ts
```

Twelve focused tests cover folded Debian control fields, exact dependency selection, Debian version ordering, cloud/RT exclusion, missing suite packages, broken dependencies, checksum failure, release-index parsing, absent-versus-disabled/metadata semantics, inherited-versus-declared intent, derived debug-info intent, ordered duplicate-free policy merging, and Git provenance. The latter creates a real temporary parent repository and verifies that a nested plain export reports no HEAD while the actual toplevel and its physical symlink alias do. Both real suite retrieval and offline pinned replay passed. An intentionally corrupted pinned package cache was rejected with a SHA256 mismatch before extraction; no config was emitted. The refreshed clean-source projected policy audit fulfilled every declared symbol and every required Rust/debug/QR expectation; Debian normalization reported one expected upstream boolification (`ANDROID_BINDER_IPC=m` no longer valid).

- [Debian unstable primary metadata](https://deb.debian.org/debian/dists/unstable/InRelease) and [experimental metadata](https://deb.debian.org/debian/dists/experimental/InRelease): source of suite/package selection.
- [Preserved running 7.1 baseline](../baselines/7.1/README.md): historical exact running config and its upstream audit; distinct from current Debian retrieval.
- [Projected 7.3 audit receipt](snapshots/unstable/audit-7.3/audit.json): source fingerprints, policy hashes, tool versions and the distinction between declarations and effective behavior.

**Remaining optional comparison:** supply a matching upstream 7.2.8 export for a separately labeled native Debian layer. Do not silently treat the projected result as a native-version delta, and do not replace the preserved running configuration based on retrieval alone.
