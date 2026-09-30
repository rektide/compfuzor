---
- hosts: all
  vars:
    TYPE: upplay
    INSTANCE: unstable
    # deb822 lane. Upstream's per-release download dirs (last known good:
    # debian-bookworm; the old playbook said debian-jessie); the repo was
    # disabled on workhorse (commented .list) so the stanza declares
    # Enabled: no -- drop that line when re-enabling.
    APT:
      URIs: http://www.lesbonscomptes.com/upmpdcli/downloads/debian-bookworm/
      Suites: unstable
      Components: [main]
      Enabled: no
    PKGS:
    - upplay
  tasks:
  - import_tasks: tasks/compfuzor.includes
    vars:
      type: pkg
