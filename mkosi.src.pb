---
- hosts: all
  vars:
    REPO: https://github.com/systemd/mkosi
    # Swap size for mkosi.repart/20-swap.conf's @SWAP@ token (stamped at build
    # by image.sh). Fixed min==max: swap sits BEFORE root so root stays last
    # and grows to fill (repart won't move swap to grow it later). Sized >=
    # RAM for hibernate; Type=swap auto-activates + auto-resume via
    # systemd-gpt-auto-generator. ESP size lives in the kit
    # (files/repart/defs/universal.d/10-esp.conf, 384M) — override via
    # REPART_SED if ever needed.
    SWAP_SIZE: "24G"
    ENV:
      scratchsize: "{{scratchsize|default()}}"
      INSTANCE: git
      hostname: "{{hostname|default('debos')}}"
      user: "{{user|default(ansible_user_id)}}"
      password: "{{password|default('CHANGE_OR_ELSE')}}"
    MKOSI_PKGS: []
    # Route all build-time package fetches through the local apt-cacher-rs
    # instance (apt-cacher-rs.src.pb -> apt-cacher-rs-git, listening :3142).
    # Renders [Build] ProxyUrl= below: mkosi marks ProxyUrl multiversal (tools
    # tree + every subimage), passing Acquire::http(s)::Proxy= to apt and
    # http(s)_proxy env into the build sandbox. The cacher upgrades upstream
    # fetches to TLS itself (https_upgrade_mode=Auto), so plain-http repo URLs
    # still get cached, verified packages. Override or disable via extra vars:
    # -e APT_PROXY=http://other:3142/ or -e APT_PROXY= (empty drops the line
    # for portable/offline builds).
    APT_PROXY: http://127.0.0.1:3142/
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
      - mkosi.images/disk/mkosi.repart
      - mkosi.images/disk/mkosi.extra/usr/local/bin
      - mkosi.images/disk/mkosi.extra/opt/repart-main/bin
      - mkosi.images/disk/mkosi.extra/opt/repart-main/var
      - mkosi.images/disk/mkosi.extra/opt/repart-main/etc/defs/universal.d
      - mkosi.images/disk/mkosi.extra/opt/repart-main/etc/defs/format.d
      - mkosi.images/disk/mkosi.extra/opt/repart-main/etc/defs/bdr.d
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
          # btrfs subvolumes (Subvolumes=/DefaultSubvolume= in mkosi.repart/)
          # cannot be created without loopback devices, so build online.
          RepartOffline=no
          # Local apt cache (APT_PROXY at the top of the playbook). Multiversal:
          # proxies the tools tree and every subimage. Coexists with
          # PackageCacheDirectory above (mkosi's on-disk deb cache); the proxy
          # adds HTTP-level dedupe shared with this host's apt and other boxes.
          {% if APT_PROXY %}ProxyUrl={{APT_PROXY}}
          {% endif %}

          [Config]
          # Build only these subimages by default. `image.sh <variant>` overrides
          # via mkosi --dependency to build just one.
          # vps-seed is NOT in the default set: mkosi-initrd's Debian-family
          # dpkg strip (mkosi-initrd/mkosi.conf.d/debian-kali-ubuntu/
          # mkosi.conf.d/dpkg.conf -> RemovePackages=dpkg, active on trixie)
          # breaks its own purge cascade -- postrm scripts hit
          # `dpkg-query: not found` and dpkg stops with "too many errors".
          # Upstream bug (their comment: "Needs perl >= 5.40.0-8 and
          # dash >= 0.5.12-7 to drop this"); retry `image.sh vps-seed` after
          # an mkosi bump.
          Dependencies=oci

          [Output]
          Format=none
          OutputDirectory={{DIR}}/var/output
      # mkosi.repart/ is per-image and NOT inherited by subimages, so it lives
      # INSIDE the disk subimage's dir. It REPLACES mkosi's built-in partition
      # defs entirely (no merge). The layout is the kit's universal.d + the
      # format.d root, embedded VERBATIM under kit filenames (00-grub 10-esp
      # 20-swap 50-root = the universal layout) with only mkosi's build-time
      # population appended (CopyFiles/MountPoint). Do not fork the partition
      # or subvolume layout here — edit files/repart/defs/ instead.
      # @ARCH@/@DATE@/@SWAP@ are rendered at build by `repart render`.
      - name: mkosi.images/disk/mkosi.repart/00-grub.conf
        content: "{{ lookup('file', '../../files/repart/defs/universal.d/00-grub.conf') }}"
      - name: mkosi.images/disk/mkosi.repart/10-esp.conf
        content: |
          {{ lookup('file', '../../files/repart/defs/universal.d/10-esp.conf') }}
          # mkosi build-time population: UKI/kernel artifacts from the image
          # tree's /boot and /efi land in the ESP (kit's is blank — a fresh
          # format has nothing to copy).
          CopyFiles=/boot:/
          CopyFiles=/efi:/
      - name: mkosi.images/disk/mkosi.repart/20-swap.conf
        content: "{{ lookup('file', '../../files/repart/defs/universal.d/20-swap.conf') }}"
      - name: mkosi.images/disk/mkosi.repart/50-root.conf
        content: |
          {{ lookup('file', '../../files/repart/defs/format.d/50-root.conf') }}
          # mkosi build-time population: the built rootfs is copied into the
          # DEFAULT subvolume (the dated OS slot); MountPoint= tells mkosi
          # where the root lives (nspawn/testing).
          CopyFiles=/
          MountPoint=/:"subvol=root/superbfowle/@ARCH@/@DATE@,compress=zstd:3,noatime,lazytime"
      # Copy useful scripts INTO the disk image via mkosi.extra/ (overlaid on
      # the rootfs). identity.sh (clone-identity), networkd-static.sh (networkd
      # config: render/gather/from-interfaces), and initrd-rewrite.sh (crack open
      # a cpio initrd, inject files, reseal — runs ON the VPS). Add more as
      # mkosi.extra/<path> entries.
      - name: mkosi.images/disk/mkosi.extra/usr/local/bin/identity.sh
        content: "{{ lookup('file', '../../files/mkosi/identity.sh') }}"
        mode: "0755"
      # Burn the same one-public-bin layout used by repart.opt.pb into images.
      - name: mkosi.images/disk/mkosi.extra/opt/repart-main/bin/repart
        content: "{{ lookup('file', '../../files/repart/repart.ts') }}"
        mode: "0755"
      - name: mkosi.images/disk/mkosi.extra/opt/repart-main/etc/defs/universal.d/00-grub.conf
        content: "{{ lookup('file', '../../files/repart/defs/universal.d/00-grub.conf') }}"
      - name: mkosi.images/disk/mkosi.extra/opt/repart-main/etc/defs/universal.d/10-esp.conf
        content: "{{ lookup('file', '../../files/repart/defs/universal.d/10-esp.conf') }}"
      - name: mkosi.images/disk/mkosi.extra/opt/repart-main/etc/defs/universal.d/20-swap.conf
        content: "{{ lookup('file', '../../files/repart/defs/universal.d/20-swap.conf') }}"
      - name: mkosi.images/disk/mkosi.extra/opt/repart-main/etc/defs/universal.d/50-root.conf
        content: "{{ lookup('file', '../../files/repart/defs/universal.d/50-root.conf') }}"
      - name: mkosi.images/disk/mkosi.extra/opt/repart-main/etc/defs/format.d/50-root.conf
        content: "{{ lookup('file', '../../files/repart/defs/format.d/50-root.conf') }}"
      - name: mkosi.images/disk/mkosi.extra/opt/repart-main/etc/defs/bdr.d/50-root.conf
        content: "{{ lookup('file', '../../files/repart/defs/bdr.d/50-root.conf') }}"
      - name: mkosi.images/disk/mkosi.extra/usr/local/bin/networkd-static.sh
        content: "{{ lookup('file', '../../files/mkosi/networkd-static.sh') }}"
        mode: "0755"
      - name: mkosi.images/disk/mkosi.extra/usr/local/bin/initrd-rewrite.sh
        content: "{{ lookup('file', '../../files/mkosi/initrd-rewrite.sh') }}"
        mode: "0755"
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
      # renders etc/pkgs.txt is rendered into Packages= per-pkgset. mkosi merges
      # multiple Packages= lines, so we emit one commented line per set for
      # easy review. Toggle sets via MKOSI_PKGSETS at the top of the playbook;
      # this image picks them up with no bin edit. Not in the default
      # Dependencies= (heavy) — build with: image.sh disk
      - name: mkosi.images/disk/mkosi.conf
        content: |
          [Output]
          Format=disk
          Output=mkosi-disk
          [Content]
          Bootable=yes
          # Runtime for the embedded /opt/repart-main/bin/repart TypeScript CLI.
          Packages=nodejs
          {% for setname in MKOSI_PKGSETS %}# {{ setname }} ({{ lookup('pkgs', setname) | length }})
          Packages={{ (lookup('pkgs', setname) | unique) | join(',') }}
          {% endfor %}
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
          #
          # @DATE@ tokens in the config tree (e.g. the dated home subvol) are
          # rendered at BUILD time by `repart render` (env
          # MKOSI_DATE=YYYYMMDD, else today) into an on-disk scratch copy
          # (/opt/repart-main/var — never tmpfs); etc/ stays tokenized, never stale.
          DATE="${MKOSI_DATE:-}"
          case "$DATE" in *[!0-9]*) echo "Error: bad MKOSI_DATE '$DATE' (want YYYYMMDD)" >&2; exit 1 ;; esac
          mkdir -p "{{DIR}}/var/output" "{{DIR}}/var/cache" "{{DIR}}/var/package-cache" "{{DIR}}/var/tmp"
          # Render the whole mkosi tree through the public repart seam. This
          # resolves DATE, ARCH, and SWAP before mkosi sees any configuration.
          REPART="${REPART_DIR:-/opt/repart-main}"
          [ -x "$REPART/bin/repart" ] || { echo "Error: install repart.opt.pb first" >&2; exit 1; }
          # The toolkit copied into the guest is an opaque payload: preserve
          # its tokens so the spawned machine renders its own future trees.
          args=(render --from {{ETC}} --swap "{{SWAP_SIZE}}" \
            --preserve mkosi.images/disk/mkosi.extra/opt/repart-main)
          [ -z "$DATE" ] || args+=(--date "$DATE")
          BUILD="$("$REPART/bin/repart" "${args[@]}")"
          trap 'rm -rf "$BUILD"' EXIT
          echo "date stamp: ${MKOSI_DATE:-today}" >&2
          # RepartOffline=no lives in the MAIN config (universal scope:
          # subimages cannot set it) because disk builds need loop devices --
          # but that makes mkosi demand root for EVERY build. Lean variants
          # (no disk in the set: vps-seed, oci, or the no-arg default) never
          # touch repart: re-enable offline for them so they build as a
          # normal user. Extra args after the variant pass through to mkosi.
          variant=""; [ "$#" -gt 0 ] && { variant="$1"; shift; }
          [ "$variant" = disk ] || set -- --repart-offline=yes "$@"
          [ -n "$variant" ] && set -- --dependency "$variant" "$@"
          mkosi -B -f -C "$BUILD" "$@"
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

      ## quick start

          ansible-playbook -i 'localhost,' -c local mkosi.src.pb
          cd /usr/local/src/mkosi-git
          bin/image.sh                          # build default subimage (oci)
          bin/image.sh disk                     # full disk image, universal layout
          MKOSI_DATE=20260901 bin/image.sh disk # explicit slot date
          bin/vps-seed.sh myseed                # host-tailored initrd (this kernel)
          bin/identity.sh --first-boot /mnt     # de-identify a mounted clone

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
        artifact); `Dependencies=oci` selects which subimages build (vps-seed
        dropped from the default: upstream mkosi-initrd dpkg-strip bug on
        trixie, see the conf comment).
      - `mkosi.images/vps-seed/` — bootable cpio initrd (`Include=mkosi-initrd`
        + ext4/xfs/btrfs/dos formatting tools). xz level 6 (commented zstd 15).
        **Generic** — does NOT inject host kernel modules; for a host-tailored
        initrd use `vps-seed.sh`. **Currently broken on trixie** (upstream
        mkosi-initrd `RemovePackages=dpkg` purge cascade fails); not in the
        default `Dependencies=`.
      - `mkosi.images/oci/` — base Debian rootfs as an OCI container image.
      - `mkosi.images/disk/` — **sample** full disk image that consumes the
        compfuzor `PKGSETS` list. `Bootable=yes`, and its `mkosi.repart/` makes
        the root a **btrfs on the universal kit scheme**: OS in subvol
        `/root/superbfowle/<arch>/<yyyymmdd>` (the default subvol; not
        top-level subvolid 5) plus a dated `/home/superbfowle/<yyyymmdd>`
        home subvol. 10-root.conf embeds files/repart/defs/format.d/50-root.conf
        verbatim and adds only CopyFiles/MountPoint — the subvolume layout is
        declared in ONE place. Not in
        default `Dependencies=` (heavy) — build with `image.sh disk`. See
        "wiring PKGSETS into a subimage" below.

      To add a build: drop another `mkosi.images/<name>/mkosi.conf`. Build one
      with `image.sh <name>` (no bin edit needed). Note: mkosi's `--dependency`
      **appends** to the main's `Dependencies=` rather than replacing it, so
      `image.sh disk` builds disk *plus* the default lean set (vps-seed, oci);
      to isolate one, comment the main's `Dependencies=` line.

      ## wiring PKGSETS into a subimage

      The compfuzor package-list machinery (`MKOSI_PKGSETS` → `lookup('pkgs')`
      → the same list that renders `etc/pkgs.txt`) renders into a subimage's
      `Packages=`. mkosi **merges multiple `Packages=` lines**, so we emit one
      commented line per pkgset for easy review:

          [Content]
          {% for setname in MKOSI_PKGSETS %}# {{ setname }} ({{ lookup('pkgs', setname) | length }})
          Packages={{ (lookup('pkgs', setname) | unique) | join(',') }}
          {% endfor %}

      (`lookup('pkgs', setname)` resolves just that one set.) Toggle which sets
      resolve via `MKOSI_PKGSETS` at the top of the playbook (currently `BASE,
      BASE_amd64` = 238 pkgs; uncomment the rest for a ~1000-pkg workstation
      image). Use this for full disk/workstation subimages — keep initrd/oci
      subimages lean with explicit `Packages=`.

      ## apt caching

      `APT_PROXY` (default `http://127.0.0.1:3142/` — this host's apt-cacher-rs
      from `apt-cacher-rs.src.pb`) renders `[Build] ProxyUrl=` into
      `etc/mkosi.conf`. ProxyUrl is multiversal in mkosi: one line proxies the
      tools tree **and** every subimage — mkosi passes
      `Acquire::http(s)::Proxy=` to apt and exports `http_proxy`/`https_proxy`
      into the build sandbox (which shares the host netns, so loopback
      reaches the daemon). Build with `-e APT_PROXY=` to drop it for
      portable/offline configs. Watch it work: <http://127.0.0.1:3142/> while
      `image.sh` runs.

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
