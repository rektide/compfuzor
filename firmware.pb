---
- hosts: all
  vars_files:
  - vars/apt.vars
  tasks:
  - name: install
    apt: state=$APT_INSTALL pkg=firmware-atheros,firmware-brcm80211,firmware-iwlwifi,firmware-libertas,firmware-ralink,firmware-realtek
