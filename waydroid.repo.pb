---
- hosts: all
  vars:
    TYPE: waydroid
    INSTANCE: main
    # deb822 lane: renders waydroid-main.sources + vendored keyring +
    # install-apt-sources.sh (packages lane). Suite forky is explicit here
    # (the legacy lane got it from APT_DEFAULT_DISTRIBUTION); repo.waydro.id
    # publishes forky alongside older suites.
    APT:
      URIs: https://repo.waydro.id
      Suites: forky
      Components: [main]
    # keyring: vendored files/apt-repos/waydroid.gpg
    # (7CE0331F71E0A238BB1002D70E406D181DCEE19C, matches repo.waydro.id/waydroid.gpg)
    APT_TRUSTED: waydroid
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: etc
