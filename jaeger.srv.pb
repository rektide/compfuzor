---
- hosts: all
  vars:
    SYSTEMS_SERVICES:
      ExecStart: jaeger query
    ENV:
      SPAN_STORAGE_TYPE: grpc-plugin
      GRPC_STORAGE_SERVER: 127.0.0.1:7281
  tasks:
    - import_tasks: tasks/compfuzor.includes
