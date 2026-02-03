---
- hosts: all
  vars:
    PASSWORDS:
      - clickhouse
    APT_DISTRIBUTION: stable
    APT_REPO: https://packages.clickhouse.com/deb
    APT_KEYRING_URL: https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key
    APT_DEARMOR: True
    PKGS:
      - clickhouse-server
      - clickhouse-client
      - apt-transport-https
      - ca-certificates
      - gnupg
      - curl
    CLICKHOUSE_DB: click_db
    CLICKHOUSE_PASSWORD: "{{PASSWORD.clickhouse}}"
    CLICKHOUSE_USER: click_user
    ENV:
      - clickhouse_db
      - clickhouse_user
    BINS:
      - name: init-db.sh
        content: |
          clickhouse-client --password "{{CLICKHOUSE_PASSWORD}}" \
            "CREATE DATABASE IF NOT EXISTS {{CLICKHOUSE_DB}};"
          clickhouse-client --password "{{CLICKHOUSE_PASSWORD}}" \
            "CREATE USER IF NOT EXISTS {{CLICKHOUSE_USER}} IDENTIFIED BY '{{CLICKHOUSE_PASSWORD}}';"
          clickhouse-client --password "{{CLICKHOUSE_PASSWORD}}" \
            "GRANT ALL PRIVILEGES ON {{CLICKHOUSE_DB}}.* TO {{CLICKHOUSE_USER}};"
    ETC_FILES:
      - name: users.xml
        content: |
          <yandex>
            <users>
              <default_password>{{PASSWORD.clickhouse}}</default_password>
              <profiles>
                <default>
                  <default_database>{{CLICKHOUSE_DB}}</default_database>
                </default>
              </profiles>
            </users>
          </yandex>
      - name: config.xml
        content: |
          <yandex>
            <listen_host>0.0.0.0</listen_host>
            <http_port>8123</http_port>
            <tcp_port>9000</tcp_port>
            <mysql_port>9004</mysql_port>
            <max_server_memory_usage_percentage>90</max_server_memory_usage_percentage>
          </yandex>
  tasks:
    - import_tasks: tasks/compfuzor.includes
