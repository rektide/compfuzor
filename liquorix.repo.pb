---
- hosts: all
  vars:
    INSTANCE: etc
    # deb822 lane: renders liquorix-etc.sources (INSTANCE etc keeps the
    # historical /etc/opt/liquorix-etc DIR). Suite pinned explicitly: the
    # legacy lane inherited forky from APT_DEFAULT_DISTRIBUTION at render
    # time; liquorix tracks sid/forky.
    APT:
      URIs: https://liquorix.net/debian
      Suites: forky
      Components: [main]
    # keyring: fetched binary .gpg (no dearmor needed)
    APT_KEYRING_URL: https://liquorix.net/liquorix-keyring.gpg
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: etc
