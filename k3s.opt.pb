---
- hosts: all
  vars:
    TYPE: k3s
    INSTANCE: v1.17.3+k3s1
    GET_URLS: https://github.com/rancher/k3s/releases/download/{{INSTANCE|urlencode}}/k3s
    BINS:
    - global: k3s
      baseidr: src
  tasks:
  - include: tasks/compfuzor.includes type=opt
  - file:
      path: "{{SRC}}/k3s"
      mode: a+x
