---
- hosts: all
  gather_facts: False
  vars:
    TYPE: hpn-ssh
    INSTANCE: "hpn-14-6.3p1"
    TGZ: http://openbsd.cs.toronto.edu/pub/OpenBSD/OpenSSH/portable/openssh-6.3p1.tar.gz
    hpnssh14v2_kitchen_sink_patch: http://www.psc.edu/index.php/hpn-ssh-patches/hpn-14-kitchen-sink-patches/finish/24-hpn-14-kitchen-sink-patches/102-openssh-6-3p1-hpnssh14v2-kitchen-sink-patch
  tasks:
  - include: tasks/compfuzor.includes type=src
  - get_url: url={{ hpnssh14v2_kitchen_sink_patch }} dest=hpnssh14v2-kitchen-sink.patch
