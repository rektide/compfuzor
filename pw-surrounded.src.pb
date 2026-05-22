---
# pw-surrounded — PipeWire virtual 5.1 surround via filter-chain (git src)
#
# Clones the pw-surrounded repo and runs surround-51-activate as a user
# systemd service. The service generates the filter-chain config, installs
# it to pipewire.conf.d, restarts PipeWire, and wires output ports to
# hardware devices.
#
# Mixing parameters and device routing are configured via env vars
# (PW_SURROUND_*), matching the conventions from pw-surround.etc.pb.
#
- hosts: all
  vars:
    REPO: https://github.com/rektide/pw-surrounded
    NODEJS: True

    USERMODE: True
    SYSTEMD_SERVICE: True
    SYSTEMD_SCOPE: user
    SYSTEMD_UNITS:
      After: pipewire.service
      PartOf: pipewire.service
      BindsTo: pipewire.service
    SYSTEMD_EXEC: >-
      node {{SRC}}/surround-51-activate.ts --install
    SYSTEMD_SERVICES:
      Type: oneshot
      RemainAfterExit: true
      SyslogIdentifier: pw-surrounded
    SYSTEMD_INSTALLS:
      WantedBy: pipewire.service
    SYSTEMD_LINK: False

    ENV:
      PW_SURROUND_FRONT_MIX: "0.7"
      PW_SURROUND_CENTER_MIX: "0.4"
      PW_SURROUND_HIGHPASS: "0"
      PW_SURROUND_SUB_LFE: "1.0"
      PW_SURROUND_SUB_MAIN: "0.0"
      PW_SURROUND_SUB_CENTER: "0.0"
      PW_SURROUND_DEVICE_L: "alsa_output.usb-Generic_BS5P-ARC_20170726905955-00.analog-stereo,alsa_output.usb-QTIL_LP-UNF_ABCDEF0123456789-00.analog-stereo"
      PW_SURROUND_DEVICE_R: "alsa_output.usb-WEIL_WEILIANG_24BIT_USB-01.analog-stereo"
      PW_SURROUND_DEVICE_C: "alsa_output.usb-Dell_Dell_AC511_USB_SoundBar-00.analog-stereo"
      PW_SURROUND_DEVICE_SUB: "alsa_output.usb-Creative_Technology_Ltd_SB_X-Fi_Surround_5.1_Pro_00000658-00.analog-stereo"
  tasks:
    - import_tasks: tasks/compfuzor.includes
