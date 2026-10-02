# Running 7.1 configuration and upstream-defconfig audit

This is a historical, full-configuration audit of `7.1.0-debplus.1`, **not** a minimal portable policy fragment or the current 7.3 seed. The deliberately maintained policy remains [overrides.config](../../overrides.config) and its compiler-specific companions. The Debian-derived full configuration enables thousands of devices/features beyond upstream's small default configuration; the delta does not identify which differences were deliberate human choices.

## Preserved artifacts

| File | Meaning |
|---|---|
| [config-running.xz](config-running.xz) | xz-compressed exact 295,658-byte copy of `/boot/config-7.1.0-debplus.1`, identical to `/usr/local/src/linux/.config`; no normalization applied. Decompresses byte-identical (SHA-256 verified); mode 0644. |
| [config-upstream-defconfig.xz](config-upstream-defconfig.xz) | Fully expanded upstream `x86_64_defconfig` generated from the 7.1 build base with the audit toolchain, xz-compressed (decode-verified byte-identical). |
| [config-running-vs-defconfig.diff](config-running-vs-defconfig.diff) | Canonical human audit, upstream `scripts/diffconfig` format: baseline → exact saved running configuration. `+`/`-` mean symbol present only in one full config; unprefixed changes show old → new. Not a unified patch. |
| [config-running-vs-defconfig.fragment](config-running-vs-defconfig.fragment) | `diffconfig -m` replay fragment, valid only with this baseline/source and subsequent normalization. It cannot express removal of symbols absent from the target config and includes compiler-generated/read-only values; do not promote it into primary policy. |
| [config-running-normalization.diff](config-running-normalization.diff) | Five observed normalization differences under today's Rust toolchain, exact running config → normalized config. |
| [source-config-inventory.json](source-config-inventory.json) | Selected `/usr/local/src` configs, their hashes, headers, critical values, and symbol comparisons against running 7.1. No key material. |
| [validation.json](validation.json) | Provenance, tool identities, artifact hashes and replay results. |

The running-config SHA-256 (of the decompressed plaintext) is **`0898648962b24943c1d312b30d8cf4fcf959b4a107ee3580692af001c70789d3`**. Baseline and generated audits were captured October 1, 2026, by GPT-6.1 Sol.

Full configurations are stored xz-compressed with the deterministic codec `xz -9 --check=crc64 -T1`; each artifact's compressed and plaintext hashes are recorded in [validation.json](validation.json). Diff, fragment, inventory, and documentation artifacts remain uncompressed. Compression changes storage only — every hash, replay result, and audit claim in this bundle describes the identical plaintext content.

## Source and toolchain provenance

