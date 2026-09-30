---
- hosts: all
  vars:
    TYPE: mise
    INSTANCE: main
    # deb822 lane: renders mise-main.sources; keyring via APT_KEYRING_URL
    # (armored pub, dearmored on install).
    APT:
      URIs: https://mise.jdx.dev/deb
      Suites: stable
      Components: [main]
    APT_KEYRING_URL: https://mise.jdx.dev/gpg-key.pub
    APT_DEARMOR: True
    PKGS:
      - mise
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: etc
