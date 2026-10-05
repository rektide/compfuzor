---
# rimworld.opt.pb — automounted dwarfs + rw-overlay stack for the RimWorld
# jc141 repack at /mnt/bitblaster/torrent/RimWorld-jc141.
#
# Two system automounts; access composes the whole stack, idle tears it
# down. No services, no cleanup logic — and one launcher bin:
#
#   /mnt/dwarfs/rimworld   ro dwarfs layer (Type=dwarfs, system dwarfs)
#   /mnt/rimworld          rw overlay (Type=fuse-overlayfs: lower=dwarfs,
#                           upper/work under STATE_DIR; the game tree with
#                           mods/updates)
#
#   ls /mnt/rimworld  ->  automount triggers overlay mount  ->  fuse-overlayfs
#                         opens lowerdir  ->  triggers dwarfs automount
#   idle               ->  overlay unmounts; dwarfs follows on its own idle
#
# bin/run.sh is the launcher entrypoint (what Lutris points at): a port of
# jc141's start.n.sh + actions.sh bwrap-run_in_sandbox (native branch) onto
# the automount stack. It arms the overlay, then runs RimWorldLinux itself
# (it is the runner) inside bwrap with a fake $HOME (STATE_DIR/home,
# jc141's native-docs concept) so saves/config never touch the real $HOME,
# optionally without network. Usage and knobs: see the deployed README.
#
# Dependencies:
#   dwarfs.src.pb        system dwarfs + /usr/sbin/mount.dwarfs bridge
#   fuse-overlayfs.etc.pb  /usr/sbin/mount.fuse-overlayfs helper (Debian
#                          ships none; .mount units cannot mount without it)
#
# All mutable state lives under STATE_DIR (one portable per-game dir,
# XDG-flavored default): overlay/{upper,work} and home/ (the fake game
# $HOME, jc141's native-docs concept). The torrent dir stays pristine —
# only the image is read from it.
#
#   ansible-playbook -i 'localhost,' -c local rimworld.opt.pb
#   ls /mnt/rimworld                          # play goes here (Lutris etc.)
#
# Vars (optional, -e overrides):
#   game_dir    release root (default the path above)
#   ro_where    ro mountpoint (default /mnt/dwarfs/rimworld)
#   where       rw mountpoint (default /mnt/rimworld)
#   state_dir   per-game state root (default ~/.local/share/rimworld)
#   idle        automount TimeoutIdleSec (default 10min)
#   cachesize   dwarfs block cache, default 25% of RAM (e.g. 4g)
#
# run.sh runtime knobs (ISOLATE/BLOCK_NET/SANDBOX_HOME/GAME_BIN, `-- CMD`)
# are documented in the deployed README.md.
- hosts: all
  vars:
    TYPE: rimworld
    INSTANCE: main
    GAME_DIR: "{{game_dir|default('/mnt/bitblaster/torrent/RimWorld-jc141')}}"
    IMAGE: "{{GAME_DIR}}/files/game-root.dwarfs"
    RO_WHERE: "{{ro_where|default('/mnt/dwarfs/rimworld')}}"
    WHERE: "{{where|default('/mnt/rimworld')}}"
    STATE_DIR: "{{state_dir|default(ansible_user_dir ~ '/.local/share/' + TYPE)}}"
    UPPER: "{{STATE_DIR}}/overlay/upper"
    WORK: "{{STATE_DIR}}/overlay/work"
    RO_UNIT: "{{ lookup('pipe', 'systemd-escape --path ' ~ RO_WHERE) }}"
    RW_UNIT: "{{ lookup('pipe', 'systemd-escape --path ' ~ WHERE) }}"
    SQUASH_UID: "{{ansible_user_uid}}"
    SQUASH_GID: "{{ansible_user_gid}}"
    # jc141 defaults: cachesize = 25% of MemTotal; tidy evicts after 30m
    CACHESIZE: "{{cachesize|default((ansible_memtotal_mb*1024*25/100)|int ~ 'k')}}"
    DWARFS_OPTS: "ro,allow_other,cachesize={{CACHESIZE}},clone_fd,tidy_strategy=time,tidy_interval=15m,tidy_max_age=30m"
    OVERLAY_OPTS: "lowerdir={{RO_WHERE}},upperdir={{UPPER}},workdir={{WORK}},squash_to_uid={{SQUASH_UID}},squash_to_gid={{SQUASH_GID}},allow_other"
    DIRS:
      - "{{UPPER}}"
      - "{{WORK}}"
      - "{{STATE_DIR}}/home"
    BINS:
      - name: run.sh
        basedir: False
        content: |
          # sandboxed rimworld runner — jc141 semantics; docs in README.md

          # knobs (caller env overrides; paths come from env.export)
          : "${ISOLATE:=1}"
          : "${BLOCK_NET:=1}"
          : "${GAME_BIN:=RimWorldLinux}"
          SANDBOX_HOME="${SANDBOX_HOME:-$STATE_DIR/home}"

          # arm the rw overlay: path lookups trigger the autofs
          # synchronously, and autofs will not fire inside bwrap's mount
          # namespace later
          tries=0
          until ls -- "$WHERE" >/dev/null 2>&1 \
              && [[ "$(findmnt -rno FSTYPE -- "$WHERE" 2>/dev/null || true)" == *fuse-overlayfs ]]; do
            tries=$((tries + 1))
            if [ "$tries" -ge 30 ]; then
              echo "run.sh: $WHERE did not automount (wanted fuse-overlayfs)" >&2
              exit 1
            fi
            sleep 2
          done

          # command: the game binary by default — we are the runner, so the
          # stock start_RimWorld.sh's semantics (LC_ALL reset, exec-bit
          # guard) live here. `-- CMD` runs an arbitrary command instead
          # (test seam).
          if [ "${1:-}" = "--" ]; then
            shift
            [ "$#" -gt 0 ] || { echo "run.sh: -- needs a command" >&2; exit 2; }
          else
            [ -x "$WHERE/$GAME_BIN" ] || chmod +x -- "$WHERE/$GAME_BIN"
            export LC_ALL=C
            set -- "./$GAME_BIN" "$@"
          fi

          # unsandboxed escape hatch (jc141's ISOLATE=0)
          if [ "$ISOLATE" != 1 ] || ! command -v bwrap >/dev/null 2>&1; then
            cd -- "$WHERE"
            exec "$@"
          fi

          # sandbox home (jc141 native-docs): saves/config stay out of the
          # real $HOME
          mkdir -p -- "$SANDBOX_HOME"
          [ -z "${XDG_RUNTIME_DIR:-}" ] && export XDG_RUNTIME_DIR="/run/user/$(id -u)"

          # X11 cookie dance (jc141): copy the authority into the sandbox
          # home and point XAUTHORITY at $HOME/.Xauthority — SANDBOX_HOME
          # is bound over $HOME below, so the path resolves inside.
          # wayland-only sessions (or a stale XAUTHORITY) skip this.
          if [ -n "${XAUTHORITY:-}" ] && [ -e "$XAUTHORITY" ] && [ ! -e "$SANDBOX_HOME/.Xauthority" ]; then
            ln -- "$XAUTHORITY" "$SANDBOX_HOME/.Xauthority" 2>/dev/null \
              || cp -- "$XAUTHORITY" "$SANDBOX_HOME/.Xauthority"
          fi
          [ -e "$SANDBOX_HOME/.Xauthority" ] && export XAUTHORITY="$HOME/.Xauthority"

          BWRAP_FLAGS=(
            --ro-bind / /
            --dev-bind-try /dev /dev
            --bind-try /tmp /tmp
            --bind-try "$SANDBOX_HOME" "$HOME"
          )
          [ "$BLOCK_NET" = 1 ] && BWRAP_FLAGS+=( --unshare-net )
          # game dir rw, as the last setting (jc141 ordering), plus cwd
          BWRAP_FLAGS+=( --bind "$WHERE" "$WHERE" --chdir "$WHERE" )

          exec bwrap "${BWRAP_FLAGS[@]}" "$@"
    ENV:
      GAME_DIR: "{{GAME_DIR}}"
      IMAGE: "{{IMAGE}}"
      RO_WHERE: "{{RO_WHERE}}"
      WHERE: "{{WHERE}}"
      STATE_DIR: "{{STATE_DIR}}"
      UPPER: "{{UPPER}}"
      WORK: "{{WORK}}"
    README: |
      # RimWorld (jc141 repack)

      Dwarfs-compressed RimWorld on a systemd-automounted two-layer stack,
      with a sandboxed runner recreating jc141's bwrap isolation (native
      branch) — see design/jc141-dwarfs/ in the compfuzor repo.

      ## Run

          /opt/rimworld-main/bin/run.sh            # game, sandboxed, no network
          /opt/rimworld-main/bin/run.sh -- CMD     # CMD inside the sandbox (testing)

      Point Lutris / any launcher at run.sh; extra args pass to RimWorldLinux.

      ## What run.sh does

      1. Arms the /mnt/rimworld automount — autofs never fires inside
         bwrap's mount namespace, so the overlay must be up first.
      2. execs RimWorldLinux with LC_ALL=C directly (the stock
         start_RimWorld.sh semantics — this script is the runner).
      3. Sandbox, jc141-faithful and porous by design: --ro-bind / /,
         /dev, shared /tmp; fake $HOME so saves/config never touch your
         real $HOME; --unshare-net; game dir rw and bound last, --chdir
         into it; Xauthority copied in for X11 sessions.
      4. Idle (10min per unit) unmounts both layers; the next run re-arms.

      ## Knobs (caller env overrides)

      | var           | default          | meaning                        |
      |---------------|------------------|--------------------------------|
      | ISOLATE       | 1                | 0 = run unsandboxed            |
      | BLOCK_NET     | 1                | 0 = allow network              |
      | SANDBOX_HOME  | $STATE_DIR/home  | fake $HOME                     |
      | GAME_BIN      | RimWorldLinux    | binary the runner execs        |

      Example: `BLOCK_NET=0 /opt/rimworld-main/bin/run.sh`

      ## Layout

      | path                                    | role                          |
      |-----------------------------------------|-------------------------------|
      | /mnt/dwarfs/rimworld                    | ro dwarfs layer (detail)      |
      | /mnt/rimworld                           | rw overlay (game tree, mods)  |
      | ~/.local/share/rimworld/overlay/{upper,work} | overlay backing         |
      | ~/.local/share/rimworld/home            | sandbox $HOME (saves/config)  |

      Unity writes player data under `$HOME/.config/unity3d/Ludeon
      Studios/RimWorld by Ludeon Studios` — inside the sandbox that is the
      home dir above, not your real one.

      Don't run the stock jc141 start.n.sh while these units are active.
    SYSTEMD_ROOTS:
      - RO_MOUNT
      - RO_AUTOMOUNT
      - RW_MOUNT
      - RW_AUTOMOUNT
    RO_MOUNT:
      SYSTEMD_MOUNT: "{{RO_UNIT}}"
      # .mount units never enable directly; the automount pulls them in.
      SYSTEMD_ENABLE: false
      SYSTEMD_INSTALLS: false
      SYSTEMD_UNITS:
        Description: "rimworld dwarfs ro layer {{IMAGE}}"
      SYSTEMD_MOUNTS:
        What: "{{IMAGE}}"
        Where: "{{RO_WHERE}}"
        Type: dwarfs
        Options: "{{DWARFS_OPTS}}"
        TimeoutSec: 60
    RO_AUTOMOUNT:
      SYSTEMD_AUTOMOUNT: "{{RO_UNIT}}"
      SYSTEMD_UNITS:
        Description: "rimworld dwarfs lazy mount {{RO_WHERE}}"
      SYSTEMD_AUTOMOUNTS:
        Where: "{{RO_WHERE}}"
        DirectoryMode: "0755"
        TimeoutIdleSec: "{{idle|default('10min')}}"
    RW_MOUNT:
      SYSTEMD_MOUNT: "{{RW_UNIT}}"
      SYSTEMD_ENABLE: false
      SYSTEMD_INSTALLS: false
      SYSTEMD_UNITS:
        Description: "rimworld rw overlay {{WHERE}}"
        # Require the ro MOUNT, not just its automount: with only the
        # automount required, the overlay helper can race ahead of the
        # dwarfs trigger, scan an untriggered (empty) lowerdir, and mount
        # an empty view that never re-scans. Requiring the .mount makes
        # systemd mount the dwarfs layer first, on demand.
        Requires: "{{RO_UNIT}}.mount"
        After: "{{RO_UNIT}}.mount"
      SYSTEMD_MOUNTS:
        What: overlay
        Where: "{{WHERE}}"
        Type: fuse-overlayfs
        Options: "{{OVERLAY_OPTS}}"
        TimeoutSec: 60
    RW_AUTOMOUNT:
      SYSTEMD_AUTOMOUNT: "{{RW_UNIT}}"
      SYSTEMD_UNITS:
        Description: "rimworld rw overlay lazy mount {{WHERE}}"
      SYSTEMD_AUTOMOUNTS:
        Where: "{{WHERE}}"
        DirectoryMode: "0755"
        TimeoutIdleSec: "{{idle|default('10min')}}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
