---
# Zabbly -- Stéphane Graber's (Incus lead developer) package host.
#
# Two repositories live at pkgs.zabbly.com:
#   incus:  /incus/{lts-6.0,lts-7.0,stable,daily} -- Incus container+VM manager
#   kernel: /kernel/stable                       -- supported Linux kernel builds
# (plus commercial Incus support at zabbly.com)
#
# This playbook registers the incus *stable* repo; INSTANCE selects which
# (e.g. -e INSTANCE=incus-daily would need its matching URIs -- the URIs here
# are stable-specific, so a different repo means a new INSTANCE + URIs edit).
#
# Suites are per-distro-codename (bookworm/trixie/jammy/noble/resolute) --
# there is NO forky/sid suite. Pinned to trixie, the newest Debian suite
# Zabbly builds; same cross-suite pattern as jellyfin.repo.pb. Incus deps
# are stable core libs, but if apt ever fails to resolve, check trixie
# soname drift first.
#
# Key is ASCII-armored and used as-is (apt accepts .asc keyrings in
# Signed-By). Fingerprint, per upstream README:
#   4EFC 5906 96CB 15B8 7C73  A3AD 82CC 8797 C838 DCFD
#
# Render + install before incus.opt.pb (its PKGS resolve against this repo):
#   ansible-playbook -i 'localhost,' -c local zabbly.repo.pb
#   sudo bash /etc/opt/zabbly-incus-stable/bin/install.sh
- hosts: all
  vars:
    TYPE: zabbly
    INSTANCE: incus-stable
    APT:
      URIs: https://pkgs.zabbly.com/incus/stable
      Suites: trixie
      Components: [main]
    APT_KEYRING_URL: https://pkgs.zabbly.com/key.asc
    APT_GPG_EXT: asc   # armored key, no dearmor; signed-by -> zabbly.asc
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: etc