Source is [`8cd9520d35a6c38db6567e97dd93b1f11f185dc6`](https://github.com/torvalds/linux/commit/8cd9520d35a6c38db6567e97dd93b1f11f185dc6), the parent of the locally preserved `987301279ffaf3a6f2eaca7ad7f4a8b7eec3008e` AMDGPU fix used for the 7.1 build. The AMDGPU fix does not alter Kconfig. An exact source export was used; no make command ran in the old in-place source/build directory. Artifact fingerprints and source references are preserved in [validation.json](validation.json).

Use the full commit hash rather than bare `v7.1`: that name is ambiguous among local refs. This is **not** a defconfig generated from the current 7.3 checkout.

- Architecture: `ARCH=x86`, target `x86_64_defconfig`, `LLVM=1`.
- Clang: `Debian clang version 21.1.8 (10)`, matches the saved running config's compiler identity.
- Audit Rust: `rustc 1.101.0-nightly (5c543b0b8 2026-09-29)`, LLVM metadata 23.1.1.
- Saved running Rust metadata: `RUSTC_VERSION=109701`, LLVM 22.1.6; it has no `CONFIG_RUST` or `CONFIG_RUST_IS_AVAILABLE` entry.
- Bindgen: 0.71.1; GNU Make: 4.4.1. No dependencies installed and no kernel compilation/package build performed.

The audit toolchain updates three Rust metadata integers and adds `RUST=n` plus `RUST_IS_AVAILABLE=y` on normalization. Therefore a **byte-exact replay of the original config is neither claimed nor needed**: the original bytes are preserved separately. Future toolchain changes can change the baseline and normalization results.

## Results and meaningful differences

The full audit contains **7,419 symbol differences**: 1,903 changed values, 5,472 symbols present only in the saved running config, and 44 baseline-only symbols. The replay fragment has 7,375 entries. Presence-only differences often arise from dependency-controlled visibility, not separately selected policy.

Examples against the upstream default:

- `DRM_AMDGPU=n → m`, with older AMD GPU support and userptr options enabled.
- `BTRFS_FS=n → y`; broad modular hardware/filesystem coverage beyond the default.
- `HZ=1000 → 250`, with dynamic preemption enabled in the running config.
- `LOCALVERSION_AUTO=y → n`; actual build suffix `-debplus.1` was supplied by the old build command, not `CONFIG_LOCALVERSION` (which is empty).
- `MODULE_SIG=n → y`, sign all modules with SHA-256 and default RSA key location; enforcement is not forced by `CONFIG_MODULE_SIG_FORCE`.
- Debug information and BTF/module BTF enabled instead of the default no-debug-info choice. `LTO_NONE=y`, not ThinLTO, in the running config.

### Which previous configs were actually the same?

- `/usr/local/src/linux/.config` **equals the running `/boot` config exactly**.
- `/usr/local/src/linux/.config.old` **equals `/usr/local/src/linux-config-debplus/config-debian-plus` exactly**: 296,498 bytes, SHA-256 `37f91f777b343b08807872548a91783483f593b0d31f87616ba6b93f6ae81484`. (The byte-exact seed stays stored compressed as [`../../archive/previous-normalization/config-debian-plus.7.1.0.xz`](../../archive/previous-normalization/config-debian-plus.7.1.0.xz); the top-level [`../../config-debian-plus.xz`](../../config-debian-plus.xz) was regenerated on 2026-10-02 for the built-in zswap zstd policy, so it now differs from this seed by the single `CRYPTO_ZSTD m -> y` change. `/usr/local` source files were not modified.) That preserved seed differs from the running configuration by **22 symbol states**, predominantly Rust support/availability, Rust-driven drivers/panic QR options and toolchain metadata. It is not an exact backup of the running config.
- February backups are x86 6.19-rc6/rc7 GCC configs, 410/396 symbol differences from running 7.1. Both remain untouched in the old source tree.
- `.config-greatish` and `/usr/local/src/config-rpi4` are distinct arm64 6.8-rc5 configurations, not this host's running seed.
- `/usr/local/src/config-6.15` is actually headed x86 **6.14.0-rc6**, with GCC 14 metadata. `config-rax120*` are OpenWrt configs, not candidates for host-kernel replacement.

The inventory is a scoped audit, not a recursive scan of all repositories. Historical backups other than the running config are recorded, not newly copied into this baseline bundle.

## Reproduce and validate without touching the old build

From the repository root, choose a new scratch directory; never use `/usr/local/src/linux` as the make working directory or output directory. The stored full configurations are xz-compressed, so decompress them into scratch first:

```sh
mkdir -p .test-agent/linux-config-preservation-replay/source
git -C /usr/local/src/linux archive 8cd9520d35a6c38db6567e97dd93b1f11f185dc6 |
  tar -x -C .test-agent/linux-config-preservation-replay/source

mkdir -p .test-agent/linux-config-preservation-replay/baseline
xz -dc files/linux-config-debplus/baselines/7.1/config-running.xz \
  > .test-agent/linux-config-preservation-replay/baseline/config-running
xz -dc files/linux-config-debplus/baselines/7.1/config-upstream-defconfig.xz \
  > .test-agent/linux-config-preservation-replay/baseline/config-upstream-defconfig
# plaintext hashes must match validation.json:
sha256sum .test-agent/linux-config-preservation-replay/baseline/*

make -C .test-agent/linux-config-preservation-replay/source \
  O="$PWD/.test-agent/linux-config-preservation-replay/default" ARCH=x86 LLVM=1 x86_64_defconfig

python3 .test-agent/linux-config-preservation-replay/source/scripts/diffconfig \
  .test-agent/linux-config-preservation-replay/default/.config \
  .test-agent/linux-config-preservation-replay/baseline/config-running
```

For replay, use the **preserved baseline** (the decompressed plaintext above) rather than a newly generated baseline if testing the committed fragment. Run the merge script from scratch so its temporary files stay there:

```sh
mkdir -p .test-agent/linux-config-preservation-replay/reconstructed
(
  cd .test-agent/linux-config-preservation-replay
  source/scripts/kconfig/merge_config.sh -m -O reconstructed \
    baseline/config-upstream-defconfig \
    ../../files/linux-config-debplus/baselines/7.1/config-running-vs-defconfig.fragment
)
make -C .test-agent/linux-config-preservation-replay/source \
  O="$PWD/.test-agent/linux-config-preservation-replay/reconstructed" ARCH=x86 LLVM=1 olddefconfig

mkdir -p .test-agent/linux-config-preservation-replay/normalized-running
cp .test-agent/linux-config-preservation-replay/baseline/config-running \
  .test-agent/linux-config-preservation-replay/normalized-running/.config
make -C .test-agent/linux-config-preservation-replay/source \
  O="$PWD/.test-agent/linux-config-preservation-replay/normalized-running" ARCH=x86 LLVM=1 olddefconfig
python3 .test-agent/linux-config-preservation-replay/source/scripts/diffconfig \
  .test-agent/linux-config-preservation-replay/normalized-running/.config \
  .test-agent/linux-config-preservation-replay/reconstructed/.config
```

**Validated result:** the last command reports zero symbol differences. Comparing reconstruction directly against the decompressed `config-running` gives exactly the five recorded normalization differences: three Rust metadata changes, two newly visible entries. No original explicit policy-valued symbol differs after excluding those three toolchain metadata integers.

## Signing material: likely automatic, still preserved in place

The v7.1 [`certs/Makefile:39–67`](https://github.com/torvalds/linux/blob/8cd9520d35a6c38db6567e97dd93b1f11f185dc6/certs/Makefile#L39-L67) automatically generates `certs/signing_key.pem` with OpenSSL when the default key path is selected, and creates `x509.genkey` from the default template if missing. The saved config enables `MODULE_SIG_ALL=y` and selects this default path. The existing PEM dates to February 25, before the August build. **Automatic creation during an earlier kernel build is plausible; deliberate human creation is not required.** Its precise historical generation event is not established.

No private key contents were printed or copied, and no signing files were modified. The default key and certificate can be relevant to signing continuity or systems/modules that trust that certificate, even though `MODULE_SIG_FORCE=n`. Config values alone do not prove Secure Boot, lockdown, enrolled trust or external dependencies absent. Do not delete the key merely because its generation was automatic. If later preservation of keys is authorized, use a separate private archive with permission preservation, never this public configuration bundle.
