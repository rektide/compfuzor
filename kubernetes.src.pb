---
- hosts: all
  gather_facts: False
  vars:
    TYPE: kubernetes
    INSTANCE: git
    REPO: https://github.com/GoogleCloudPlatform/kubernetes
    BINS:
    - exec: make all
      pwd: repo
    ENV:
      gopath: "{{DIR}}:$GOPATH"
    PKGS:
    - rsync
    LINKS: 
      bin: "{{REPO}}/cmd"
  tasks:
  - include: tasks/compfuzor.includes
