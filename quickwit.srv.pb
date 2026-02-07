---
- hosts: all
  vars:
    SYSTEMD_SERVICES:
      ExecStart: quickwit run
    ENV:
      QW_ENABLE_OPENTELEMETRY_OTLP_EXPORTER: true
      OTEL_EXPORTER_OTLP_ENDPOINT: http://127.0.0.1:7281
  tasks:
    - import_tasks: tasks/compfuzor.includes
