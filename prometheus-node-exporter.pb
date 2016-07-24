---
- hosts: all
  vars:
    TYPE: prometheus-node-exporter
    INSTANCE: main
    SYSTEMD_EXEC: "{{node_exporter_dir}}/node_exporter -collectors.enabled={{collectors|join(',')}}"
    node_exporter_dir: "{{SRCS_DIR}}/prometheus-git/node_exporter"
    collectors:
    - power_supply
    # default collectors:
    - netstat
    - stat
    - filesystem
    - mdadm
    - meminfo
    - sockstat
    - uname
    - diskstats
    - entropy
    - filefd
    - loadavg
    - conntrack
    - netdev
    - textfile
    - time
    - vmstat
  tasks:
  - include: tasks/compfuzor.includes type=srv
