---
- hosts: all
  vars:
    TYPE: prometheus
    INSTANCE: git
    REPOS:
    - https://github.com/prometheus/prometheus
    - https://github.com/prometheus/node_exporter
    - https://github.com/prometheus/pushgateway
    - https://github.com/prometheus/alertmanager
    - https://github.com/prometheus/blackbox_exporter
    - https://github.com/prometheus/prometheus.github.io
    - https://github.com/prometheus/docs
    - https://github.com/prometheus/mysqld_exporter
    - https://github.com/prometheus/client_golang
    - https://github.com/prometheus/client_java
    - https://github.com/prometheus/snmp_exporter
    - https://github.com/prometheus/common
    - https://github.com/prometheus/promdash
    - https://github.com/prometheus/collectd_exporter
    - https://github.com/prometheus/promu
    - https://github.com/prometheus/memcached_exporter
    - https://github.com/prometheus/statsd_exporter
    - https://github.com/prometheus/influxdb_exporter
    - https://github.com/prometheus/graphite_exporter
    - https://github.com/prometheus/jmx_exporter
    - https://github.com/prometheus/golang-builder
    - https://github.com/prometheus/golang-builder
    - https://github.com/prometheus/procfs
    - https://github.com/prometheus/utils
    - https://github.com/prometheus/host_exporter
    - https://github.com/prometheus/prometheus_cli
    - https://github.com/prometheus/prom2json
    - https://github.com/prometheus/log
    - https://github.com/prometheus/client_model
    - https://github.com/prometheus/distro-pkgs
    - https://github.com/prometheus/migrate
  tasks:
  - include: tasks/compfuzor.includes type=src
