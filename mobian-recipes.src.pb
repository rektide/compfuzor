---
- hosts: all
  vars:
    REPO: https://salsa.debian.org/Mobian-team/mobian-recipes.git
    MOBIAN_KERNEL: linux-image-7.2-sdm845
    MOBIAN_ENVIRONMENT: plasma-mobile
    MOBIAN_DEBIAN_SUITE: sid
    MOBIAN_SUITE: staging
    PKGS:
      - git
      - rsync
      - python3
      - debos
      - debootstrap
      - bmap-tools
      - xz-utils
      - qemu-system-x86
      # Modern Debian's qemu-user is static; registration lives in this package.
      - qemu-user-binfmt
      - binfmt-support
      - android-sdk-libsparse-utils
      - yq
      - mkbootimg
    BINS:
      - name: build.sh
        # Image builds are explicitly invoked after provisioning.
        run: false
    README: |
      # Mobian SDM845 / Plasma Mobile

      Run `{{DIR}}/bin/build.sh` to build an arm64 SDM845 image with debos:
      Debian {{MOBIAN_DEBIAN_SUITE}}, Mobian {{MOBIAN_SUITE}},
      {{MOBIAN_ENVIRONMENT}}, and {{MOBIAN_KERNEL}}.

      Recipes are copied from `{{REPO_DIR}}` into `{{DIR}}/build` before
      applying the kernel selection. Images and rootfs archives land in
      `{{DIR}}/build`. Upstream build.sh options are forwarded, e.g. `-z`
      for compression or `-m 4G` for build VM memory. Use `ARGS='--dry-run
      --print-recipe' {{DIR}}/bin/build.sh` to inspect the debos recipes.

      Debos/fakemachine temporary storage defaults to `{{DIR}}/tmp` on the
      deployment filesystem; export TMPDIR to override it.

      The SDM845 support metapackage currently depends on a different kernel;
      the build installs qcom-support-common and the requested kernel directly.
      Boot images select the kernel version from that package's file list.
      Default image login is upstream's `mobian` / `1234`; use `-u` / `-p`
      to customize it. Debos normally uses /dev/kvm (the builder needs access).

      For a host without working KVM/QEMU, debos can build directly using
      root privileges and the host's registered arm64 binfmt interpreter:
      `sudo env ARGS=--disable-fakemachine TMPDIR={{DIR}}/tmp {{DIR}}/bin/build.sh`.
  tasks:
    - import_tasks: tasks/compfuzor.includes
