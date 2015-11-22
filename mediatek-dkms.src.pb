---
- hosts: all
  vars:
    TYPE: mediatek-mt7612u
    INSTANCE: git
    TGZ: http://cdn-cw.mediatek.com/Downloads/linux/MT7612U_DPO_LinuxSTA_3.0.0.1_20140718.tar.bz2
    BINS:
    - prep-build.sh
    VAR_FILES:
    - kuid_t.patch
  tasks:
  - include: tasks/compfuzor.includes type=src
