# Linux Debian-plus configuration

This bundle restores this machine's custom kernel configuration, AMDGPU
minimum-power-cap override, and Debian package build recipe. It lives separately
from the Linux checkout and does not contain a kernel build.

## Target and ownership

The current target is the **latest 7.3 development snapshot checked on
2026-10-01**: [`551c722f4080`](https://github.com/torvalds/linux/commit/551c722f40809618230001baccf219193e22fc5a),
dated 2026-09-29. Its release baseline is `v7.3-rc5` (2026-09-27); **this is
not a final 7.3 release**. The revision is pinned rather than following a moving
branch during configuration or validation.

Compfuzor owns the deployable files in `files/linux-config-debplus/` through
`linux-config-debplus.src.pb`. Running the playbook copies them to
`/usr/local/src/linux-config-debplus` by default, backing up changed declared
files. It does **not** fetch or replace the Linux checkout, copy its `.config`,
apply the hotfix, compile, install packages, change boot arguments, or reboot.
Existing `.git`/`.jj` metadata and undeclared files are left alone.

From the compfuzor checkout:

```sh
ansible-playbook -i 'localhost,' -c local linux-config-debplus.src.pb
```

For isolated staging, redirect both the bundle and standard etc furniture:

```sh
ansible-playbook -i 'localhost,' -c local linux-config-debplus.src.pb \
  -e DIR="$PWD/.test-agent/linux-debplus/stage" \
  -e ETCS_DIR="$PWD/.test-agent/linux-debplus/etc"
```

Overriding `DIR` alone still creates `/etc/opt/linux-config-debplus` for the
standard `etc` symlink. Deployment and kernel modification are separate actions.

## Files

- `config-debian-plus.xz` preserves the complete generated kernel configuration.
  The diffs and policy fragments are the useful review surface; decompress the
  snapshot only when a full configuration is needed.
- `overrides.config` is the shorter list of deliberate changes from Debian's
  configuration that apply to every compiler.
- `overrides.llvm` selects the current Clang/LLVM optimization policy.
- `overrides.gcc` selects the GCC/binutils fallback policy.
- [DEBIAN.md](DEBIAN.md) documents configuration, packaging, installation,
  symbols, reproducibility, and alternate build flows.
- `hotfixes/amdgpu-power.sh` reapplies the AMDGPU minimum-power-cap source
  change after the Linux checkout is replaced.
- `archive/` contains old inputs and backups. Nothing in the current workflow
  reads it.

## Preserved configs and upstream-default comparisons

### Fresh Debian base, then our changes

[Debian retrieval and layers](debian/README.md) is the useful entry point for
current configuration differences. The helper checks **unstable and
experimental independently**, verifies archive signatures and package
checksums, and saves full inputs only as compressed evidence.

The captured unstable kernel is **7.2.8-1**. Experimental currently has neither
a matching amd64 kernel config nor a `linux` source package. That is recorded
as absence, not replaced with unstable under an experimental label.

The same-target comparison evaluates both inputs on the pinned 7.3 source:

1. [Upstream → projected Debian](debian/snapshots/unstable/audit-7.3/target-debian-vs-upstream.diff):
   Debian's broad driver/module and subsystem choices.
2. [Projected Debian → our policy](debian/snapshots/unstable/audit-7.3/target-policy-vs-debian.diff):
   **49 effective changes**, driven by the small common and LLVM fragments:
   47 kernel-policy/dependency changes plus standalone signing-path and
   build-salt normalization.

This is explicitly a 7.3 projection of Debian 7.2.8, not a native-version
Debian delta. It does not automatically replace the saved legacy-seed config.

From this bundle's root, refresh the suites into a separate output directory:

```sh
./debian/retrieve.py fetch --suite both \
  --cache-dir "$HOME/.cache/debplus-debian" --output-dir ./debian-latest
```

Use `diff --kernel-tree ...` for evaluated layers, or `diff` without a source
tree for the declaration-only comparison. See the Debian README for exact
commands, offline replay, trust details, and required-option audit results.

### Historical preservation

- [7.1 preservation and audit](baselines/7.1/README.md): exact running
  `7.1.0-debplus.1` config, matching `/usr/local/src/linux/.config` and `/boot`,
  plus an upstream defconfig baseline, readable delta, and replay fragment.
- [7.3 baseline and audit](baselines/7.3/README.md): upstream
  `x86_64_defconfig` for the pinned source and a comparison with the updated
  `config-debian-plus.xz`.

The original saved Debian-plus seed matches the old checkout's `.config.old`,
**not** its running `.config`: they differ in 22 symbol states, mostly Rust
availability/support, Rust-dependent features, and toolchain metadata. The
7.3 migration follows the saved seed's intended policy; the exact running
config is preserved separately rather than overwritten or conflated with it.

These large upstream-default deltas capture thousands of inherited Debian
driver/module choices as well as custom policy. They are audit/replay material,
not a minimal portable set of personal tweaks. Keep `overrides.config` and the
compiler fragments as the concise record of deliberate choices. No private
signing key is included; its default-path automatic generation is explained
in the 7.1 audit.

## Maintenance tools

Two standalone maintenance tools travel with the bundle. Both are stdlib-only
Python and work from a repository checkout or from a deployed copy.

[tools/diff-configs.py](tools/diff-configs.py) compares two kernel
configuration files — plain text or `.xz`, or `-` for standard input — and
prints one `SYMBOL: old -> new` line per difference, matching the format of
the recorded layer diffs. Toolchain version/identity symbols are excluded by
default because Kconfig records them per invocation rather than as policy;
`--include-metadata` reports them, `--keys-from` restricts the comparison to
the symbols declared in a policy fragment, and `--quiet` prints only the
count. The exit status is 0 whether or not symbols differ:

```sh
./tools/diff-configs.py --keys-from overrides.config \
  baselines/7.3/config-upstream-defconfig.xz config-debian-plus.xz
```

[tests/bundle/verify.py](tests/bundle/verify.py) checks a rendered stage
against the bundle's own receipts: declared file bytes and modes, the
repository-tracked file set, the compression registry and saved audit-output
hashes, and relative README links. It is a maintenance tool, not part of an
automatic test run; from a deployed copy without the playbook it skips the
declaration checks with a note:

```sh
python3 tests/bundle/verify.py --stage .test-agent/linux-debplus/stage
```

[tests/tools/run.py](tests/tools/run.py) exercises the diff tool against the
durable in-bundle fixtures, including the preserved 22-symbol 7.1 state
between the exact running configuration and the saved seed.

The full 2026-10-01 session verification transcript (render logs, audit runs,
and the original verify script) remains in the gitignored
`.test-agent/linux-debplus-final/` scratch directory as history; it is not
part of the bundle.

## Compiler tuning

The common fragment applies the tuning choices shared by both compilers:

| Setting | Policy | Effect |
|---|---|---|
| `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y` | Enabled | Uses the kernel's conventional `-O2` optimization level |
| `CONFIG_X86_NATIVE_CPU=y` | Enabled | Uses `-march=native`; the resulting kernel is intended for this machine |
| `CONFIG_RUST=y` | Required | Retains Rust drivers, external Rust module support, and the DRM panic QR screen |
| `CONFIG_DEBUG_INFO=y` | Required | Produces DWARF for the Debian `-dbg` package and kdump analysis |
| `CONFIG_DEBUG_INFO_BTF=y` | Enabled | Retains compact runtime kernel types for advanced BPF tooling |

### LLVM

`overrides.llvm` is the canonical compiler fragment:

| Setting | Policy | Reason |
|---|---|---|
| Build invocation | `LLVM=1` | Selects Clang, LLD, LLVM binutils, and LLVM host tools together |
| `CONFIG_LTO_NONE=y` | Enabled | Linux 7.3 cannot combine LTO with both Rust and BTF |
| `CONFIG_LTO_CLANG_THIN` | Disabled | ThinLTO would force a choice between essential Rust support and BTF |
| `CONFIG_LTO_CLANG_FULL` | Disabled | Has the same compatibility conflict and a much more expensive link stage |
| `CONFIG_AUTOFDO_CLANG` | Disabled | Requires a representative sampled workload profile |
| `CONFIG_PROPELLER_CLANG` | Disabled | Requires a dedicated profile/train/rebuild workflow |
| `CONFIG_CFI` | Disabled | kCFI is hardening with runtime checks, not a general speed optimization |

`LLVM=1` selects tools; it does not imply LTO or profile-guided optimization.
Use it on every LLVM configuration, build, and package invocation so Kconfig
does not silently reevaluate compiler-gated options under GCC.

### GCC

`overrides.gcc` is the fallback compiler fragment:

| Setting | Policy | Reason |
|---|---|---|
| Build invocation | omit `LLVM=1` | Selects GCC and GNU binutils through normal Kbuild defaults |
| `CONFIG_LTO_NONE=y` | Enabled | Upstream x86 Kconfig does not provide a GCC LTO mode |
| `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y` | Enabled | Retains the same `-O2` baseline as LLVM |
| `CONFIG_X86_NATIVE_CPU=y` | Enabled | Retains the same host-specific CPU tuning as LLVM |
| AutoFDO and Propeller | Unavailable | These kernel options are Clang-specific |

The GCC build is a diagnostic fallback for identifying a Clang-specific build
or runtime problem. It is not a second canonical package. Merge the saved seed
with `overrides.config` plus `overrides.gcc`, normalize under GCC in a separate
output directory, and assign a distinct kernel and Debian package version.

### Remaining performance policy

The most meaningful remaining overhead is not another compiler switch. The
inherited Debian policy enables UBSAN bounds and shift instrumentation,
zero-initialized stack variables, and allocation initialization. Disabling
those may improve runtime or build size, but reduces bug detection and
hardening, so it needs a separate measured common-policy decision.

Keep full DWARF debug information: it is stripped from installed boot artifacts
and retained in the `-dbg` package, so its main costs are build time and storage,
not normal runtime. Keep BTF unless measurement shows its compact resident
metadata is a problem; it enables BPF CO-RE, typed tracing, kfuncs, struct-ops,
module BTF, and sched-ext. Keep dynamic ftrace for the crash-diagnostic design.

## Use the saved configuration

Decompress the complete configuration into a Linux checkout, then let Kconfig account
for any options added or removed by that source version:

```sh
xz -dc /usr/local/src/linux-config-debplus/config-debian-plus.xz \
  > /usr/local/src/linux/.config
make -C /usr/local/src/linux LLVM=1 olddefconfig
```

This updates `.config`; it does not compile the kernel. `LLVM=1` selects Clang
and LLD. Keep using `LLVM=1` for later configuration and build commands so the
selected toolchain does not change halfway through. To use the GCC/BFD fallback,
omit `LLVM=1` consistently from every command.

## Regenerate the saved configuration

The 7.3 migration uses the saved Debian-plus configuration as its seed, merged
with `overrides.config` and `overrides.llvm`, then normalized by the pinned
source's Kconfig. It preserves host policy; it is **not** a fresh Debian 7.3
configuration. The old external `config-7.1.3+deb14` input is no longer assumed
to exist.

After changing the fragments, regenerate in a clean source export. This does
not compile or install a kernel:

The current Linux checkout contains output from earlier builds. Linux refuses
to use such a source directory with a separate output directory. The commands
therefore export a source-only temporary copy rather than deleting the existing
build output with `make mrproper`.

```sh
bundle=/usr/local/src/linux-config-debplus
revision=551c722f40809618230001baccf219193e22fc5a
work=$(mktemp -d "$HOME/tmp-opencode/linux-config-debplus.XXXXXX")
mkdir "$work/src" "$work/out"
git -C /usr/local/src/linux archive "$revision" | tar -x -C "$work/src"
printf '%s\n' "$revision" > "$work/src/.debplus-source-revision"
xz -dc "$bundle/config-debian-plus.xz" > "$work/seed.config"
"$work/src/scripts/kconfig/merge_config.sh" -m \
  -O "$work/out" \
  "$work/seed.config" \
  "$bundle/overrides.config" \
  "$bundle/overrides.llvm"
make -C "$work/src" O="$work/out" LLVM=1 olddefconfig
xz -9 --check=crc64 -T1 -c "$work/out/.config" > "$work/config-debian-plus.xz"
install -m 0644 "$work/config-debian-plus.xz" "$bundle/config-debian-plus.xz"
```

Here, `O="$work/out"` only tells Kconfig where to place temporary generated
files. Check required options and inspect the diff before the final `install`.
In particular, confirm `CONFIG_RUST=y`, `CONFIG_DEBUG_INFO_BTF=y`, and
`CONFIG_DRM_PANIC_SCREEN_QR_CODE=y`: a missing `rust-src` component can make
Kconfig drop Rust-dependent policy even when it appears in a fragment.
`merge_config.sh -m` only merges text; the later `olddefconfig` can change it.
Edits made to the deployed bundle are not automatically copied back to
compfuzor; bring accepted changes into its `files/linux-config-debplus/` inputs.

## AMDGPU power-cap hotfix

Check whether the hotfix matches the current Linux source without changing it:

```sh
/usr/local/src/linux-config-debplus/hotfixes/amdgpu-power.sh \
  --check /usr/local/src/linux
```

Apply it by omitting `--check`:

```sh
/usr/local/src/linux-config-debplus/hotfixes/amdgpu-power.sh \
  /usr/local/src/linux
```

The script changes four AMDGPU source files. It detects an already-applied
hotfix and exits without changing them again.

Enable the rebuilt driver's opt-in override with `amdgpu.ignore_min_pcap=1`.
By default it is off. When enabled, hwmon reports a minimum cap of zero, and
the shared SWSMU PPT-limit API allows requests below the firmware minimum.
The selected AC/DC and overdrive **maximum remains enforced**. Unsupported
limits, disabled-device errors, the default-cap zero sentinel, and firmware
failures retain their normal behavior. A reported minimum of zero does not
promise the firmware will accept every low value.

In particular, the SMU 13.0.6 and 15.0.8 fast-PPT setters independently enforce
`PPT1Min`. They can reject a low fast cap with `-EINVAL` despite zero minimum
readback. This port leaves those hardware-specific checks intact.

The 7.3 port targets `smu_get_ppt_limit()` / `smu_set_ppt_limit()` and
`ppt_limits.range[power_source][limit_type]`, replacing the old 7.1
`min_power_limit` API. A clean `--check` establishes only that source hunks fit;
it is not proof of a successful kernel build, boot, or GPU power-control test.

The [regression tests](tests/amdgpu-power/README.md) check both the pinned tip
and rc5 baseline without changing the original checkout. They verify patch
lifecycle and compile the actual patched getter, setter, and hwmon functions
with stubbed kernel/firmware interfaces to exercise bounds, AC/DC, overdrive,
supported limits, errors, and user-profile updates. They do not simulate real
GPU firmware acceptance.

## Build and installation

Configuration, patching, compilation, package installation, and boot selection
remain explicit operator decisions. Review the versioned `MAKE.sh` recipe and
[DEBIAN.md](DEBIAN.md) before building; do not reuse a package identity for a
different source or patch. Keep matching debug symbols and a bootable previous
kernel. No 7.3 kernel is built or installed by deploying this bundle.

`MAKE.sh [SOURCE-TREE]` works from any directory and checks the pinned base
revision. Its default `/usr/local/src/linux` is still user-managed; the recipe
refuses an older Git HEAD. Plain exports must contain the
`.debplus-source-revision` marker shown above. That marker records the declared
base, not a cryptographic proof of the exported contents. Prepare the selected
tree's `.config` and apply the hotfix explicitly before running the recipe.
The package identity is `7.3.0~rc5+git20260929.551c722f4080-1`, sorting before
the eventual final 7.3 release.

[Package-recipe guard tests](tests/package-recipe/make-sh-guards.sh) exercise
revision, source-root, marker, and expected-hotfix checks with recording
Git/Make stubs. They do not compile a kernel.

## Archive

`archive/previous-normalization/` contains old GCC-era Kconfig scratch output.
`archive/amdgpu-power/` contains superseded scripts, patches, and `.orig` source
backups. These files are not needed to restore the current configuration or
reapply the current hotfix. Cleanup is deliberate, never automatic.

The initial import came from the local jj repo at
`/usr/local/src/linux-config-debplus` on 2026-10-01. Its 7.1 configuration,
hotfix, and build command are preserved in compfuzor's commit history. The
original local repo remains intact; it and the compfuzor inputs do not
automatically synchronize.

[Recovered inputs](archive/recovered-inputs/README.md) include the old
`config-7.1.3+deb14` base, a 6.13 config, and the small tool declaration found
in JJ history. They are compressed evidence, not automatically restored files.

The old in-place kernel build was cleaned on 2026-10-01, reclaiming 24.16 GB.
Its small private preservation set is at
`/usr/local/src/linux-build-preserved/7.1.0-debplus.1-20261001/`, including
configs, signing material, build metadata, and the exact unstripped kernel
image. That directory and the old `.deb` packages are separate from this public
bundle; private keys are never committed here.

Related compfuzor material: [rektide/compfuzor `pstore.etc.pb`](https://github.com/rektide/compfuzor/blob/main/pstore.etc.pb) explains the
runtime crash-evidence policy enabled by the `CONFIG_PSTORE*` options;
[`crashkernel.etc.pb`](https://github.com/rektide/compfuzor/blob/main/crashkernel.etc.pb) explains kdump and matching symbols.
The [Blueturn kernel investigation](https://github.com/rektide/compfuzor/blob/main/design/blueturn/kernel-uhid-shortreport.general.md)
records why the previous `7.1.0-debplus.1` build needed a HID fix; that is
historical context, not a reason to reapply its backport to 7.3.
