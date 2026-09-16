---
- hosts: all
  vars:
    TYPE: steamos-offload
    INSTANCE: main

    # Bootstrap state must not depend on either mount that this deployment
    # creates. /opt is already a native SteamOS offload.
    ETC: "{{DIR}}/etc"
    ETC_DIR: true
    ETC_LINK_BYPASS: true
    LINKS_BYPASS: true

    STEAMOS_OFFLOAD_ROOT: /home/.steamos/offload
    STEAMOS_OFFLOAD_ADMIN: "{{STEAMOS_OFFLOAD_ROOT}}/.compfuzor"
    STEAMOS_OFFLOADS:
      - id: usr-local
        where: /usr/local
        relative: usr/local
        what: "{{STEAMOS_OFFLOAD_ROOT}}/usr/local"
      - id: etc-opt
        where: /etc/opt
        relative: etc/opt
        what: "{{STEAMOS_OFFLOAD_ROOT}}/etc/opt"

    # Copy the bootstrap units into /etc/systemd/system. A symlink back into
    # /opt may be unresolved when systemd first discovers units during boot.
    SYSTEMD_INSTALL_STRATEGY: copy
    SYSTEMD_ROOTS:
      - STEAMOS_OFFLOAD_SEED
      - STEAMOS_OFFLOAD_USR_LOCAL
      - STEAMOS_OFFLOAD_ETC_OPT

    STEAMOS_OFFLOAD_SEED:
      SYSTEMD_SERVICE: steamos-offload-seed
      SYSTEMD_UNITS:
        Description: Seed persistent SteamOS offload trees
        # String form is intentional: boolean false suppresses a directive in
        # the generic unit renderer, while systemd needs the directive emitted.
        DefaultDependencies: "false"
        RequiresMountsFor:
          - /home/.steamos/offload
          - /opt
        Before:
          - usr-local.mount
          - etc-opt.mount
      SYSTEMD_SERVICES:
        Type: oneshot
        ExecStart: "{{DIR}}/bin/seed-offloads.sh"
        RemainAfterExit: true
      SYSTEMD_INSTALLS:
        WantedBy: holo-offload.target

    STEAMOS_OFFLOAD_USR_LOCAL:
      SYSTEMD_MOUNT: usr-local
      SYSTEMD_UNITS:
        Description: Persistent SteamOS /usr/local
        Requires: steamos-offload-seed.service
        After: steamos-offload-seed.service
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
        Requires: steamos-offload-seed.service
        After: steamos-offload-seed.service
      SYSTEMD_MOUNTS:
        What: "{{STEAMOS_OFFLOAD_ROOT}}/etc/opt"
        Where: /etc/opt
        Type: none
        Options: bind
      SYSTEMD_INSTALLS:
        WantedBy: holo-offload.target

    BINS:
      - name: seed-offloads.sh
        basedir: false
        compose: false
        content: |
          if [ "$(id -u)" -ne 0 ] && [ "${STEAMOS_OFFLOAD_ALLOW_NON_ROOT:-0}" != 1 ]; then
            echo "seed-offloads: run as root" >&2
            exit 1
          fi

          force=0
          case "${1:-}" in
            "") ;;
            --force) force=1 ;;
            -h|--help)
              echo "Usage: $0 [--force]"
              exit 0
              ;;
            *) echo "seed-offloads: unknown argument: $1" >&2; exit 2 ;;
          esac

          # shellcheck disable=SC1091
          . /etc/os-release
          build_id="${STEAMOS_BUILD_ID:-${BUILD_ID:-${VERSION_ID:-unknown}}}"
          build_key=$(printf '%s' "$build_id" | tr -c 'A-Za-z0-9._-' '_')
          source_root=${STEAMOS_OFFLOAD_SOURCE_ROOT:-}
          source_root=${source_root%/}
          offload_root=${STEAMOS_OFFLOAD_ROOT:-{{STEAMOS_OFFLOAD_ROOT}}}
          offload_root=${offload_root%/}
          admin=${STEAMOS_OFFLOAD_ADMIN:-$offload_root/.compfuzor}
          mkdir -p "$admin/archive" "$admin/seeded"
          exec 9>"$admin/seed.lock"
          flock 9

          offloads=(
          {% for offload in STEAMOS_OFFLOADS %}  {{ (offload.id ~ '|' ~ offload.where ~ '|' ~ offload.relative)|quote }}
          {% endfor %})

          for spec in "${offloads[@]}"; do
            IFS='|' read -r id where_path relative <<<"$spec"
            where="$source_root$where_path"
            what="$offload_root/$relative"
            stamp="$admin/seeded/$id/$build_key"

            if mountpoint -q "$where"; then
              echo "seed-offloads: $where is already mounted; leaving it unchanged"
              continue
            fi
            if [ "$force" -eq 0 ] && [ -f "$stamp" ]; then
              echo "seed-offloads: $id already seeded for $build_id"
              continue
            fi

            mkdir -p "$where" "$what" "$(dirname "$stamp")"
            timestamp=$(date -u +%Y%m%dT%H%M%SZ)
            archive="$admin/archive/$id/$build_key/$timestamp"
            mkdir -p "$archive"

            echo "seed-offloads: overlaying $where onto $what"
            rsync -aHAXx --numeric-ids --itemize-changes \
              --backup --backup-dir="$archive" \
              "$where/" "$what/"

            tmp="$stamp.tmp.$$"
            {
              printf 'build_id=%s\n' "$build_id"
              printf 'seeded_at=%s\n' "$timestamp"
              printf 'source=%s\n' "$where"
              printf 'backing=%s\n' "$what"
              printf 'archive=%s\n' "$archive"
            } >"$tmp"
            mv -f "$tmp" "$stamp"
          done
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        # /opt is a native SteamOS offload and is available independently of
        # the two mounts generated by this playbook.
        type: opt
