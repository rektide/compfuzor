---
- hosts: all
  gather_facts: False
  vars:
    TYPE: iceweasel
    INSTANCE: beta
    APT_REPO: http://mozilla.debian.net/
    APT_DISTRIBUTION: experimental
    APT_COMPONENT: iceweasel-beta
    APT_ARCH: True
    APT_PIN: 'release o=Debian Mozilla Team'
    APT_PIN_PRIORITY: 600
  tasks:
  - include: tasks/compfuzor.includes type=opt
