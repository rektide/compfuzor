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
    ETC_FILES:
      - name: pkgs.txt
        content: "{{ lookup('template', '../../files/_pkgs') }}"
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
          # vps-seed: a bootable initrd/seed for a constrained BIOS/MBR VPS.
          # Wraps mkosi-initrd (builds an initrd for the running kernel).
          # mkosi-initrd does NOT accept extra packages, so this ships fs
          # *kernel modules* (mount ext4/xfs/btrfs) but NOT the mkfs.* tools;
          # a vps-seed with formatting tools needs the full mkosi cpio subimage
          # (mkosi.images/vps-seed/) — coming with the mkosi.conf restructuring.
          # Target is BIOS/MBR (no GPT/ESP); prefer systemd-boot in life but
          # this VPS is MBR-only. $1 = output name (default vps-seed), rest
          # passed through to mkosi-initrd, e.g.:
          #   vps-seed.sh myseed --profile network,lvm --kernel-version $(uname -r)
          NAME="${1:-vps-seed}"; shift || true
          OUTDIR="${VPS_SEED_OUTDIR:-${DIR}/var/output}"
          mkdir -p "$OUTDIR"
          mkosi-initrd --format cpio --output "$NAME" --output-dir "$OUTDIR" "$@"
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
      | `build.sh` | builds `image.raw` (Debian trixie disk + mkosi-vm builtin) from `etc/pkgs.txt` |
      | `run-nspawn.sh` | boots `image.raw` in systemd-nspawn |
      | `vps-seed.sh [name] [mkosi-initrd opts…]` | builds a BIOS/MBR VPS initrd (cpio). **Ships fs kernel modules only — not mkfs.\* tools** (mkosi-initrd can't take extra pkgs; the full formatting-capable seed is the coming `mkosi.images/vps-seed/` subimage) |
      | `identity.sh` | (re)provision system/disk identity for clone-ready images — see below |
      | `debian-pkgs.sh essential\|recommends\|suggests\|all [pkgs…]` | screen Debian package tiers to stdout for review |

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
      -B -f`), the reference for the mkosi.conf/`mkosi.images/` layout this
      playbook will grow into.
    ARCH_PKGS:
      - debootstrap
      - debian-archive-keyring
      - apt
  tasks:
    - import_tasks: tasks/compfuzor.includes
