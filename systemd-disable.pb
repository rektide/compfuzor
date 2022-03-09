---
- hosts: all
  vars:
    TYPE: systemd-disable
    INSTANCE: main
    ETC_FILES:
    - name: system.units
      content: "{{system|join('\n')}}"
    - name: user.units
      content: "{{user|join('\n')}}"
    BINS:
    - name: disable.sh
      content: |
        action="${1:-disable}"
        target="${2:-system}"
        source="${3:-{{ETC}}/$target.units}"
        shift || true; shift || true; shift || true
        list="$(cat $source)"
        systemctl --$target $action $list $*
    system:
    - snapper-boot.service
    - snapper-cleanup.service
    - snapper-timeline.service
    - snapperd.service
    - wpa_supplicant.service
    - NetworkManager.service
    - gdm3.service
    - prometheus-smokeping-prober.service
    - prometheus-node-exporter-smartmon.timer
    - prometheus-node-exporter-smartmon.service
    - prometheus-node-exporter-nvme.timer
    - prometheus-node-exporter-nvme.service
    - prometheus-node-exporter-mellanox-hca-temp.timer
    - prometheus-node-exporter-mellanox-hca-temp.service
    - prometheus-node-exporter-ipmitool-sensor.timer
    - prometheus-node-exporter-ipmitool-sensor.service
    - prometheus-node-exporter-apt.timer
    - prometheus-node-exporter-apt.service
    - prometheus-pushgateway.service
    - prometheus-process-exporter.service
    - prometheus-postgres-exporter.service
    - prometheus-node-exporter.service
    - prometheus-homeplug-exporter.service
    - prometheus-blackbox-exporter.service
    - prometheus-alertmanager.service
    - prometheus.service
    - tinc.service
    - accounts-daemon.service
    - switcheroo-control.service
    - spacenavd.service
    - resolvconf.service
    - plymouth-quit-wait.service
    - plymouth-read-write.service
    - plymouth-start.service
    - pgcluu_collectd.service
    - oomd.service
    - auditd.service
    - dundee.service
    - ofono.service
    - lxc-net.service
    - lxc.service
    - lxcfs.service
    - mumble-server.service
    - olpc-powerd.service
    - smbd.service
    - nmbd.service
    - apt-cacher-ng.service
    - libvirtd.service
    - libvirt-guests.service
    - neard.service
    - rbdmap.service
    - pulseaudio-enable-autospawn.service
    - e2scrub_all.timer
    - udisks2.service
    user:
    - tracker-miner-fs-3.service
    - dirmngr.service
    - mmsd-tng.service
  tasks:
  - include: tasks/compfuzor.includes type=opt
