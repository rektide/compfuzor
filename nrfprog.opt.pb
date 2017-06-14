---
- hosts: all
  vars:
    TYPE: nrfprog
    INSTANCE: 9.4.0
    GET_URLS:
    - url: https://www.nordicsemi.com/eng/nordic/download_resource/51386/21/90266232/94917
      dest: "{{tar}}"
    BINS:
    - basedir: "{{DIR}}/nrfjprog"
      dest: "nrfjprog"
      global: True
    tar: "nRF5x-Command-Line-Tools_{{INSTANCE|replace('.', '_')}}_Linux-x86_64.tar"
  tasks:
  - set_fact:
    args:
      _global_bins_bypass: "{{GLOBAL_BINS_BYPASS|default(False)}}"
      GLOBAL_BINS_BYPASS: True
  - include: tasks/compfuzor.includes type=src
  - unarchive:
    args:
      src: "{{SRC}}/{{tar}}"
      dest: "{{SRC}}"
  - include: tasks/compfuzor/bins_link_global.tasks
    when: not _global_bins_bypass
