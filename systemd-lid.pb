---
- hosts: all
  gather_facts: False
  vars:
    power: hibernate
  tasks:
  - lineinfile: dest=/etc/systemd/logind.conf regexp='^HandleLidSwitch=' line='HandleLidSwitch=ignore'
  - lineinfile: dest=/etc/systemd/logind.conf regexp='^HandlePowerKey=' line="HandlePowerKey={{power}}"
