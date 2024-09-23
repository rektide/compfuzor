---
- hosts: all
  vars:
    TYPE: esniper
    INSTANCE: cvs
    CVS_REPO: pserver:anonymous@esniper.cvs.sourceforge.net:/cvsroot/esniper
    CVS_MODULE: esniper
  tasks:
  - include: tasks/compfuzor.includes type=src
