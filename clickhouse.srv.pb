---
- hosts: all
  vars:
    TYPE: clickhouse
    INSTANCE: main
    # Server deployment: packages, staged config, db-init bin, passwords.
    # The apt repository itself is clickhouse.repo.pb (/etc/opt/
    # clickhouse-main) -- render that first on a fresh box, or the PKGS
    # lane below cannot resolve clickhouse-server/-client.
    PASSWORDS:
      - clickhouse
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
    ENV_LIST:
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
            "GRANT ALL ON {{CLICKHOUSE_DB}}.* TO {{CLICKHOUSE_USER}};"
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
      vars:
        type: srv
