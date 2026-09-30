---
- hosts: all
  vars:
    TYPE: chrome
    INSTANCE: stable
    # deb822 lane: renders chrome-apt.sources + vendored keyring +
    # install-apt-sources.sh. Not deployed on workhorse (google drops its
    # own google-chrome.sources); render elsewhere as needed.
    APT:
      URIs: http://dl.google.com/linux/chrome/deb
      Suites: stable
      Components: [main]
    # keyring: vendored files/apt-repos/chrome-apt.gpg
    APT_TRUSTED: chrome-apt
    APT_SOURCELIST: chrome-apt
    PKGS:
    - google-chrome-unstable
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: etc
