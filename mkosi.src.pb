---
- hosts: all
  vars:
    REPO: https://github.com/systemd/mkosi
    ENV:
      scratchsize: "{{scratchsize|default()}}"
      INSTANCE: git
      hostname: "{{hostname|default('debos')}}"
      user: "{{user|default(ansible_user_id)}}"
      password: "{{password|default('CHANGE_OR_ELSE')}}"
    MKOSI_PKGS: []
    MKOSI_PKGSETS:
      - BASE
      # TODO: eventually support "BASE_{{ARCH}}" parametric pkgsets so the
      # amd64/arm64-specific sets resolve automatically from ARCH.
      - BASE_amd64
      # - WORKSTATION
      # - VIRTUALIZATION
      # - WORKSTATION_X
      # - OPENCL
      # - XPRA
      # - DEVEL
      # - DEBDEV
      # - AUDIO
      # - AUDIO_X
      # - BT
      # - BT_X
      # - RYGEL
      # - RYGEL_X
      # - USERSPACE
      # - JACK
      # - JACK_X
      # - MEDIA
      # - VAAPI
      # - VAAPI_amd64
      # - WORKSTATION_WAYLAND
      # - MEDIA_X
      # - POSTGRES
      # - CONTAINER
      # - BONUS
      # - WORDS
    ETC_DIRS:
      - mkosi.images/vps-seed
      - mkosi.images/oci
      - mkosi.images/disk
    ETC_FILES:
      - name: pkgs.txt
        content: "{{ lookup('template', '../../files/_pkgs') }}"
      # --- config-driven multi-build (mkosi.conf + mkosi.images/) ---
      # Main config: universal settings (Distribution/Release/Repositories and
      # Output*/Cache* are main-image-only). Format=none = no main artifact;
      # the deliverables are the subimages selected by Dependencies=.
      - name: mkosi.conf
        content: |
          [Distribution]
          Distribution=debian
          Release=trixie
          Repositories=main,contrib,non-free,non-free-firmware

          [Build]
          CacheDirectory={{DIR}}/var/cache
          PackageCacheDirectory={{DIR}}/var/package-cache

          [Config]
          # Build only these subimages by default. `image.sh <variant>` overrides
          # via mkosi --dependency to build just one.
          Dependencies=vps-seed,oci

          [Output]
          Format=none
          OutputDirectory={{DIR}}/var/output
      # vps-seed: bootable cpio initrd for a constrained BIOS/MBR VPS.
      - name: mkosi.images/vps-seed/mkosi.conf
        content: |
          # Includes the mkosi-initrd builtin (init + module assembly) AND the fs
          # formatting tools the mkosi-initrd *wrapper* can't take as packages.
          # NOTE: this does NOT inject the running host's kernel modules (the
          # vps-seed.sh wrapper does, via --extra-tree). For a host-tailored
          # initrd for THIS box, use bin/vps-seed.sh instead.
          [Include]
          Include=mkosi-initrd

          [Output]
          Format=cpio
          Output=vps-seed
          # xz = widest old-kernel compat (needs CONFIG_RD_XZ). Level 6 = mid-high,
          # sane memory (9 is ridiculous). BIOS/MBR VPS kernels predate zstd often.
          CompressOutput=xz
          CompressLevel=6
          # zstd alternative (mid-high; needs kernel >= 5.1 / CONFIG_RD_ZSTD):
          #CompressOutput=zstd
          #CompressLevel=15

          [Content]
          Packages=
                  e2fsprogs
                  btrfs-progs
                  xfsprogs
                  dosfstools
                  util-linux
      # oci: the base Debian rootfs as an OCI container image.
      - name: mkosi.images/oci/mkosi.conf
        content: |
          [Output]
          Format=oci
          Output=mkosi-oci
      # Sample subimage that consumes the compfuzor PKGSETS list.
      # This is the config-driven replacement for build-debian.sh's
      # --package "$(commaSep etc/pkgs.txt)": the same lookup('pkgs') that
      # renders etc/pkgs.txt is rendered straight into Packages= (comma-separated,
      # which mkosi accepts). Toggle sets via MKOSI_PKGSETS at the top of the
      # playbook; this image picks them up with no bin edit. Not in the default
      # Dependencies= (heavy) — build with: image.sh disk
      - name: mkosi.images/disk/mkosi.conf
        content: |
          [Output]
          Format=disk
          Output=mkosi-disk
          [Content]
          Packages={{ (lookup('pkgs') | unique) | join(',') }}
    BINS:
      - name: build-debian.sh
        exec: |
          # btrfs rootdir recommended!

          commaSep(){
            paste -sd, "$1"
          }
          mkosi \
            --distribution debian \
            --release trixie \
            --format disk \
            --checksum \
            --root-password "$PASSWORD" \
            --include mkosi-vm \
            --package "$(commaSep etc/pkgs.txt)" \
            --repository-key-fetch yes \
            --output image.raw \
            "$@"
      - name: run-nspawn.sh
        exec: |
          systemd-nspawn --boot --image image.raw "$@"
      - name: vps-seed.sh
        exec: |
          # vps-seed: a HOST-TAILORED bootable initrd for a constrained BIOS/MBR VPS.
          # Wraps mkosi-initrd, which injects THIS box's kernel modules + firmware
          # (so the result boots on this kernel). mkosi-initrd does NOT accept extra
          # packages, so this ships fs *kernel modules* (mount ext4/xfs/btrfs) but
          # NOT the mkfs.* formatting tools. For an initrd WITH formatting tools
          # (generic, not host-tailored), build the mkosi.images/vps-seed/ subimage
          # via `image.sh vps-seed`. $1 = output name (default vps-seed), rest
          # passed through to mkosi-initrd, e.g.:
          #   vps-seed.sh myseed --profile network,lvm --kernel-version $(uname -r)
          NAME="${1:-vps-seed}"; shift || true
          OUTDIR="${VPS_SEED_OUTDIR:-${DIR}/var/output}"
          mkdir -p "$OUTDIR"
          mkosi-initrd --format cpio --output "$NAME" --output-dir "$OUTDIR" "$@"
      - name: image.sh
        basedir: etc
        exec: |
          # image.sh [variant] — build the mkosi.conf graph from etc/.
          # No arg: build the subimages listed in mkosi.conf [Config] Dependencies=.
          # With a variant: build just that mkosi.images/<variant>/ via
          # mkosi --dependency. Examples: image.sh vps-seed ; image.sh oci
          mkdir -p "{{DIR}}/var/output" "{{DIR}}/var/cache" "{{DIR}}/var/package-cache"
          if [ -n "${1:-}" ]; then set -- --dependency "$1"; fi
          mkosi -B -f "$@"
      - name: identity.sh
        src: identity.sh
        raw: true
      - name: debian-pkgs.sh
        src: debian-pkgs.sh
        raw: true
    README: |
      # mkosi-git

      Installs the **mkosi** image builder (from git) and provides bins to build
      Debian disk images, a BIOS/MBR VPS initrd seed, and clone-identity tooling.

      ## bins (`bin/`)

      | bin | what it does |
      |---|---|
      | `build.sh` | legacy: builds `image.raw` (Debian trixie disk + mkosi-vm) from `etc/pkgs.txt` via CLI |
      | `run-nspawn.sh` | boots `image.raw` in systemd-nspawn |
      | `image.sh [variant]` | **config-driven multi-build** — builds the `etc/mkosi.conf` graph; `image.sh vps-seed` / `oci` builds one subimage via `mkosi --dependency` |
      | `vps-seed.sh [name] [mkosi-initrd opts…]` | HOST-tailored initrd (cpio) for this box's kernel via `mkosi-initrd`. Ships fs *kernel modules* (mount ext4/xfs/btrfs) but NOT mkfs.\* tools |
      | `identity.sh` | (re)provision system/disk identity for clone-ready images — see below |
      | `debian-pkgs.sh essential\|recommends\|suggests\|all [pkgs…]` | screen Debian package tiers to stdout for review |

      ## config-driven multi-build (`etc/mkosi.conf` + `etc/mkosi.images/`)

      `image.sh` drives the mkosi config tree in `etc/`:

      - `etc/mkosi.conf` — main config: universal settings (Distribution/Release/
        Repositories, Output\*/Cache\* dirs → `var/`). `Format=none` (no main
        artifact); `Dependencies=vps-seed,oci` selects which subimages build.
      - `mkosi.images/vps-seed/` — bootable cpio initrd (`Include=mkosi-initrd`
        + ext4/xfs/btrfs/dos formatting tools). xz level 6 (commented zstd 15).
        **Generic** — does NOT inject host kernel modules; for a host-tailored
        initrd use `vps-seed.sh`.
      - `mkosi.images/oci/` — base Debian rootfs as an OCI container image.
      - `mkosi.images/disk/` — **sample** full disk image that consumes the
        compfuzor `PKGSETS` list (not in default `Dependencies=`; build with
        `image.sh disk`). See "wiring PKGSETS into a subimage" below.

      To add a build: drop another `mkosi.images/<name>/mkosi.conf`. Build one
      with `image.sh <name>` (no bin edit needed). Note: mkosi's `--dependency`
      **appends** to the main's `Dependencies=` rather than replacing it, so
      `image.sh disk` builds disk *plus* the default lean set (vps-seed, oci);
      to isolate one, comment the main's `Dependencies=` line.

      ## wiring PKGSETS into a subimage

      The compfuzor package-list machinery (`MKOSI_PKGSETS` → `lookup('pkgs')`
      → the same list that renders `etc/pkgs.txt`) can be rendered straight into
      a subimage's `Packages=`. Because the `content:` blocks are Jinja-rendered:

          [Content]
          Packages={{ (lookup('pkgs') | unique) | join(',') }}

      Toggle which sets resolve via `MKOSI_PKGSETS` at the top of this playbook
      (currently `BASE, BASE_amd64` = 238 pkgs; uncomment the rest for a ~1000-pkg
      workstation image). Use this for full disk/workstation subimages — keep
      initrd/oci subimages lean with explicit `Packages=`.

      ## mkosi output formats

      `Format=` one of: `directory` (plain tree, fastest to inspect/diff),
      `tar`, `cpio` (initrd), `disk` (GPT block image), `uki` (unified kernel
      image), `esp` (ESP-only disk), `oci` (OCI container image), `sysext`,
      `confext`, `portable`, `addon`, `none` (build-only, no output).

      ## cloning & system identity

      A cloned system shares `machine-id`, ssh host keys, the entropy seed, and
      (for dd'd disks) every fs/partition UUID — two clones on one kernel
      collide. **Build images blank and let each clone self-provision on first
      boot.** `identity.sh` does this two ways:

      - `identity.sh --first-boot [--root DIR]` (default) — blanks userspace
        identity (machine-id truncated empty, dbus id + ssh host keys + random
        seed + journal cleared, `systemd-firstboot --reset`) so it regenerates
        next boot. Non-destructive. Use on a mounted image root.
      - `identity.sh --generate [--root DIR] [--new DISK|PART] [--old DISK]
        [--force-disks] [--force]` — builds a fresh identity now and, with
        `--new`, regenerates block UUIDs (GPT GUIDs/partuuids via sgdisk;
        ext4/xfs/btrfs/swap UUIDs). `--new` accepts a whole disk **or** a single
        partition. `--old` (the clone source) is required as a guard unless
        `--force-disks`. MBR/DOS targets skip partuuids (no native partuuid).

      Derivation: evolved from `pivot-bdr.srv.pb`'s `clone-reset.sh`
      (the in-repo origin of the "truncate machine-id, don't delete" gotcha).

      ## preseed / firstboot model

      mkosi does **not** use d-i preseeds or chroot `policy-rc.d` scripts
      (unlike the legacy `files/multistrap/preseed` / `files/pdebuildx/preseed`
      paths). It installs in a sandbox (services don't start) and provisions via
      **mkosi Credentials** + `systemd-firstboot` on first boot
      (`passwd.plaintext-password.root`, `firstboot.locale`,
      `firstboot.timezone`, `firstboot.hostname`). Our `build.sh` currently bakes
      `--root-password` (not clone-friendly); moving to credentials is part of
      the coming mkosi.conf restructuring.

      ## profiles

      `mkosi --profile` (and `Profiles=`) take a **comma-separated list** — you
      are not limited to one profile at a time.

      ## see also

      `particleos.src.pb` — a full ParticleOS immutable image (repo + `mkosi
      -B -f`), a reference for the `mkosi.conf`/`mkosi.images/` layout.
    ARCH_PKGS:
      - debootstrap
      - debian-archive-keyring
      - apt
  tasks:
    - import_tasks: tasks/compfuzor.includes
