---
- hosts: all
  vars:
    TYPE: kernel-epp
    INSTANCE: main
    SYSTEMD_SERVICE: True
    SYSTEMD_TYPE: oneshot
    SYSTEMD_EXEC: "{{DIR}}/bin/setup.sh"
    BINS:
      - name: setup.sh
        content: |
          find -L /sys/devices/system/cpu -maxdepth 3 -name "energy_performance_preference" -print0 2>/dev/null |
            while IFS= read -r -d '' cpu
            do
              echo $cpu
              echo $ENERGY_PERFORMANCE_PREFERENCE | sudo tee $cpu >/dev/null
            done
    ENV:
      - energy_performance_preference
    energy_performance_preference: balance_power
  tasks:
    - include: tasks/compfuzor.includes type=etc
