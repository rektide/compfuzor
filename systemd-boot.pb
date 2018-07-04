- hosts: all
  vars:
    TYPE: systemd-boot
    INSTANCE: main
    BINS:
    - name: zz-systemd-boot
      comments: hooks via https://wiki.debian.org/EFIStub
      content: |
        echo "zz-systemd-boot copying in boot targets"
        cp -v /{vmlinuz,initrd.img,vmlinuz.old,initrd.img.old} $EFI_DIR/
    - name: import-grub-cmdline.sh
      run: True
      comments: possible source for the all-important root= cmdline
      content: |
        cmdline_full="$(grep -e '^GRUB_CMDLINE_LINUX="' /etc/default/grub)"
        cmdline="${cmdline_full%\"}"
        cmdline="${cmdline#GRUB_CMDLINE_LINUX=\"}"
        echo $cmdline > $ETC/grub-cmdline.options
    - name: install-loader-conf.sh
      run: "{{systemd_boot_install|default(False)}}"
      content: |
        cat <<LOADER >$EFI_DIR/loader/loader.conf
        default debian
        timeout 3
        LOADER
    - name: install-entries.sh
      run: "{{systemd_boot_install|default(False)}}"
      comments: entries for systemd
      become: True
      content: |
        [ -z "$systemd_boot_cmdline" ] && systemd_boot_cmdline="$(cat $ETC/grub-cmdline.options) $(cat $ETC/cmdline.options) $EFI_CMDLINE"

        cat <<ENTRY >$EFI_DIR/loader/entries/debian.conf
        title debian
        linux /vmlinuz
        initrd /initrd.img
        options initrd=\initrd.img ${systemd_boot_cmdline}
        ENTRY

        cat <<ENTRY >$EFI_DIR/loader/entries/debian.old.conf
        title debian
        linux /vmlinuz.old
        initrd /initrd.img.old
        options initrd=\initrd.img.old ${systemd_boot_cmdline}
        ENTRY
    - name: install-boot.sh
      run: "{{do_systemd_boot_install|default(False)}}"
      become: True
      content: |
        bootctl install --path="$EFI_DIR"
    ETC_FILES:
    - name: cmdline.options
      content: "{{cmdline}}"
    - name: grub-cmdline.options
      content: ""
    VAR_DIR: True
    ENV:
      EFI_DIR: "{{DIR}}/var/efi"
      EFI_CMDLINE: ""
      VAR: "{{DIR}}/var"
      ETC: "{{DIR}}/etc"
    LINKS:
      "{{VAR}}/efi": "{{efi}}"
      "/etc/kernel/postinst.d/zz-systemd-boot": "{{DIR}}/bin/zz-systemd-boot"
      "/etc/initramfs/post-update.d/zz-systemd-boot": "{{DIR}}/bin/zz-systemd-boot"
    systemd_boot_install: False
    efi: /boot
    cmdline: "add_efi_memmap"
  tasks:
  - include: tasks/compfuzor.includes type=etc
