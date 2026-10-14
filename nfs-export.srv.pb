---
# nfs-export.srv.pb — export a directory over the kernel NFS server.
#
# Declares ONE exports(5) fragment: materialized under DIR/etc/ (the etc
# hierarchy; default /srv/nfs-export-test/etc/nfs-export-test.exports,
# exposed at /etc/opt/nfs-export-test) and published into
# /etc/exports.d/<NAME>.exports by the LINKS subsystem. The generated
# bin/install-nfs-export.sh joins bin/install.sh in the `units` lane and,
# in order: applies the fragment's link record through bin/links.mjs
# (exactly like the systemd unit installers publish their unit), creates
# the export root only when missing, enables/starts the distro
# nfs-server.service, then converges kernel state for exactly the declared
# clients with `exportfs -i -o <opts> <client>:<path>`. These updates do not
# reconcile other declarations; the distro unit still owns host-wide startup
# and shutdown semantics.
#
#   ansible-playbook -i 'localhost,' -c local nfs-export.srv.pb
#   sudo bash /srv/nfs-export-test/bin/install.sh
#   ansible-playbook -i 'localhost,' -c local nfs-export.srv.pb \
#     -e INSTANCE=media -e export_path=/srv/media \
#     -e '{"clients": ["10.0.0.0/24", "fileserver.lan"]}'
#
# Vars (optional, -e overrides):
#   export_path   exported directory (default /srv/nfs-<INSTANCE>). Must be
#                 absolute and not /; created by the installer only when
#                 missing, owned by the rendering user's uid/gid so a nonroot
#                 install can stage content without sudo afterwards.
#   clients       client specs, list of strings (default 127.0.0.1). IPv4
#                 addresses/CIDRs, hostnames, wildcards, @netgroups only:
#                 exports(5) wants bare IPv6 literals while the exportfs
#                 CLI brackets them, so IPv6 clients are rejected instead
#                 of silently misapplied. Bare '*' (world) is refused.
#   export_opts   option list applied to every client
#                 (default rw,sync,no_subtree_check,root_squash)
#   nfs_service   distro unit to enable/start (default nfs-server.service;
#                 no replacement unit is generated here)
#   export_owner / export_group / export_mode
#                 ownership/mode applied to a NEWLY created export root
#                 (never to pre-existing data); COMPFUZOR-style env knobs
#                 NFS_EXPORT_OWNER/NFS_EXPORT_GROUP/NFS_EXPORT_MODE
#                 override at install time
# Installer disarms at runtime: COMPFUZOR_NFS_EXPORT_BYPASS,
# COMPFUZOR_LINK_BYPASS, COMPFUZOR_FS_BYPASS.
- hosts: all
  vars:
    TYPE: nfs-export
    INSTANCE: test
    EXPORT_PATH: "{{ export_path|default('/srv/nfs-' + INSTANCE) }}"
    CLIENTS: "{{ clients|default(['127.0.0.1'])|normalize(to='list') }}"
    EXPORT_OPTS: "{{ export_opts|default('rw,sync,no_subtree_check,root_squash') }}"
    NFS_SERVICE: "{{ nfs_service|default('nfs-server.service') }}"
    PKGS: [nfs-kernel-server]
    ARCH_PKGS: [nfs-utils]
    ETC_FILES:
      - name: "{{NAME}}.exports"
        mode: "0644"
        content: |
          # managed by compfuzor: nfs-export.srv.pb deployment {{NAME}}
          {{EXPORT_PATH}}{% for _client in CLIENTS %} {{_client}}({{EXPORT_OPTS}}){% endfor %}
    LINKS:
      # links.mjs owns the /etc/exports.d publication: status drift,
      # audit cross-checks, remove uninstall. install-nfs-export.sh
      # applies this record (baked LINK_ID) before starting the service.
      - src: "{{DIR}}/etc/{{NAME}}.exports"
        dest: "/etc/exports.d/{{NAME}}.exports"
        scope: system
        policy: replace
    BINS:
      - name: install-nfs-export.sh
        # Not auto-run at render: `sudo bash bin/install.sh` invokes it in
        # the `units` lane, after artifact installs and before the records
        # lane (install-links.sh re-applies records as bookkeeping).
        bypass: ["LINK", "NFS_EXPORT", "FS"]
        phase: units
        generated: |
          # Apply this deployment's NFS export: publish the /etc/exports.d
          # fragment through LINKS, then converge kernel state for exactly
          # the declared clients.
          NFS_EXPORT_LINK_ID='system:/etc/exports.d/{{NAME}}.exports'
          EXPORT_PATH='{{EXPORT_PATH}}'
          EXPORT_OPTS='{{EXPORT_OPTS}}'
          CLIENTS=({% for _client in CLIENTS %} {{ _client|quote }}{% endfor %} )
          NFS_SERVICE='{{NFS_SERVICE}}'
          EXPORT_OWNER_DEFAULT={{ export_owner|default(ansible_user_uid)|string|quote }}
          EXPORT_GROUP_DEFAULT={{ export_group|default(ansible_user_gid)|string|quote }}
          EXPORT_MODE_DEFAULT={{ export_mode|default('0770')|string|quote }}
          EXPORT_OWNER="${NFS_EXPORT_OWNER:-$EXPORT_OWNER_DEFAULT}"
          EXPORT_GROUP="${NFS_EXPORT_GROUP:-$EXPORT_GROUP_DEFAULT}"
          EXPORT_MODE="${NFS_EXPORT_MODE:-$EXPORT_MODE_DEFAULT}"
          SUDO_CMD="sudo"
          if [ ! -f "${DIR}/etc/{{NAME}}.exports" ]; then
              echo "nfs-export: missing staged fragment ${DIR}/etc/{{NAME}}.exports" >&2
              exit 1
          fi
          # Publication rides the LINKS subsystem (record in DIR/links.json;
          # --id matches it). No unmanaged symlink fallback: a render with
          # LINKS_BYPASS ships no plan and no runtime, and inventing one here
          # would put the fragment outside LINKS audit/remove reach.
          if [ -x "${DIR}/bin/links.mjs" ]; then
              case "${1:-}" in
                  --copy) "${DIR}/bin/links.mjs" apply --id "$NFS_EXPORT_LINK_ID" --strategy copy ;;
                  *) "${DIR}/bin/links.mjs" apply --id "$NFS_EXPORT_LINK_ID" ;;
              esac
          else
              echo "nfs-export: no links runtime (LINKS_BYPASS render?); /etc/exports.d/{{NAME}}.exports not published" >&2
              exit 1
          fi
          # The export root is ours to create, never to restomp: mkdir only
          # when missing, and chown/chmod only the directory we created.
          if [ ! -d "$EXPORT_PATH" ]; then
              $SUDO_CMD mkdir -p "$EXPORT_PATH"
              $SUDO_CMD chown "$EXPORT_OWNER:$EXPORT_GROUP" "$EXPORT_PATH"
              $SUDO_CMD chmod "$EXPORT_MODE" "$EXPORT_PATH"
          fi
          # Distro service owns the nfsd lifecycle (no replacement unit):
          # starting with the fragment already published lets its own export
          # pass see this deployment on first boot.
          $SUDO_CMD systemctl enable --now "$NFS_SERVICE"
          # Scoped convergence: exportfs -i replaces only these
          # (client, path) table entries; every other host declaration is
          # left untouched. Removing or re-exporting anything else remains
          # a deliberate manual operation.
          for _client in "${CLIENTS[@]}"; do
              $SUDO_CMD exportfs -i -o "$EXPORT_OPTS" "${_client}:${EXPORT_PATH}"
              echo "nfs-export: exported ${_client}:${EXPORT_PATH} (${EXPORT_OPTS})"
          done
  pre_tasks:
    - name: "Compfuzor: kernel NFS requires the system scope"
      ansible.builtin.fail:
        msg: >-
          nfs-export: USERMODE is unsupported; kernel nfsd exports need the
          system scope. Re-run without USERMODE.
      when: USERMODE is deftruthy
    - name: "Compfuzor: validate the export declaration"
      ansible.builtin.assert:
        that:
          - NAME | default(TYPE ~ '-' ~ INSTANCE) is match('^[A-Za-z0-9_-][A-Za-z0-9_.-]*\Z')
          - EXPORT_PATH is match('^/[A-Za-z0-9_./+-]+\Z')
          - EXPORT_PATH is not search('(^|/)\.{1,2}(/|$)|//|/$')
          - CLIENTS | length > 0
          - EXPORT_OPTS is match('^[A-Za-z0-9_]+(=[A-Za-z0-9_./@+-]*)?(,[A-Za-z0-9_]+(=[A-Za-z0-9_./@+-]*)?)*\Z')
          - NFS_SERVICE is match('^[A-Za-z0-9_.@-]+[.]service\Z')
        fail_msg: >-
          nfs-export: invalid declaration (export_path={{ EXPORT_PATH }}
          export_opts={{ EXPORT_OPTS }} nfs_service={{ NFS_SERVICE }}):
          the path must be absolute and not /, and paths/opts/service must
          be free of whitespace and control characters
        success_msg: "nfs-export: export declaration validated"
    - name: "Compfuzor: validate export clients"
      ansible.builtin.assert:
        that:
          - item is match('^[A-Za-z0-9@*?_][A-Za-z0-9.@*?_/-]*\Z')
          - item != '*'
        fail_msg: >-
          nfs-export: unsafe client spec "{{ item }}": use IPv4
          addresses/CIDRs, hostnames, wildcards or @netgroups only.
          Bare '*' (world export) is refused, and IPv6 literals (which
          contain ':') are out of scope for now because exports(5) files
          and the exportfs CLI bracket them differently.
      loop: "{{ CLIENTS }}"
      loop_control:
        label: "{{ item }}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
