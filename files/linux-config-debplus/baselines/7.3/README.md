# 7.3 baseline — upstream x86_64_defconfig (provenance)

Reference baseline for the 7.3 slice only; NOT a Debian baseline and NOT a
proposed replacement. The durable Debian-plus host policy remains
`config-debian-plus`. Sibling `../7.1/` (exact original preservation) is owned
by the research agent.

## Target / source / toolchain

| Item | Value |
|---|---|
| Kernel | `7.3.0-rc5` at pin `551c722f40809618230001baccf219193e22fc5a` ("Merge tag 'rtc-7.3-fixes'", `v7.3-rc5-37-g551c722f4080`, baseline tag `v7.3-rc5` = `72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`) |
| Source | clean `git archive` export of the pin (scratch `.test-agent/linux-debplus-7.3/config/source`, 1.8G); archive sha256 `a3279266e0440e924a58255de3bb6378a6b833f587766cd64e1bfacd289c88b3` |
| Toolchain | Debian clang 21.1.8 (`CC_IS_CLANG=y`), ld.lld, rustc 1.101.0-nightly + rust-src (probe `RUST_IS_AVAILABLE=y`), bindgen 0.71.1, pahole 1.30 — same LLVM=1 toolchain as `config-debian-plus` |

## Commands

```
make -C source O=$PWD/output-defconfig LLVM=1 x86_64_defconfig
cp output-defconfig/.config <bundle>/baselines/7.3/config-upstream-defconfig
# roundtrip check:
cp config-upstream-defconfig output-roundtrip/.config
make -C source O=$PWD/output-roundtrip LLVM=1 olddefconfig
diff output-defconfig/.config output-roundtrip/.config   # byte-identical
# audit diff (keys printed WITHOUT the CONFIG_ prefix):
/usr/bin/python3 source/scripts/diffconfig \
    config-debian-plus baselines/7.3/config-upstream-defconfig \
    > baselines/7.3/config-debian-plus-vs-defconfig.diff
```

`config-upstream-defconfig` is the unmodified generated file (5516 lines,
sha256 `0c236fada2c40ab78733de631613db5ae8ea709c69ac3fc853dc919bb401c480`).

## Roundtrip

Saved baseline re-resolves **byte-identical** under a second `LLVM=1
olddefconfig` in a fresh O= dir — the artifact is a fixed point, safe to
re-normalize from.

## Critical audit — config-debian-plus vs defconfig

Diff: 7461 entries = 42 defconfig-only, 5533 debian-plus-only, 1886 changed
(direction: `ours -> defconfig`).

- The **5533 removed + bulk of 1886 changes are the large Debian-derived
  policy** (Debian's driver/filesystem/debug/module coverage carried through
  the 7.1 seed): expected and deliberate to keep — this is exactly the
  Debian-plus delta over a lean upstream baseline, not drift to be "fixed".
- The **deliberate overrides** are the small loud subset in
  `overrides.config`/`overrides.llvm`; anchor deltas visible in the audit:
  `X86_NATIVE_CPU y->n`, `DEFAULT_TCP_CONG "bbr"->"cubic"`, `RUST y->n`,
  `DRM_AMDGPU m->n`, `PSTORE y->n` (+PSTORE_RAM), `DRM_PANIC y->n`,
  `LKDTM m->n`, `MODULE_SIG y->n`, `PROC_MEM_ALWAYS_FORCE y->n`,
  `WQ_POWER_EFFICIENT_DEFAULT y->n`, `X86_INTEL_TSX_MODE_OFF y->n`,
  `BTRFS_FS/XFS_FS y->n`, `DEBUG_INFO(+BTF) y` absent, `RANDOMIZE_BASE
  n->y` (defconfig hardens; our low-hardening host policy is the choice).
- Upstream defconfig already carries `KEXEC/CRASH_DUMP/PROC_VMCORE=y`,
  `HIBERNATION=y`, `LTO_NONE=y`, `EXT4_FS=y`, `CRYPTO_LZ4=y` — those do not
  differ.
- The 42 defconfig-only entries are mostly forced/internal symbols
  (`X86_REQUIRED/DISABLED_FEATURE_*`, `ARCH_*`, `NOINSTR_VALIDATION`) plus
  real lean-baseline items we drop (NFS-root/IP_PNP, MD_AUTODETECT,
  PM_TRACE, EARLY_PRINTK_USB, `RANDOMIZE_MEMORY=y`,
  `RANDOMIZE_KSTACK_OFFSET_DEFAULT=n`, `DM_INIT=n`).

No full build was performed; no claim that this is a fresh Debian baseline.
