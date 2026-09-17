---
- hosts: all
  vars:
    TYPE: steamos-offload
    INSTANCE: main

    # Bootstrap state must not depend on either mount this deployment creates;
    # /srv is already a native SteamOS offload mount.
    ETC: "{{DIR}}/etc"
    ETC_DIR: true
    ETC_LINK_BYPASS: true
    LINKS_BYPASS: true

    STEAMOS_OFFLOAD_ROOT: /home/.steamos/offload

    # Plain bind mounts, mirroring Valve's own opt.mount/srv.mount. Copy the
    # units into /etc/systemd/system: a symlink back into /srv may dangle when
    # systemd first discovers units during early boot.
    SYSTEMD_INSTALL_STRATEGY: copy
    SYSTEMD_ROOTS:
      - STEAMOS_OFFLOAD_USR_LOCAL
      - STEAMOS_OFFLOAD_ETC_OPT

    STEAMOS_OFFLOAD_USR_LOCAL:
      SYSTEMD_MOUNT: usr-local
      SYSTEMD_UNITS:
        Description: Persistent SteamOS /usr/local
        ConditionPathExists: "{{STEAMOS_OFFLOAD_ROOT}}/usr/local"
      SYSTEMD_MOUNTS:
        What: "{{STEAMOS_OFFLOAD_ROOT}}/usr/local"
        Where: /usr/local
        Type: none
        Options: bind
      SYSTEMD_INSTALLS:
        WantedBy: holo-offload.target

    STEAMOS_OFFLOAD_ETC_OPT:
      SYSTEMD_MOUNT: etc-opt
      SYSTEMD_UNITS:
        Description: Persistent SteamOS /etc/opt
        ConditionPathExists: "{{STEAMOS_OFFLOAD_ROOT}}/etc/opt"
      SYSTEMD_MOUNTS:
        What: "{{STEAMOS_OFFLOAD_ROOT}}/etc/opt"
        Where: /etc/opt
        Type: none
        Options: bind
      SYSTEMD_INSTALLS:
        WantedBy: holo-offload.target

    # Manual first-activation helper: overlay the image's /usr/local and
    # /etc/opt onto the offload backing trees before the mounts are enabled.
    # Replaced files are archived under .seed-backup/. Run once with sudo.
    BINS:
      - name: seed.sh
        basedir: false
        compose: false
        content: |
          if [ "$(id -u)" -ne 0 ]; then
            echo "seed.sh: run with sudo, before the mounts are enabled" >&2
            exit 1
          fi
          root={{STEAMOS_OFFLOAD_ROOT}}
          mkdir -p "$root/usr/local" "$root/etc/opt"
          ts=$(date -u +%Y%m%dT%H%M%SZ)
          for rel in usr/local etc/opt; do
            if mountpoint -q "/$rel"; then
              echo "seed.sh: /$rel is mounted; skipping"
              continue
            fi
            echo "seed.sh: /$rel -> $root/$rel"
            rsync -aHAXx --numeric-ids --backup --backup-dir="$root/.seed-backup/$ts" "/$rel/" "$root/$rel/"
          done
          echo "seed.sh: done; replaced files (if any) archived under $root/.seed-backup/$ts"
  tasks:
    - import_tasks: tasks/compfuzor.includes

    # Bind sources live on the persistent home partition. usr/local already
    # holds the pre-update tree; etc/opt is created on first run. The mounts'
    # ConditionPathExists keeps boot ordering safe if a source is absent.
    - name: ensure /usr/local offload backing
      ansible.builtin.file:
        path: "{{STEAMOS_OFFLOAD_ROOT}}/usr/local"
        state: directory
      become: "{{ _become.become }}"
      vars:
        _become: "{{ (STEAMOS_OFFLOAD_ROOT ~ '/usr/local')|become_calc }}"
    - name: ensure /etc/opt offload backing
      ansible.builtin.file:
        path: "{{STEAMOS_OFFLOAD_ROOT}}/etc/opt"
        state: directory
      become: "{{ _become.become }}"
      vars:
        _become: "{{ (STEAMOS_OFFLOAD_ROOT ~ '/etc/opt')|become_calc }}"
