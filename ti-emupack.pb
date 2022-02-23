---
- hosts: all
  vars:
    TYPE: ti-emupack
    INSTANCE: main
    GET_URLS:
    - "https://software-dl.ti.com/dsps/dsps_public_sw/sdo_ccstudio/emulation/exports/{{emupack_bin}}"
    emupack_bin: ti_emupack_setup_9.2.0.00002_linux_x86_64.bin
    ENV:
      EMUPACK_BIN: "{{emupack_bin}}"
    BINS:
    - name: install.sh
      run: True
      basedir: True
      exec: |
        chmod +x ./src/$EMUPACK_BIN
        ./src/$EMUPACK_BIN --unattendedmodeui minimal --mode unattended --prefix /opt/ti-emupack
    - name: xds1100-update.sh
      basedir: ccs_base/common/uscif/xds110
      exec: |
        set -e
        # check for unit
        ./xdsdfu -e
        # put in dfu mode
        ./xdsdfu -m
        # flash then reset
        ./xdsdfu -f firmware_3.0.0.13.bin -r
  tasks:
  - include: tasks/compfuzor.includes type=opt
