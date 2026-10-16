---
# systemd-iface-extra-addr: add a STATIC secondary IPv4 address to a
# networkd-managed interface whose DHCP lease stays authoritative (default
# route, DNS, etc. all keep coming from DHCP). This is the stable anchor a
# kube node-IP pin points at (k3s.srv.pb NODE_IP): embedded-etcd member
# peer URLs stop drifting with DHCP leases while the host remains fully
# DHCP-mobile. For the opposite tool -- replacing an interface with
# static-only config, DHCP dropped -- see systemd-iface-static.etc.pb.
#
# The address lands as a networkd drop-in
# (/etc/systemd/network/<NETWORK_FILE>.network.d/<NAME>.conf) merged into the
# existing config -- no .network replacement,
# no DHCP disruption -- applied live via `networkctl reload && reconfigure`
# (briefest of address blips; no reboot).
#
# INSTANCE-driven: INSTANCE names the target interface; the deployment dir,
# the drop-in, and apply.sh all key off it (`-e INSTANCE=enp3s0`). The
# governing networkd config basename (NETWORK_FILE) is DISCOVERED at runtime
# from `networkctl status` ("Network File:" line), so the drop-in lands
# beside whatever file actually owns the interface -- an /etc admin file, a
# netplan /run render, or a vendor /usr/lib main; drop-ins delivered via
# /etc merge into any of those. Force a basename with -e NETWORK_FILE=<base>
# when discovery must not win.
#
# Guards: the play refuses to run when the interface is not networkd-managed
# (no discoverable Network File) or has no DHCPv4 client attached --
# "secondary to DHCP" is meaningless without DHCP. Both are override-able
# (-e NETWORK_FILE=..., -e DHCP_REQUIRED=False) for repair scenarios.
#
# VERIFYING -- do NOT use ifconfig. net-tools ifconfig reads SIOCGIFADDR,
# which can only ever report the kernel-PRIMARY address of an interface;
# once the static lands it usually becomes primary, so ifconfig shows ONLY
# the static and silently hides the DHCP lease. The lease is fine. Check:
#   ip -4 -brief addr show <iface>    # both addresses, always
#   networkctl status <iface>         # which is (DHCPv4 via ...), Network File + drop-in
#   ip route show default             # proto dhcp proves DHCP authority
#
# !!! Pick an address OUTSIDE the DHCP pool (or reserve it router-side) !!!
# Two owners of one address is a silent, nasty failure mode.
#
# Inventory-driven deploy example (`NODE_IP_CIDR` lives with k3s_node_ip):
#   ansible-playbook -i ~/.ansible/k3s -c local \
#     systemd-iface-extra-addr.etc.pb --limit workhorse
- hosts: all
  vars:
    TYPE: systemd-iface-extra-addr
    # INSTANCE is the target interface. Deployment dir, drop-in name, and
    # apply.sh all derive from it; IFACE is kept as an in-template alias.
    INSTANCE: eno1
    IFACE: "{{INSTANCE}}"

    # basename (sans .network) of the networkd config to extend. Empty (the
    # default) means "discover from networkctl at runtime"; an explicit
    # -e NETWORK_FILE=<base> bypasses discovery (extra vars outrank facts).
    NETWORK_FILE: ""
    # Drop-ins always land in the admin dir: an /etc drop-in merges into
    # mains living in /run (netplan renders) or /usr/lib (vendor) too.
    NETWORKD_CONFIG_DIR: /etc/systemd/network
    # Refuse to proceed when no DHCPv4 client is attached to IFACE.
    DHCP_REQUIRED: true
    # NODE_IP_CIDR belongs in host inventory beside k3s's NODE_IP so this
    # playbook and k3s.srv.pb cannot drift apart.
    ADDRESS_CIDR: "{{NODE_IP_CIDR|default('192.168.1.8/22')}}"

    _addr: "{{ADDRESS_CIDR.split('/')[0]}}"

    ETC_FILES:
      - name: extra-addr.conf
        content: |
          # static secondary address ({{NAME}}); DHCP stays authoritative
          [Network]
          Address={{ADDRESS_CIDR}}

    LINKS:
      - src: "{{ETC}}/extra-addr.conf"
        dest: "{{NETWORKD_CONFIG_DIR}}/{{NETWORK_FILE}}.network.d/{{NAME}}.conf"
        policy: replace
        strategies:
          available: [copy]
          default: copy

    README: |
      # systemd-iface-extra-addr ({{INSTANCE}}): static secondary IPv4 beside DHCP

      A networkd drop-in merges `Address={{ADDRESS_CIDR}}` into the interface's
      governing config (discovered: `{{NETWORK_FILE}}.network`, extended via
      `{{NETWORKD_CONFIG_DIR}}/{{NETWORK_FILE}}.network.d/{{NAME}}.conf`).
      Nothing about the interface is replaced: DHCP keeps the default route,
      DNS, and lease renewals. The static address is the stable anchor other
      systems pin to -- notably the k3s `--node-ip` (see the repo's
      doc/k3s-drift-recovery.md "static secondary IP + NODE_IP pin").
      `k3s.srv.pb` installs `drift-guard.sh` as `ExecStartPre`, re-verifying
      the pin is assigned before every k3s start: if this drop-in ever
      vanishes, starts fail loudly instead of silently re-registering under
      the DHCP address.

      ## Verify with `ip` -- NEVER ifconfig

      net-tools `ifconfig` can only show the kernel-PRIMARY address
      (`SIOCGIFADDR`, one address per interface). After this deployment the
      static address usually becomes primary, so `ifconfig` shows ONLY the
      static and hides the live DHCP lease. That is an observation artifact,
      not a network problem:

          ip -4 -brief addr show {{INSTANCE}}
          networkctl status {{INSTANCE}}
          ip route show default        # want: proto dhcp, src <dhcp-addr>

      `bin/apply.sh` re-verifies all of this after every run.

      ## Address choice

      Pick an address OUTSIDE the DHCP pool, or reserve it router-side.
      Two owners of one address is a silent, nasty failure mode.

      ## Files

      - `etc/extra-addr.conf` -- drop-in source (delivered as a readable
        copy; networkd cannot traverse this private deployment dir)
      - `bin/apply.sh` -- idempotent: install drop-in, `networkctl reload`
        && `reconfigure`, then wait for BOTH the static address and the
        DHCP-owned default route to return

    BINS:
      - name: apply.sh
        content: |
          #!/bin/sh
          # Apply the secondary static address drop-in for {{IFACE}}:
          #   deliver drop-in (LINKS copy) -> reload networkd -> reconfigure -> verify.
          #
          # Idempotent: when the drop-in file, the static address, and the
          # DHCP default route are all already in place, exits without
          # touching the lease (no reconfigure churn on re-runs).
          #
          # VERIFY WITH `ip`, NOT ifconfig: net-tools ifconfig reads
          # SIOCGIFADDR, which reports only the kernel-primary address --
          # after this deployment that is usually the STATIC address, so
          # ifconfig will hide the DHCP lease entirely. The lease is fine:
          #   ip -4 -brief addr show {{IFACE}}
          #   ip route show default
          #   networkctl status {{IFACE}}
          set -e
          DROPIN={{NETWORKD_CONFIG_DIR}}/{{NETWORK_FILE}}.network.d/{{NAME}}.conf

          if [ -f "$DROPIN" ] \
            && ip -4 addr show {{IFACE}} | grep -q "{{_addr}}" \
            && ip -4 route show default dev {{IFACE}} | grep -q '^default '; then
            echo "OK (already applied): drop-in present, {{_addr}} + DHCP default route live"
            ip -4 -brief addr show {{IFACE}}
            exit 0
          fi

          # networkd cannot traverse Compfuzor's private deployment dirs, so
          # LINKS delivers this as a regular copy. Ensure networkd can
          # traverse the drop-in dir, then apply this deployment's own link
          # record (record id matches the LINKS entry in DIR/links.json).
          # No unmanaged-copy fallback: a render with LINKS_BYPASS ships no
          # runtime, and delivering outside LINKS audit/remove reach would
          # leave a drop-in nothing tracks.
          sudo install -d -m 0755 {{NETWORKD_CONFIG_DIR}}/{{NETWORK_FILE}}.network.d
          if [ -x "${DIR}/bin/links.mjs" ]; then
              "${DIR}/bin/links.mjs" apply --id "system:${DROPIN}"
          else
              echo "extra-addr: no links runtime (LINKS_BYPASS render?); ${DROPIN} not delivered" >&2
              exit 1
          fi
          sudo chmod 0644 "$DROPIN"
          sudo networkctl reload
          sudo networkctl reconfigure {{IFACE}}
          # Reconfigure briefly drops the DHCP lease. Do not report success
          # until both the static address and DHCP-owned default route return.
          ready=false
          for _ in $(seq 1 30); do
            if ip -4 addr show {{IFACE}} | grep -q "{{_addr}}" \
              && ip -4 route show default dev {{IFACE}} | grep -q '^default '; then
              ready=true
              break
            fi
            sleep 1
          done
          if [ "$ready" != true ]; then
            echo "ERROR: {{IFACE}} did not regain both {{_addr}} and its DHCP default route" >&2
            ip -4 -brief addr show {{IFACE}} >&2 || true
            ip -4 route show default dev {{IFACE}} >&2 || true
            exit 1
          fi
          echo "OK: {{_addr}} assigned on {{IFACE}}; DHCP default route restored"
          echo
          ip -4 -brief addr show {{IFACE}}
          ip route show default

  tasks:
    - name: read networkctl state for {{INSTANCE}} (discovery input)
      command: networkctl status {{INSTANCE}} --no-pager
      changed_when: false
      failed_when: false
      register: _netctl

    - name: capture Network File path from networkctl output
      set_fact:
        _nf_path: "{{ ((_netctl.stdout | default('')).split('Network File:'))[1] | default('') }}"
      when: "'Network File:' in (_netctl.stdout | default(''))"
    - name: no Network File line (unmanaged or non-networkd host)
      set_fact:
        _nf_path: ""
      when: "'Network File:' not in (_netctl.stdout | default(''))"
    - name: interface must be networkd-managed (or NETWORK_FILE forced)
      assert:
        that:
          - NETWORK_FILE | length > 0 or (((_nf_path).splitlines() | first | default('')) | trim) not in ('', 'n/a')
        success_msg: >-
          governing config:
          {{ (NETWORK_FILE | length > 0) | ternary(NETWORK_FILE ~ ' (forced)',
             (((_nf_path).splitlines() | first | default('')) | trim) ~ ' (discovered)') }}
        fail_msg: >-
          networkctl reports no Network File for {{INSTANCE}} (unmanaged or
          not a networkd host). This playbook extends an existing networkd
          config; pass -e NETWORK_FILE=<basename> only if you really mean it.

    - name: derive governing network-file basename
      set_fact:
        _network_file: "{{ (((_nf_path).splitlines() | first | default('')) | trim) | basename | regex_replace('[.]network$', '') }}"

    - name: adopt discovered network file when none was forced
      set_fact:
        NETWORK_FILE: "{{_network_file}}"
      when: NETWORK_FILE | length == 0

    - name: DHCPv4 client must be attached (secondary-to-DHCP contract)
      assert:
        that:
          - (not (DHCP_REQUIRED | bool)) or (_netctl.stdout | default('')) is search('DHCPv4 Client')
        success_msg: "DHCPv4 client present on {{INSTANCE}}; DHCP stays authoritative"
        fail_msg: >-
          No DHCPv4 client on {{INSTANCE}} per networkctl. This playbook adds
          a static secondary to DHCP, it does not create DHCP. Fix the
          interface's DHCP= setting, or -e DHCP_REQUIRED=False to override.

    - import_tasks: tasks/compfuzor.includes
