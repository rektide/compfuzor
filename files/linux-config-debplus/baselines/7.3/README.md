# 7.3 baseline — upstream x86_64_defconfig (provenance)

Reference baseline for the 7.3 slice only; NOT a Debian baseline and NOT a
proposed replacement. The durable Debian-plus host policy remains
`config-debian-plus` (committed xz-compressed as `../config-debian-plus.xz`;
decompress into scratch to read it). Sibling `../7.1/` (exact original
preservation) is owned by the research agent.

Full configurations in this bundle are stored with the deterministic codec
`xz -9 --check=crc64 -T1`, mode 0644; each decompresses byte-identical to its
original (SHA-256 verified, hashes registered in `../7.1/validation.json`).
`.diff`/`.fragment` artifacts stay plain. Decompress into scratch — never into
`/usr/local` — before any merge, eval, or diff.

## Target / source / toolchain

| Item | Value |
|---|---|
| Kernel | `7.3.0-rc5` at pin `551c722f40809618230001baccf219193e22fc5a` ("Merge tag 'rtc-7.3-fixes'", `v7.3-rc5-37-g551c722f4080`, baseline tag `v7.3-rc5` = `72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`) |
| Source | clean `git archive` export of the pin (scratch `.test-agent/linux-debplus-7.3/config/source`, 1.8G); archive sha256 `a3279266e0440e924a58255de3bb6378a6b833f587766cd64e1bfacd289c88b3` |
| Toolchain | Debian clang 21.1.8 (`CC_IS_CLANG=y`), ld.lld, rustc 1.101.0-nightly + rust-src (probe `RUST_IS_AVAILABLE=y`), bindgen 0.71.1, pahole 1.30 — same LLVM=1 toolchain as `config-debian-plus` |

## Commands

Generation record (when `config-debian-plus` and the defconfig were still
plaintext at these paths):

```
make -C source O=$PWD/output-defconfig LLVM=1 x86_64_defconfig
cp output-defconfig/.config baselines/7.3/config-upstream-defconfig
/usr/bin/python3 source/scripts/diffconfig \
    baselines/7.3/config-upstream-defconfig config-debian-plus \
    > baselines/7.3/config-debian-plus-vs-defconfig.diff
/usr/bin/python3 source/scripts/diffconfig -m \
    baselines/7.3/config-upstream-defconfig config-debian-plus \
    > baselines/7.3/defconfig-to-debian-plus.fragment
# diffconfig -m omits baseline-only keys (42 here); negate them explicitly:
grep '^-' <full diff above> | sed 's/^-//' | awk '{print $1}' \
    | sed 's/^/# CONFIG_/; s/$/ is not set/' >> baselines/7.3/defconfig-to-debian-plus.fragment
```

Reproduction today — decompress the committed `.xz` artifacts into scratch
first, then run the same merge/eval/diff against the plaintext copies:

```
mkdir -p .test-agent/linux-debplus-7.3/plain
xz -dc baselines/7.3/config-upstream-defconfig.xz \
    > .test-agent/linux-debplus-7.3/plain/config-upstream-defconfig
xz -dc config-debian-plus.xz \
    > .test-agent/linux-debplus-7.3/plain/config-debian-plus
# plaintext sha256 must match ../7.1/validation.json (compression registry):
sha256sum .test-agent/linux-debplus-7.3/plain/*

/usr/bin/python3 source/scripts/diffconfig \
    .test-agent/linux-debplus-7.3/plain/config-upstream-defconfig \
    .test-agent/linux-debplus-7.3/plain/config-debian-plus
```

`config-upstream-defconfig` is the unmodified generated file (5516 lines);
stored as `config-upstream-defconfig.xz` (decode-verified). sha256
`0c236fada2c40ab78733de631613db5ae8ea709c69ac3fc853dc919bb401c480` is the
decompressed plaintext content hash.
The fixedpoint roundtrip (a second `olddefconfig` on the baseline is
byte-identical) only proves baseline stability — see next section for the
verification that actually matters here.

## Fragment: defconfig -> config-debian-plus reconstruction

