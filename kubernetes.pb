---
- hosts: all
  vars:
    TYPE: kubernetes
    INSTANCE: main
    podip: "{{service_cluster_ip_range|ipsubnet(service_cluster_podcidr, item)}}"
    VARS_DIR: True
    ETC_DIRS:
    - manifests
    ETC_FILES: 
    - config
    SYSCTL:
      "net.ipv4.ip_forward": 1
    HOST_TOKENS:
    - kubelet_token
  tasks:
  - include: tasks/compfuzor/vars_base.tasks 
