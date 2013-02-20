---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars_files:
  - vars/common.vars
  vars:
    PKGS:
    - eclipse-cdt
    - eclipse-cdt-autotools
    - eclipse-cdt-valgrind
    - eclipse-cdt-valgrind-remote
    - eclipse-egit
    - eclipse-egit-mylyn 
    - eclipse-mylyn
    - eclipse-mylyn-builds-hudson
    - eclipse-mylyn-context-cdt
    - eclipse-mylyn-context-jdt
    - eclipse-mylyn-context-pde
    - eclipse-mylyn-wikitext
    - eclipse-cdt-jni
    - eclipse-rse
    - eclipse-anyedit
    - eclipse-cdt-perf
    - eclipse-cdt-pkg-config
    - eclipse-cdt-profiling-framework
    - eclipse-cdt-profiling-framework-remote
    - eclipse-subclipse
    - eclipse-subclipse-graph
    - eclipse-subclipse-mylyn
    - eclipse-wtp
    - eclipse-wtp-servertools
    - eclipse-wtp-webtools
    - eclipse-wtp-ws
    - eclipse-wtp-xmltools
    - eclipse-wtp-xsl
    - eclipse
    - eclipse-jdt
    - eclipse-pde
    - eclipse-platform
    - eclipse-platform-data
    - eclipse-rcp
    - eclipse-emf
  tasks:
  - apt: state=${APT_INSTALL} pkg=$item
    with_items: $PKGS