`defconfig-to-debian-plus.fragment` = `diffconfig -m` of baseline→ours
(7419 entries: differing values as `CONFIG_…=…`, our explicit not-set
negations as `# CONFIG_… is not set`) **plus 42 explicit negations** of
baseline-only keys that `diffconfig -m` cannot express (without them, a
merge would keep the baseline's `=y` for keys like `IP_PNP_BOOTP`,
`MD_AUTODETECT`, `RANDOMIZE_MEMORY`).

Roundtrip verification (the delta reconstruction, not the fixedpoint):

```
sh source/scripts/kconfig/merge_config.sh -m -O output-fragment \
    .test-agent/linux-debplus-7.3/plain/config-upstream-defconfig \
    baselines/7.3/defconfig-to-debian-plus.fragment
make -C source O=$PWD/output-fragment LLVM=1 olddefconfig
/usr/bin/python3 source/scripts/diffconfig output-fragment/.config \
    .test-agent/linux-debplus-7.3/plain/config-debian-plus
```

Result: **0 differing entries** — baseline + fragment resolved with the same
`LLVM=1 olddefconfig` reproduces `config-debian-plus` exactly at the keymap
level. No normalization differences to explain: both sides come from the same
tree, toolchain, and resolution step, and every key that differs from the
baseline is captured in the fragment (including `# … is not set` lines, which
`olddefconfig` honors for prompt symbols and ignores for promptless/forced
symbols — which resolve to the same values our config carries).

Note `merge_config.sh -m` does NOT verify fragments against Kconfig (it stops
before the make step); the verification above is the separate olddefconfig
resolution plus explicit keymap diff.

## Critical audit — defconfig vs config-debian-plus

`config-debian-plus-vs-defconfig.diff` direction: **baseline → ours**
(`diffconfig config-upstream-defconfig config-debian-plus`); keys are printed
WITHOUT the `CONFIG_` prefix. 7461 entries = 5533 added (ours-only), 42
removed (baseline-only), 1886 changed.

- The **5533 added + bulk of the 1886 changes are the large Debian-derived
  policy** (Debian's driver/filesystem/debug/module coverage carried through
  the 7.1 seed): expected and deliberate to keep — this is exactly the
  Debian-plus delta over a lean upstream baseline, not drift to be "fixed".
- The **deliberate overrides** are the small loud subset in
  `overrides.config`/`overrides.llvm`; anchor deltas: `X86_NATIVE_CPU y->n`,
  `DEFAULT_TCP_CONG "bbr"->"cubic"`, `RUST y->n`, `DRM_AMDGPU m->n`,
  `PSTORE y->n` (+PSTORE_RAM), `DRM_PANIC y->n`, `LKDTM m->n`,
  `MODULE_SIG y->n`, `PROC_MEM_ALWAYS_FORCE y->n`,
  `WQ_POWER_EFFICIENT_DEFAULT y->n`, `X86_INTEL_TSX_MODE_OFF y->n`,
  `BTRFS_FS/XFS_FS y->n`, `DEBUG_INFO(+BTF) y` absent from baseline,
  `RANDOMIZE_BASE n->y` (baseline hardens; our low-hardening host policy is
  the choice).
- Upstream defconfig already carries `KEXEC/CRASH_DUMP/PROC_VMCORE=y`,
  `HIBERNATION=y`, `LTO_NONE=y`, `EXT4_FS=y`, `CRYPTO_LZ4=y` — those do not
  differ.
- The 42 baseline-only entries are mostly forced/internal symbols
  (`X86_REQUIRED/DISABLED_FEATURE_*`, `ARCH_*`, `NOINSTR_VALIDATION`) plus
  real lean-baseline items we drop (NFS-root/IP_PNP, MD_AUTODETECT,
  PM_TRACE, EARLY_PRINTK_USB, `RANDOMIZE_MEMORY=y`,
  `RANDOMIZE_KSTACK_OFFSET_DEFAULT=n`, `DM_INIT=n`).

No full build was performed; no claim that this is a fresh Debian baseline.
