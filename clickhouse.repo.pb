---
- hosts: all
  vars:
    TYPE: clickhouse
    INSTANCE: main
    # apt repository ONLY: deb822 source stanza + keyring
    # (install-apt-sources.sh links both into place). The server
    # deployment -- packages, config, db init, passwords -- lives in
    # clickhouse.srv.pb (/srv/clickhouse-main).
    APT:
      URIs: https://packages.clickhouse.com/deb
      Suites: stable
      Components: [main]
    APT_KEYRING_URL: https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key
    APT_DEARMOR: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: etc
