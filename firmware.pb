---
- hosts: all
  tasks:
  - name: install
    apt: state=latest pkg=firmware-atheros,firmware-brcm80211,firmware-iwlwifi,firmware-libertas,firmware-ralink,firmware-realtek
