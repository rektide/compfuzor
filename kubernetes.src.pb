---
- hosts: all
  vars:
    TYPE: kubernetes
    INSTANCE: git
    REPO: https://github.com/kubernetes/kubernetes
    BINS:
    - name: build.sh
      exec: bazel build . :kube-controller-manager :kube-proxy :kube-apiserver
      basedir: build/debs
  tasks:
  - include: tasks/compfuzor.includes type=src
