---
- hosts: all
  gather_facts: False
  vars:
    NAME: steam
    DEBCONFS:
    - name: steam
      question: "steam/question"
      vtype: select
      value: "I AGREE"
    - name: steam
      question: "steam/license"
      vtype: note
    - name: steam
      question: "steam/purge"
      vtype: note
    #PKGS:
    #- steam:i386
  tasks:
  - shell: dpkg --add-architecture i386
  - shell: apt-get update
  - include: tasks/compfuzor.includes
