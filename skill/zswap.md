# compfuzor: zswap configuration

## Overview

Configures the kernel's zswap compressed swap cache. Zswap sits between swapin/swapout and the backing swap device, intercepting pages and compressing them in RAM before they reach disk. When the compressed pool exceeds its limit, pages evict to the backing swap device as normal.

This is an `etc`-type playbook. It generates a modprobe config, a sysctl drop-in, and a systemd oneshot service to apply settings immediately.

## Variables

### Core toggles

| Variable | Default | Purpose |
|---|---|---|
| `ZSWAP_ENABLED` | `Y` | Enable or disable zswap entirely |
| `ZSWAP_BYPASS` | `False` | Skip all zswap processing |

### Compression

| Variable | Default | Purpose |
|---|---|---|
| `ZSWAP_COMPRESSOR` | `lz4` | Compressor algorithm (`lz4`, `zstd`, `lzo`, `lz4hc`, `842`) |
| `ZSWAP_ZPOOL` | `z3fold` | Allocator backend (`z3fold`, `zbud`, `zsmalloc`) |
| `ZSWAP_SAME_FILLED_PAGES_ENABLED` | `Y` | Deduplicate pages filled with identical values (zero-page optimization) |
| `ZSWAP_ACCEPT_THRESHOLD_PERCENT` | `90` | Percentage of compressed pool at which zswap starts rejecting new pages (0-100) |

### Pool sizing

| Variable | Default | Purpose |
|---|---|---|
| `ZSWAP_MAX_POOL_PERCENT` | `20` | Maximum percentage of RAM the compressed pool can consume (1-100) |
| `ZSWAP_EXCLUSIVE_LOADS` | `Y` (kernel 6.10+) | When a page is loaded back from zswap, remove it from the pool (avoids duplication) |

### Kernel module preloading

The skill adds the `zswap` module to `/etc/modules-load.d/` so it's loaded early in boot (before swap activation), via the `MODULES` mechanism.

## Generated files

| File | Destination | Purpose |
|---|---|---|
| `zswap.conf` | `/etc/modules-load.d/` | Load the zswap kernel module at boot |
| `zswap-modprobe.conf` | `/etc/modprobe.d/` | Set zswap module parameters |
| `zswap.conf` | `/etc/sysctl.d/` | Runtime sysctl for parameters not exposed as module params |

## Minimal usage

```yaml
# zswap.etc.pb
TYPE: zswap
```

This uses all defaults: enabled, lz4, z3fold, 20% pool, 90% threshold.

## Tuned example

```yaml
# zswap.etc.pb
TYPE: zswap
ZSWAP_COMPRESSOR: zstd
ZSWAP_MAX_POOL_PERCENT: 35
ZSWAP_ACCEPT_THRESHOLD_PERCENT: 85
```

## How it works

1. **Boot-time**: `modules-load.d` loads the `zswap` module. `modprobe.d` sets parameters that take effect at module load.
2. **Runtime apply**: The systemd oneshot service writes parameters to `/sys/module/zswap/parameters/` so changes take effect without reboot.
3. **Bypass**: Set `ZSWAP_BYPASS: True` to skip all zswap generation.

## Interaction with zram

Zswap and zram are independent but complementary:
- **zram** creates a compressed block device used as swap
- **zswap** caches swap pages in compressed RAM before they hit any swap backend

Both can be used simultaneously. Zswap will cache pages headed for zram or disk-based swap. If using only zram (no disk swap), zswap adds an extra compression layer on top of the already-compressed zram device — usually not worth the overhead. Zswap shines when backing swap is on disk.

## Kernel requirements

- `CONFIG_ZSWAP=y` — kernel must be compiled with zswap support
- `CONFIG_ZRAM=y` — only needed if also using zram
- Compressor backends: `CONFIG_LZ4_COMPRESS`, `CONFIG_ZSTD_COMPRESS`, etc.
- Allocator backends: `CONFIG_Z3FOLD`, `CONFIG_ZBUD`, `CONFIG_ZSMALLOC`

## Key files

| File | Purpose |
|---|---|
| `zswap.etc.pb` | Playbook |
| `skill/zswap.md` | This skill document |
