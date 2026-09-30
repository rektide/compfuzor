---
- hosts: all
  vars:
    TYPE: debian
    INSTANCE: stable
    # The stable archive as a LOW-PINNED BACKSTOP on sid hosts.
    # Third-party debs are routinely built against stable (jellyfin-ffmpeg8
    # -> libbluray2/libvpx9/libx264-164; anything older-built hits the same
    # wall): those sonames vanish from sid but live on in stable. With the
    # stable suite present at Pin-Priority 100, dependency resolution can
    # pull them, while apt never PREFERS stable over unstable for packages
    # sid still carries and never downgrades an installed package to it.
    # Suite central var: APT_STABLE_DISTRIBUTION (vars/common.yaml).
    APT:
      URIs: "{{APT_DEFAULT_MIRROR}}"
      Suites: "{{APT_STABLE_DISTRIBUTION}}"
      Components: [main, contrib, non-free, non-free-firmware]
      # the Debian archive publishes all arches; hosts run i386 multiarch
      Architectures: [amd64, i386]
    APT_PREFS:
      Pin: "release n={{APT_STABLE_DISTRIBUTION}}"
      Pin-Priority: 100
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: etc
