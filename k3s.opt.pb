---
- hosts: all
  vars:
    TYPE: k3s
    release: v1.34.1+k3s1
    #INSTANCE: "{{ release }}"
    INSTANCE: main
    GET_URLS: https://github.com/k3s-io/k3s/releases/download/{{release|urlencode}}/k3s
    PKGS:
      - criu
    BINS:
    - link: "{{SRC}}/k3s"
      global: True
    - dest: kubectl
      link: k3s
      global: True
    - dest: crictl
      link: k3s
      global: True
    - dest: ctr
      link: k3s
      global: True
  tasks:
  - import_tasks: tasks/compfuzor.includes
  - file:
      path: "{{SRC}}/k3s"
      mode: a+x
