---
- hosts: all
  gather_facts: False
  tasks:
  - lineinfile: dest=/etc/systemd/logind.conf regexp='^HandleLidSwitch=' line='HandleLidSwitch=ignore'
  - lineinfile: dest=/etc/systemd/logind.conf regexp='^HandlePowerKey=' line='HandlePowerKey=suspend'
  - lineinfile: dest=/etc/systemd/logind.conf regexp='^PowerKeyIgnoreInhibited' line='PowerKeyIgnoreInhibited=on'
  - lineinfile: dest=/etc/systemd/logind.conf regexp='^SuspendKeyIgnoreInhibited' line='SuspendKeyIgnoreInhibited=on'
  - lineinfile: dest=/etc/systemd/logind.conf regexp='^RuntimeDirectorySize' line='RuntimeDirectorySize=25%'
