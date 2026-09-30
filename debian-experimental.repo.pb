---
- hosts: all
  vars:
    TYPE: debian-experimental
    INSTANCE: main
    # deb822 lane: renders debian-experimental-main.sources + pin .pref.
    # Archive keys already trusted system-wide (debian-archive-keyring) --
    # no keyring configured, so no Signed-By in the stanza.
    APT:
      URIs: "{{APT_DEFAULT_MIRROR}}"
      Suites: experimental
      Components: [main, contrib, non-free]
      # the Debian archive publishes all arches; host runs i386 multiarch
      Architectures: [amd64, i386]
    APT_PREFS:
      Pin: "release a=experimental"
      Pin-Priority: 200
  tasks:
  - import_tasks: tasks/compfuzor.includes
    vars:
      type: etc
