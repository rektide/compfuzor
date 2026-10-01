# Linux Debian-plus configuration

This repository survives when `/usr/local/src/linux` is deleted and replaced.
It stores the pieces needed to restore this machine's custom kernel setup; it
does not contain a kernel build.

## Files

- `config-debian-plus` is the complete, ready-to-use kernel configuration.
- `overrides.config` is the shorter list of deliberate changes from Debian's
  configuration that apply to every compiler.
- `overrides.llvm` selects the current Clang/LLVM optimization policy.
- `overrides.gcc` selects the GCC/binutils fallback policy.
- [`DEBIAN.md`](/DEBIAN.md) documents configuration, packaging, installation,
  symbols, reproducibility, and alternate build flows.
- `hotfixes/amdgpu-power.sh` reapplies the AMDGPU minimum-power-cap source
  change after the Linux checkout is replaced.
- `archive/` contains old inputs and backups. Nothing in the current workflow
  reads it.

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
| `CONFIG_LTO_NONE=y` | Enabled | Linux 7.1 cannot combine LTO with both Rust and BTF |
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
or runtime problem. It is not a second canonical package. Generate it from the
Debian base with `overrides.config` plus `overrides.gcc`, use a separate output
directory, and assign a distinct kernel and Debian package version.

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

Copy the complete configuration into a Linux checkout, then let Kconfig account
for any options added or removed by that source version:

```sh
cp /usr/local/src/linux-config-debplus/config-debian-plus \
  /usr/local/src/linux/.config
make -C /usr/local/src/linux LLVM=1 olddefconfig
```

This updates `.config`; it does not compile the kernel. `LLVM=1` selects Clang
and LLD. Keep using `LLVM=1` for later configuration and build commands so the
selected toolchain does not change halfway through. To use the GCC/BFD fallback,
omit `LLVM=1` consistently from every command.

## Regenerate the saved configuration

Use this only after changing `overrides.config` or replacing Debian's base
configuration. It combines those two files and updates `config-debian-plus`.
It does not compile or install a kernel.

The current Linux checkout contains output from earlier builds. Linux refuses
to use such a source directory with a separate output directory. The commands
therefore export a source-only temporary copy rather than deleting the existing
build output with `make mrproper`.

```sh
work=$(mktemp -d /tmp/linux-config-debplus.XXXXXX)
mkdir "$work/src" "$work/out"
git -C /usr/local/src/linux archive HEAD | tar -x -C "$work/src"
/usr/local/src/linux/scripts/kconfig/merge_config.sh -m \
  -O "$work/out" \
  /usr/local/src/linux/config-7.1.3+deb14 \
  /usr/local/src/linux-config-debplus/overrides.config \
  /usr/local/src/linux-config-debplus/overrides.llvm
make -C "$work/src" O="$work/out" LLVM=1 olddefconfig
install -m 0644 "$work/out/.config" \
  /usr/local/src/linux-config-debplus/config-debian-plus
```

Here, `O="$work/out"` only tells Kconfig where to place temporary generated
files. The resulting complete configuration is the final `install` source.

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

## Archive

`archive/previous-normalization/` contains old GCC-era Kconfig scratch output.
`archive/amdgpu-power/` contains superseded scripts, patches, and `.orig` source
backups. These files are not needed to restore the current configuration or
reapply the current hotfix. They are safe to delete if their historical context
is not wanted.
