---
- hosts: all
  vars:
    TYPE: lutris
    INSTANCE: main
    # deb822 lane: renders lutris-main.sources + install-apt-sources.sh
    # (packages lane) which fetches the keyring from APT_KEYRING_URL (OBS
    # rotates it; install re-fetches so a rotation self-heals), dearmors
    # it, and links both into place. Flat-repo OBS style: Suites "./", no
    # components.
    # NB on forky/sid hosts Debian's own contrib lutris (0.5.22) is newer
    # than the OBS builds (0.5.20 across Debian_12/13/Unstable) -- this
    # repo was disabled on workhorse 2026-09-30 for that reason; deploy
    # where the OBS build is still wanted.
    APT:
      URIs: https://download.opensuse.org/repositories/home:/strycore/Debian_12/
      Suites: ["./"]
      # explicit empty: flat OBS repo takes no components -- without this
      # the APT_DEFAULTS layer injects the default component and apt
      # rejects the stanza ("absolute Suite Component")
      Components: []
    APT_KEYRING_URL: https://download.opensuse.org/repositories/home:/strycore/Debian_12/Release.key
    APT_DEARMOR: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: etc
