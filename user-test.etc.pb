---
- hosts: all
  vars:
    # Test-account factory: throwaway shell users for rehearsing user-scope
    # compfuzor installs (zim2/mise2 with USERMODE=True) without polluting
    # real accounts. Users land in a UID/GID band above the normal range
    # (login.defs UID_MAX/GID_MAX is 60000; default band 61000-61199), and
    # the operator gets passwordless sudo TO them (never from them):
    #
    #   ansible-playbook -i 'localhost,' -c local user-test.etc.pb -e USER_TEST_USERS=zimtest
    #   sudo -u zimtest -H zsh -lc 'id; echo $HOME'
    #   /etc/opt/user-test/bin/user-remove.sh zimtest   # manual teardown
    #
    # user-add/user-status run during the playbook via become (useradd,
    # /etc/sudoers.d writes); gate them with BINS_RUN_BYPASS=True like any
    # other subsystem. user-remove is manual-only.
    USER_TEST_BASE_UID: 61000
    USER_TEST_UID_SPAN: 200
    USER_TEST_SHELL: /usr/bin/zsh
    USER_TEST_OPERATOR: rektide
    # Space- or comma-separated names; empty means "factory idle".
    USER_TEST_USERS: ""
    BINS:
      - name: user-add.sh
        run: true
        become: true
        vars: [USER_TEST_BASE_UID, USER_TEST_UID_SPAN, USER_TEST_SHELL, USER_TEST_OPERATOR, USER_TEST_USERS]
        content: |
          # Create throwaway shell users in a high UID/GID band (default
          # 61000-61199, above login.defs UID_MAX/GID_MAX=60000) with a
          # matching per-user group, plus a passwordless operator->user sudo
          # grant. Existing users must have matching UID/GID in the test band;
          # their account settings stay untouched and grants refresh.
          set -euo pipefail

          users=("$@")
          if [ ${{'{#'}}users[@]} -eq 0 ]; then
            read -r -a users <<<"${USER_TEST_USERS//,/ }"
          fi
          if [ ${{'{#'}}users[@]} -eq 0 ] || [ -z "${users[0]:-}" ]; then
            echo "user-test: no users requested (args or USER_TEST_USERS); nothing to do"
            exit 0
          fi

          base=${USER_TEST_BASE_UID:-61000}
          span=${USER_TEST_UID_SPAN:-200}
          shell=${USER_TEST_SHELL:-/usr/bin/zsh}
          operator=${USER_TEST_OPERATOR:-${SUDO_USER:-rektide}}

          if ! [[ "$base" =~ ^[1-9][0-9]{0,9}$ && "$span" =~ ^[1-9][0-9]{0,9}$ ]] ||
             (( base <= 60000 || base + span > 4294967295 )); then
            echo "user-test: invalid test UID band (must be above 60000)" >&2
            exit 1
          fi
          for name in "$operator" "${users[@]}"; do
            if ! [[ "$name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
              echo "user-test: unsafe account name: $name" >&2
              exit 1
            fi
          done

          for name in "${users[@]}"; do
            if ent=$(getent passwd "$name"); then
              IFS=: read -r _ _ uid gid _ _ _ <<<"$ent"
              group_gid=$(getent group "$name" | cut -d: -f3) || group_gid=
              if (( uid < base || uid >= base + span )) ||
                 [ "$uid" != "$gid" ] || [ "$gid" != "$group_gid" ]; then
                echo "user-test: refusing existing non-test account $name" >&2
                exit 1
              fi
              echo "user-test: $name exists ($(id "$name"))"
            else
              if getent group "$name" >/dev/null; then
                echo "user-test: refusing existing group $name without a matching test user" >&2
                exit 1
              fi
              # Stable start, wrapping within the band; visit each slot once.
              start=$(( $(printf '%s' "$name" | cksum | cut -d' ' -f1) % span ))
              for (( attempt=0; attempt<span; attempt++ )); do
                uid=$(( base + (start + attempt) % span ))
                if ! getent passwd "$uid" >/dev/null 2>&1 && ! getent group "$uid" >/dev/null 2>&1; then
                  break
                fi
              done
              if (( attempt == span )); then
                echo "user-test: test UID/GID band exhausted" >&2
                exit 1
              fi
              groupadd -g "$uid" "$name"
              useradd -m -u "$uid" -g "$name" -s "$shell" "$name"
              echo "user-test: created $name (uid/gid $uid, shell $shell)"
            fi

            # sudoers.d names must not contain '.' or sudo ignores them.
            sudoers=/etc/sudoers.d/61-user-test-$name
            entry="$operator ALL=($name) NOPASSWD: ALL"
            if [ -f "$sudoers" ] && [ "$(cat "$sudoers")" = "$entry" ]; then
              echo "user-test: sudo grant $operator -> $name already current"
            else
              # Dot keeps the temporary file out of sudoers.d's include set.
              pending=$(mktemp /etc/sudoers.d/.61-user-test-XXXXXX)
              trap 'rm -f -- "$pending"' EXIT
              printf '%s\n' "$entry" >"$pending"
              chmod 0440 "$pending"
              visudo -cf "$pending" >/dev/null
              mv -f -- "$pending" "$sudoers"
              trap - EXIT
              echo "user-test: granted $operator passwordless sudo to $name"
            fi
          done
      - name: user-status.sh
        run: true
        become: true
        vars: [USER_TEST_USERS]
        content: |
          # Report test users, their homes, and operator sudo grants.
          set -euo pipefail

          users=("$@")
          if [ ${{'{#'}}users[@]} -eq 0 ]; then
            read -r -a users <<<"${USER_TEST_USERS//,/ }"
          fi
          if [ ${{'{#'}}users[@]} -eq 0 ] || [ -z "${users[0]:-}" ]; then
            echo "user-test: no users requested (args or USER_TEST_USERS); nothing to do"
            exit 0
          fi

          for name in "${users[@]}"; do
            if ! [[ "$name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
              echo "user-test: unsafe account name: $name" >&2
              exit 1
            fi
            echo "== $name =="
            if ! ent=$(getent passwd "$name"); then
              echo "user: absent"
            else
              echo "$ent"
              home=$(getent passwd "$name" | cut -d: -f6)
              if [ -d "$home" ]; then
                echo "home: $home ($(stat -c '%U:%G %a' "$home"))"
              else
                echo "home: $home (missing)"
              fi
            fi
            sudoers=/etc/sudoers.d/61-user-test-$name
            if [ -f "$sudoers" ]; then
              echo "sudoers: $(cat "$sudoers")"
            else
              echo "sudoers: none"
            fi
          done
      - name: user-remove.sh
        vars: [USER_TEST_BASE_UID, USER_TEST_UID_SPAN, USER_TEST_USERS]
        content: |
          # Remove test users (home + mail spool) and their sudo grants.
          # Manual-only counterpart to user-add.sh.
          set -euo pipefail

          users=("$@")
          if [ ${{'{#'}}users[@]} -eq 0 ]; then
            read -r -a users <<<"${USER_TEST_USERS//,/ }"
          fi
          if [ ${{'{#'}}users[@]} -eq 0 ] || [ -z "${users[0]:-}" ]; then
            echo "user-test: no users requested (args or USER_TEST_USERS); nothing to do"
            exit 0
          fi

          base=${USER_TEST_BASE_UID:-61000}
          span=${USER_TEST_UID_SPAN:-200}
          if ! [[ "$base" =~ ^[1-9][0-9]{0,9}$ && "$span" =~ ^[1-9][0-9]{0,9}$ ]] ||
             (( base <= 60000 || base + span > 4294967295 )); then
            echo "user-test: invalid test UID band (must be above 60000)" >&2
            exit 1
          fi
          for name in "${users[@]}"; do
            if ! [[ "$name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
              echo "user-test: unsafe account name: $name" >&2
              exit 1
            fi
          done

          for name in "${users[@]}"; do
            if ent=$(getent passwd "$name"); then
              IFS=: read -r _ _ uid gid _ _ _ <<<"$ent"
              group_gid=$(getent group "$name" | cut -d: -f3) || group_gid=
              if (( uid < base || uid >= base + span )) ||
                 [ "$uid" != "$gid" ] || [ "$gid" != "$group_gid" ]; then
                echo "user-test: refusing existing non-test account $name" >&2
                exit 1
              fi
              userdel -r "$name"
              # userdel may already have removed the private group.
              if ent=$(getent group "$name"); then
                group_gid=$(cut -d: -f3 <<<"$ent")
                if [ "$group_gid" = "$gid" ]; then
                  groupdel "$name"
                fi
              fi
              echo "user-test: removed user $name"
            else
              echo "user-test: user $name absent"
            fi
            sudoers=/etc/sudoers.d/61-user-test-$name
            if [ -f "$sudoers" ]; then
              rm -f "$sudoers"
              echo "user-test: removed $sudoers"
            fi
          done
  tasks:
    - import_tasks: tasks/compfuzor.includes
