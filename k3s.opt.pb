---
- hosts: all
  vars:
    TYPE: k3s
    release: v1.18.3+k3s1
    #INSTANCE: "{{ release }}"
    INSTANCE: main
    GET_URLS: https://github.com/rancher/k3s/releases/download/{{release|urlencode}}/k3s
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
  - include: tasks/compfuzor.includes type=opt
  - file:
      path: "{{SRC}}/k3s"
      mode: a+x
