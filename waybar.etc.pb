---
# waybar.etc.pb -- site policy: waybar default-OFF for all users, with a
# documented per-user opt-in. The session bar/tray on this fleet is the
# Noctalia shell (doc/noctalia/README.md); waybar stays installed for
# anyone who deliberately wants it back.
#
# Mechanism notes (verified 2026-10-13 on workhorse):
#   * waybar's real default-on vector was the GLOBAL enablement symlink
#     /etc/systemd/user/graphical-session.target.wants/waybar.service,
#     created by Debian packaging (deb-systemd-helper --user enable runs
#     from waybar's postinst and can recreate the symlink on package
#     upgrade when the shipped unit changes -- deleting it alone is not
#     durable).
#   * Earlier attempts to neutralize this with drop-ins setting an empty
#     "[Install] WantedBy=" (in /etc/systemd/user/waybar.service.d/ and
#     ~/.config/systemd/user/waybar.service.d/, both named not-wanted.conf)
#     were no-ops: drop-in [Install] lists only ADD to the vendor unit's
#     lists -- an empty list clears nothing -- and [Install] is not
#     consulted at runtime anyway. Both stale files were removed.
#   * The durable gate is a [Unit] Condition in an /etc drop-in: conditions
#     from all drop-in levels AND together and cannot be cancelled by a
#     user-level drop-in, so every start vector (global enablement,
#     per-user enable, manual start, package-upgrade re-enable) stays
#     inert until the user opts in.
#
# Per-user opt-in (no root needed):
#     mkdir -p ~/.config/waybar && touch ~/.config/waybar/enabled
#     systemctl --user enable --now waybar.service
#
# This playbook only manages /etc state. It does not stop already-running
# waybar instances and does not touch per-user enablement symlinks; those
# remain each user's own choice. Other logged-in users' user managers pick
# the drop-in up after their next daemon-reload/session start.
- hosts: all
  gather_facts: False
  vars:
    TYPE: waybar
    INSTANCE: site
  tasks:
  - file: path="/etc/systemd/user/waybar.service.d/" state=directory mode=755 owner=root group=root
  - copy:
      dest: /etc/systemd/user/waybar.service.d/50-site-default-off.conf
      mode: "0644"
      owner: root
      group: root
      content: |
        # Site policy (compfuzor waybar.etc.pb): waybar is installed but OFF
        # by default for every user; the session bar is the Noctalia shell.
        # Opt back in per user (no root needed):
        #   mkdir -p ~/.config/waybar && touch ~/.config/waybar/enabled
        #   systemctl --user enable --now waybar.service
        [Unit]
        ConditionPathExists=%h/.config/waybar/enabled
  - file: path="/etc/systemd/user/graphical-session.target.wants/waybar.service" state=absent
  - file: path="/etc/systemd/user/waybar.service.d/not-wanted.conf" state=absent
  # Flip deb-systemd-helper's statefile so waybar package upgrades do not
  # re-run global enablement (postinst checks was-enabled, which defaults
  # to true with no statefile). The helper refuses bare invocation -- it
  # only runs under dpkg -- so supply the owning package the same way
  # dpkg does. Harmless to repeat; the condition drop-in above is the
  # backstop either way.
  - command: deb-systemd-helper --user disable waybar.service
    environment:
      DPKG_MAINTSCRIPT_PACKAGE: waybar
    changed_when: False
