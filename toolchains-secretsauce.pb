---
- hosts: all
  gather_facts: False
  vars:
    NAME: toolchains-secretsauce
    APT_REPO: http://toolchains.secretsauce.net
    APT_DISTRIBUTION: unstable
    APT_TRUST: False
  tasks:
  - include: tasks/compfuzor/apt.tasks
  - shell: dpkg --add-architecture armel
