---
- hosts: all
  vars:
    TYPE: mkosi
    INSTANCE: main
    ENV:
      scratchsize: "{{scratchsize|default()}}"
      hostname: "{{hostname|default('debos')}}"
      user: "{{user|default(ansible_user_id)}}"
      password: "{{password|default('CHANGE_OR_ELSE')}}"
    MKOSI_PKGSETS:
      - BASE
      - BASE_amd64
      - WORKSTATION
      - VIRTUALIZATION
      - WORKSTATION_X
      - OPENCL
      - XPRA
      - DEVEL
      - DEBDEV
      - AUDIO
      - AUDIO_X
      - BT
      - BT_X
      - RYGEL
      - RYGEL_X
      - USERSPACE
      - JACK
      - JACK_X
      - MEDIA
      - VAAPI
      - VAAPI_amd64
      - WORKSTATION_WAYLAND
      - MEDIA_X
      - POSTGRES
      - CONTAINER
      - BONUS
      - WORDS
    ETC_FILES:
      - name: pkgs.txt
        content: |
          {% set sep=joiner('\n') -%}
          {% for s in mmpkgset -%}
          {{sep()}}{{vars[s]|default(hostvars[inventory_hostname][s])|join(',')}}
          {%- endfor -%}
          linux-image-{{arch}},linux-headers-{{arch}}
      - name: mkosi.conf.d/pkgs.conf

      - name: mkosi.postinst
        content: |
          export DEBIAN_FRONTEND=noninteractive
          apt-get -y update
          #apt-get -y upgrade
      - name: mkosi.default
        content: |
          [Output]
          OutputDirectory=var/output
          CacheDirectory=var/cache
          PackageCacheDirectory=var/package-cache
          [Build]
          WithNetwork=true
          Incremental=true
      - name: mkosi.images/oci/mkosi.conf
        content: |
          [Output]
          Format=oci

          [Content]
          BaseTrees=%O/base
      - name: mkosi.images/disk/mkosi.conf
        content: |
          [Output]
          Format=rw btrfs
          CompressOutput=lz4

          [Content]
          BaseTrees=%O/base
      - name: mkosi.images/base/mkosi.conf
        content: |
          [Build]
          ToolsTree=default
          History=yes
          CacheDirectory=mkosi.cache
          Incremental=yes
          
          #Format=directory
          Format=disk

          SplitArtifacts=uki,partitions
          Format=disk
          ImageId=ParticleOS
          ManifestFormat=json
          Output=%i_%v_%a

          [Distribution]
          Distribution=debian
          Release=forky
          Repositories=main,contrib,non-free,non-free-firmware
          Architecture={{ARCH}}
          
          [Content]
          CleanPackageMetadata=no
          KernelCommandLine=
                  root=dissect
                  mount.usr=dissect
                  rw
                  audit=0
                  systemd.image_policy=esp=unprotected:xbootldr=unprotected+unused+absent:usr=signed:root=encrypted+absent:swap=encrypted+unused+absent:home=unprotected+absent:=ignore
                  systemd.image_filter=usr=ParticleOS_*:usr-verity=ParticleOS_*:usr-verity-sig=ParticleOS_*:root=ParticleOS-*:swap=ParticleOS-*:home=ParticleOS-*
          InitrdProfiles=
          KernelInitrdModules=default
          Hostname=particle-????-????
          
          Packages=
                  acl
                  attr
                  bash-completion
                  btrfs-progs
                  coreutils
                  cpio
                  curl
                  dbus-broker
                  diffutils
                  dmidecode
                  dosfstools
                  erofs-utils
                  findutils
                  fish
                  fwupd
                  gdb
                  gdisk
                  grep
                  gzip
                  jq
                  kbd
                  kmod
                  less
                  man
                  mtools
                  nano
                  nftables
                  nvme-cli
                  opensc
                  openssl
                  p11-kit
                  pciutils
                  pkcs11-provider
                  sed
                  socat
                  strace
                  systemd
                  tar
                  tree
                  udev
                  unzip
                  usbutils
                  util-linux
                  which
                  wireguard-tools
                  xxd
                  yubikey-manager
                  zstd
          
          VolatilePackages=
                  systemd
                  udev
          
          InitrdVolatilePackages=
                  systemd
                  udev
          
          [Validation]
          SecureBoot=yes
          SignExpectedPcr=yes
          
          [Runtime]
          RuntimeSize=30G
          RAM=4G
          CPUs=4
          Ephemeral=yes
          RuntimeScratch=no
          Credentials=
                  passwd.plaintext-password.root=particleos
                  tty.serial.hvc0.agetty.autologin=particleos
                  tty.serial.hvc0.login.noauth=yes
                  tty.console.agetty.autologin=particleos
                  tty.console.login.noauth=yes
                  tty.virtual.tty1.agetty.autologin=particleos
                  tty.virtual.tty1.login.noauth=yes 

      - name: mkosi.images/disk/mkosi.conf
        content:
    VAR_DIRS:
      - cache
      - output
      - package-cache
    LINKS:
      - src: var/cache
        dest: mkosi.cache
      - src: var/output
        dest: mkosi.output
      - src: var/package-cache
        dest: mkosi.package-cache
    BINS:
      - name: build-debian.sh
        exec: |
          # btrfs rootdir recommended!

          commaSep(){
            sed -E ':a;N;$!ba;s/\s+/ /g' $1
          }
          mkosi \
            --distribution debian \
            --release trixie \
            --format disk \
            --checksum \
            --root-password $PASSWORD
            --include mkosi-vm \
            --package $(commaSep etc/pkgs.txt)
            --repository-key-fetch yes
            --output var/image.raw $*
      - name: run-nspawn.sh
        exec: |
          systemd-nspawn --boot --image image.raw
    ARCH_PKGS:
      - debootstrap
      - debian-archive-keyring
      - apt




  tasks:
    - import_tasks: tasks/compfuzor.includes
