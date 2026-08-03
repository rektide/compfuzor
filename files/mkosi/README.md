# files/mkosi/ — mkosi/VPS image tooling

Standalone scripts used around the mkosi image build and on the boxes that boot
those images. Each is self-contained, `bash -n` clean, and documented inline
(run `--help` or read the header). The mkosi playbook ships the on-image ones
into the disk image via `mkosi.extra/` so they land on `/usr/local/bin/`.

## scripts

| script | runs where | what it does |
|---|---|---|
| [`identity.sh`](identity.sh) | on the image / a clone | (re)provision system + disk identity for clone-ready images. `--first-boot` (default) blanks userspace so next boot regenerates it; `--generate` builds a fresh identity now + regenerates block UUIDs (ext4/xfs/btrfs/swap, GPT+MBR aware). Guards: `--new`/`--old`/`--force-disks`. |
| [`networkd-static.sh`](networkd-static.sh) | on the image / a build host | generate systemd-networkd `.network` files. Three modes: **render** (from `--file` profile / env), **gather** (`--gather`, snapshot a live iface), **from-interfaces** (`--from-interfaces [PATH]`, parse Debian `/etc/network/interfaces`, detect dhcp vs static per iface, emit one `.network` each). IPv4 + IPv6. |
| [`initrd-rewrite.sh`](initrd-rewrite.sh) | on the VPS (host) | crack open a cpio initrd, inject files / run edits, reseal — same compression. Used to specialize a generic initrd with per-host data (e.g. a generated networkd config) on the box, the way `update-initramfs` does. |
| [`debian-pkgs.sh`](debian-pkgs.sh) | build host | screen Debian package tiers (`essential` / `recommends` / `suggests`) to stdout for reviewing what an image build pulls in. |

## the VPS "specialize a generic initrd" flow

Build a **generic** initrd once (mkosi `vps-seed`), ship it + the tools to the
VPS, then specialize the initrd **on the box** from the box's own data, then
kexec — no per-host rebuild, no bootloader cmdline args, no chicken-and-egg:

```sh
# 1. generate networkd config from THIS box's Debian ifupdown config
networkd-static.sh --from-interfaces -o /tmp/net
# 2. bake it into the generic vps-seed initrd (crack open, inject, reseal)
initrd-rewrite.sh /boot/vps-seed.img --inject /tmp/net:/etc/systemd/network
# 3. kexec into it — it now comes up on the host's own IP, self-contained
```

The per-host network data comes from `/etc/network/interfaces` (already on the
disk); the initrd carries no host data at build time and is rewritten in place
where both the initrd file and the interfaces file live.

## notes

- `initrd-rewrite.sh` works on **cpio** initrds (what mkosi emits), NOT on UKIs
  (signed PE binaries — rewriting breaks the signature) and not on distro
  `/boot/initrd.img` with a microcode-prepend prefix (use `update-initramfs`).
- `identity.sh` is the canonical clone-identity tool; `pivot-bdr.srv.pb`'s
  `clone-reset.sh` is a raw copy of it (single source of truth lives here).
- `networkd-static.sh` `render`/`gather` force `DHCP=no` (static); only
  `--from-interfaces` sets `DHCP=` per the detected ifupdown method.
