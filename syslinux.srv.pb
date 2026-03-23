---
- hosts: all
  vars:
    TYPE: syslinux
    INSTANCE: bios
    BINS_RUN_BYPASS: True

    PKGSET:
    PKGS:
      - syslinux-common
      - syslinux-utils
      - extlinux
      - mbr

    VAR_DIRS:
      - mnt
      - mnt/boot

    syslinux_dev: /dev/sdb
    syslinux_boot_part: "{{syslinux_dev}}1"
    syslinux_mnt_boot: "{{VAR}}/mnt/boot"
    syslinux_dir: /syslinux
    syslinux_table: msdos
    syslinux_mbr_bin: "{{ '/usr/lib/syslinux/mbr/gptmbr.bin' if syslinux_table == 'gpt' else '/usr/lib/syslinux/mbr/mbr.bin' }}"

    syslinux_label: linux
    syslinux_menu_title: "Compfuzor BIOS Syslinux"
    syslinux_timeout: 50
    syslinux_root: "{{syslinux_boot_part}}"
    syslinux_append: rw
    syslinux_kernel: /boot/vmlinuz
    syslinux_initrd: /boot/initrd.img
    syslinux_kernel_name: vmlinuz
    syslinux_initrd_name: initrd.img

    ETC_FILES:
      - name: syslinux.cfg
        content: |
          UI menu.c32
          PROMPT 0
          MENU TITLE {{syslinux_menu_title}}
          TIMEOUT {{syslinux_timeout}}
          DEFAULT {{syslinux_label}}

          LABEL {{syslinux_label}}
            LINUX /{{syslinux_kernel_name}}
            INITRD /{{syslinux_initrd_name}}
            APPEND root={{syslinux_root}} {{syslinux_append|default('', true)}}

    ENV:
      SYSLINUX_DEV: "{{syslinux_dev}}"
      SYSLINUX_BOOT_PART: "{{syslinux_boot_part}}"
      SYSLINUX_MNT_BOOT: "{{syslinux_mnt_boot}}"
      SYSLINUX_DIR: "{{syslinux_dir}}"
      SYSLINUX_MBR_BIN: "{{syslinux_mbr_bin}}"
      SYSLINUX_KERNEL: "{{syslinux_kernel}}"
      SYSLINUX_INITRD: "{{syslinux_initrd}}"
      SYSLINUX_KERNEL_NAME: "{{syslinux_kernel_name}}"
      SYSLINUX_INITRD_NAME: "{{syslinux_initrd_name}}"
      SYSLINUX_LABEL: "{{syslinux_label}}"
      SYSLINUX_ROOT: "{{syslinux_root}}"
      SYSLINUX_APPEND: "{{syslinux_append|default('', true)}}"

    BINS:
      - name: mount-boot.sh
        content: |
          [ -b "$SYSLINUX_BOOT_PART" ] || { echo "missing block device: $SYSLINUX_BOOT_PART"; exit 2; }
          mkdir -p "$SYSLINUX_MNT_BOOT"

          if ! mountpoint -q "$SYSLINUX_MNT_BOOT" 2>/dev/null; then
            mount "$SYSLINUX_BOOT_PART" "$SYSLINUX_MNT_BOOT"
          fi

          findmnt "$SYSLINUX_MNT_BOOT"

      - name: install-kernel.sh
        content: |
          "{{BINS_DIR}}/mount-boot.sh"

          [ -r "$SYSLINUX_KERNEL" ] || { echo "missing kernel: $SYSLINUX_KERNEL"; exit 3; }
          [ -r "$SYSLINUX_INITRD" ] || { echo "missing initrd: $SYSLINUX_INITRD"; exit 4; }

          BOOTDIR="$SYSLINUX_MNT_BOOT$SYSLINUX_DIR"
          mkdir -p "$BOOTDIR"

          cp -Lf "$SYSLINUX_KERNEL" "$BOOTDIR/$SYSLINUX_KERNEL_NAME"
          cp -Lf "$SYSLINUX_INITRD" "$BOOTDIR/$SYSLINUX_INITRD_NAME"
          cp -f "{{ETC}}/syslinux.cfg" "$BOOTDIR/syslinux.cfg"

          echo "Installed kernel, initrd, and syslinux.cfg to $BOOTDIR"

      - name: install-bios.sh
        content: |
          "{{BINS_DIR}}/mount-boot.sh"

          BOOTDIR="$SYSLINUX_MNT_BOOT$SYSLINUX_DIR"
          MODDIR=/usr/lib/syslinux/modules/bios
          mkdir -p "$BOOTDIR"

          [ -d "$MODDIR" ] || { echo "missing syslinux modules: $MODDIR"; exit 5; }

          extlinux --install "$BOOTDIR"
          cp -f "$MODDIR/menu.c32" "$BOOTDIR/"
          cp -f "$MODDIR/libcom32.c32" "$BOOTDIR/"
          cp -f "$MODDIR/libutil.c32" "$BOOTDIR/"

          if [ -f "$MODDIR/ldlinux.c32" ]; then
            cp -f "$MODDIR/ldlinux.c32" "$BOOTDIR/"
          fi

          cp -f "{{ETC}}/syslinux.cfg" "$BOOTDIR/syslinux.cfg"
          echo "Installed BIOS syslinux files into $BOOTDIR"

      - name: install-mbr.sh
        content: |
          [ -b "$SYSLINUX_DEV" ] || { echo "missing disk device: $SYSLINUX_DEV"; exit 6; }
          [ -r "$SYSLINUX_MBR_BIN" ] || { echo "missing mbr bootstrap: $SYSLINUX_MBR_BIN"; exit 7; }

          dd if="$SYSLINUX_MBR_BIN" of="$SYSLINUX_DEV" bs=440 count=1 conv=notrunc
          sync
          echo "Wrote MBR bootstrap from $SYSLINUX_MBR_BIN to $SYSLINUX_DEV"

      - name: install-all.sh
        content: |
          "{{BINS_DIR}}/install-kernel.sh"
          "{{BINS_DIR}}/install-bios.sh"
          "{{BINS_DIR}}/install-mbr.sh"

          echo "Done. Validate with:"
          echo "  ls -la $SYSLINUX_MNT_BOOT$SYSLINUX_DIR"
          echo "  hexdump -C -n 440 $SYSLINUX_DEV | head"

      - name: unmount-boot.sh
        content: |
          if mountpoint -q "$SYSLINUX_MNT_BOOT" 2>/dev/null; then
            umount "$SYSLINUX_MNT_BOOT"
          fi

  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: srv
