---
- hosts: all
  vars:
    TYPE: cfssl
    INSTANCE: git
    REPO_GOGET: github.com/cloudflare/cfssl/cmd/...
    BINS:
    - name: cfssl
      global: True
      src: False
    - name: cfssl-bundle
      global: True
      src: False
    - name: cfssl-certinfo
      global: True
      src: False
    - name: cfssljson
      global: True
      src: False
    - name: cfssl-newkey
      global: True
      src: False
    - name: cfssl-scan
      global: True
      src: False
    - name: mkbundle
      global: True
      src: False
    - name: multirootca
      global: True
      src: False
  tasks:
  - include: tasks/compfuzor.includes type=src
