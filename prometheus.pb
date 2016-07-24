---
- hosts: all
  vars:
    TYPE: prometheus
    INSTANCE: main
    SYSTEMD_EXEC: "{{prometheus_dir}}/prometheus -config.file={{ETC}}/prometheus.yml $ARGS"
    ENV:
      ARGS: ""
    ETC_D:
    - prometheus.yml.d/rules
    - prometheus.yml.d/scrapes
    - prometheus.yml
    ETC_FILES:
    - prometheus.yml.d/00-global
    - prometheus.yml.d/rules.d/00-rules
    - prometheus.yml.d/scrapes.d/00-scrapes
    prometheus_dir: /opt/prometheus-git/prometheus
    scrape_configs:
    - job_name: prometheus
      scrape_interval: 5s
      static:
      - 'localhost:9090'
    ETC: /etc/opt/prometheus-main
 
  tasks:
  - include: tasks/compfuzor.includes type=srv
  - set_fact: yaml_indent=2 yaml_special=item
  - template: src="files/_yaml" dest="{{ETC}}/prometheus.yml.d/scrapes.d/50-{{item.job_name}}" yaml_special=item
    with_items: "{{scrape_configs}}"
  - include: tasks/compfuzor/fs_d.tasks include=etc
  - include: tasks/systemd.thunk service="{{SYSTEMD_SERVICE}}"
