---
- hosts: all
  vars:
    NAME: steam
    DEBCONF:
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
    PKGS:
    - steam:i386
    - libglx-mesa0:i386
    - mesa-vulkan-drivers:i386
    - libgl1-mesa-dri:i386
    - fonts-liberation
  tasks:
  - shell: dpkg --add-architecture i386
    become: True
  - shell: apt-get update
    become: True
  - include: tasks/compfuzor.includes type=opt
