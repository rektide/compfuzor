---
# systemd-iface-static-only: configure an interface STATIC-ONLY with
# Address/Gateway/DNS and deliberately NO DHCP. This REPLACES the
# interface's effective networkd config: networkd applies only the first
# matching .network (directory precedence /etc > /run > /usr/lib, lexical
# order within a dir), and this file lands at
# /etc/systemd/network/10-<INSTANCE>-static-only.network to win that race
# on purpose. Any DHCP config for the interface stops applying.
#
# Audience: VPS/colo boxes with provider-assigned static addressing.
#
# To KEEP DHCP and add a static secondary address beside it, use
# systemd-iface-extra-addr.etc.pb -- different tool, opposite contract.
# The guard below enforces that choice: a live DHCPv4 client on the target
# interface aborts the run unless -e FORCE=True (deliberate cutover).
#
# INSTANCE-driven: INSTANCE names the target interface (deployment dir,
# generated .network filename, and apply.sh all key off it):
#   ansible-playbook -i <inv> -c local systemd-iface-static-only.etc.pb \
#     -e INSTANCE=ens3 -e ADDRESS_CIDR=203.0.113.10/24 \
#     -e GATEWAY=203.0.113.1 -e DNS=193.110.81.0
#
# VERIFYING -- prefer `ip`/`networkctl` over ifconfig: net-tools ifconfig
# reads SIOCGIFADDR and can only show the kernel-primary address; it
# happens to be right for a single static, but lies on any multi-address
# interface (it is exactly how a live DHCP lease gets "lost" on
# extra-addr hosts):
#   ip -4 -brief addr show <iface>
#   networkctl status <iface>
#   ip route show default
- hosts: all
  vars:
    TYPE: systemd-iface-static-only
    # INSTANCE is the target interface; IFACE is kept as an in-template alias.
    INSTANCE: eth0
    IFACE: "{{INSTANCE}}"

    # Provider-assigned addressing. The defaults are the legacy example
    # host; pass real values per-VPS via inventory or -e.
    ADDRESS_CIDR: 216.144.229.17/24
    GATEWAY: 216.144.229.1
    DNS:
      - 8.8.8.8
      - 8.8.4.4
    # Deliberately empty NETWORK file prefix: 10- sorts early so the
    # static-only config wins first-match against vendor/DHCP files.
    NETWORKD_CONFIG_DIR: /etc/systemd/network
    # Allow cutting over an interface that currently has a DHCPv4 client.
    FORCE: false

    _addr: "{{ADDRESS_CIDR.split('/')[0]}}"

    ETC_FILES:
      - name: iface-static-only.network
        content: |
          # static-only config ({{NAME}}): REPLACES this interface's
          # effective networkd config; no DHCP runs here by design.
          [Match]
          Name={{IFACE}}

          [Network]
          Address={{ADDRESS_CIDR}}
          {% if GATEWAY %}
          Gateway={{GATEWAY}}
          {% endif %}
          {% for dns in DNS|default([]) %}
          DNS={{dns}}
          {% endfor %}

    LINKS:
      - src: "{{ETC}}/iface-static-only.network"
        dest: "{{NETWORKD_CONFIG_DIR}}/10-{{IFACE}}-static-only.network"
        policy: replace
        strategies:
          available: [copy]
          default: copy

    README: |
      # systemd-iface-static-only ({{INSTANCE}}): static-only interface config

      `{{NETWORKD_CONFIG_DIR}}/10-{{INSTANCE}}-static-only.network` configures
      {{INSTANCE}} with `{{ADDRESS_CIDR}}` (gateway `{{GATEWAY|default('none')}}`)
      and **no DHCP**. networkd applies only the FIRST matching .network
      (/etc > /run > /usr/lib, lexical within a dir); the `10-` prefix makes
      this file win deliberately, which means any DHCP config for the
      interface stops applying. That is the contract.

      To keep DHCP and ADD a static secondary beside it, that is the
      opposite tool: `systemd-iface-extra-addr.etc.pb` (drop-in merge, DHCP
      stays authoritative). The play refuses to run against an interface
      with a live DHCPv4 client unless `-e FORCE=True`.

      ## Verify with `ip`/`networkctl`, not ifconfig

      net-tools `ifconfig` can only ever show the kernel-primary address
      (`SIOCGIFADDR`, one address per interface). With a single static it
      happens to be right -- but on any multi-address interface it silently
      hides addresses, which is exactly how a live DHCP lease "disappears"
      on extra-addr hosts:

          ip -4 -brief addr show {{INSTANCE}}
          networkctl status {{INSTANCE}}
          ip route show default

      `bin/apply.sh` re-verifies address + gateway route after every run.

      ## Files

      - `etc/iface-static-only.network` -- the .network (delivered as a
        readable copy; networkd cannot traverse this private deployment dir)
      - `bin/apply.sh` -- idempotent: enable networkd/resolved, install,
        `networkctl reload` && `reconfigure`, then wait for the address and
        gateway route

    BINS:
      - name: apply.sh
        content: |
          #!/bin/sh
          # Apply static-only config for {{IFACE}}:
          #   enable networkd+resolved -> reload -> reconfigure -> verify.
          # This REPLACES the effective config for the interface; no DHCP
          # client runs on it afterward (see playbook header for the
          # first-match-wins story).
          #
          # Idempotent: exits early when the config file, the static
          # address, and the gateway route are all already in place.
          #
          # VERIFY WITH `ip`, NOT ifconfig: net-tools ifconfig reads
          # SIOCGIFADDR and shows only the kernel-primary address -- right
          # for a single static, silently wrong on multi-address interfaces:
          #   ip -4 -brief addr show {{IFACE}}
          #   ip route show default
          #   networkctl status {{IFACE}}
          set -e
          CONF={{NETWORKD_CONFIG_DIR}}/10-{{IFACE}}-static-only.network

          check_ready() {
            ip -4 addr show {{IFACE}} | grep -q "{{_addr}}" || return 1
            {% if GATEWAY %}
            ip route show default | grep -q "via {{GATEWAY}} " || return 1
            {% endif %}
            return 0
          }

          if [ -f "$CONF" ] && check_ready; then
            echo "OK (already applied): {{_addr}}{% if GATEWAY %} via {{GATEWAY}}{% endif %} present, config in place"
            ip -4 -brief addr show {{IFACE}}
            exit 0
          fi

          # networkd cannot traverse Compfuzor's private deployment dirs, so
          # LINKS delivers this as a regular copy. Ensure networkd can read
          # it before reload.
          sudo chmod 0644 "$CONF"
          sudo systemctl enable --now systemd-networkd.service
          sudo systemctl enable --now systemd-resolved.service
          sudo networkctl reload
          sudo networkctl reconfigure {{IFACE}}
          # Wait for the address (and gateway route) to land before
          # reporting success.
          ready=false
          for _ in $(seq 1 30); do
            if check_ready; then
              ready=true
              break
            fi
            sleep 1
          done
          if [ "$ready" != true ]; then
            echo "ERROR: {{IFACE}} did not gain {{_addr}}{% if GATEWAY %} via {{GATEWAY}}{% endif %}" >&2
            ip -4 -brief addr show {{IFACE}} >&2 || true
            ip route show default >&2 || true
            exit 1
          fi
          echo "OK: {{IFACE}} static-only {{ADDRESS_CIDR}}{% if GATEWAY %} gateway {{GATEWAY}}{% endif %}"
          echo
          ip -4 -brief addr show {{IFACE}}
          ip route show default

  tasks:
    - name: read networkctl state for {{INSTANCE}} (guard input)
      command: networkctl status {{INSTANCE}} --no-pager
      changed_when: false
      failed_when: false
      register: _netctl

    - name: refuse live DHCP interfaces unless FORCE (want extra-addr instead)
      assert:
        that:
          - (FORCE | bool) or not ((_netctl.stdout | default('')) is search('DHCPv4 Client'))
        success_msg: "no DHCPv4 client on {{INSTANCE}} (or FORCE); proceeding static-only"
        fail_msg: >-
          {{INSTANCE}} has a live DHCPv4 client. static-only REPLACES the
          interface config and drops DHCP; to keep DHCP and add a static
          secondary use systemd-iface-extra-addr.etc.pb. Use -e FORCE=True
          only for a deliberate static cutover.

    - import_tasks: tasks/compfuzor.includes
