---
- hosts: all
  vars:
    TYPE: pam-ssh-agent-auth-arch
    INSTANCE: main
    REPO: https://aur.archlinux.org/pam_ssh_agent_auth
    ETC_FILES:
      - name: replacement-build
        content: |
          # via https://aur.archlinux.org/packages/pam_ssh_agent_auth#comment-1036640
          build() {
            cd "$srcdir/$pkgname"
            curl -o gcc14.patch https://sources.debian.org/data/main/p/pam-ssh-agent-auth/0.10.3-11/debian/patches/1000-gcc-14.patch
            curl -o configure.patch https://sources.debian.org/data/main/p/pam-ssh-agent-auth/0.10.3-11/debian/patches/fix-configure.patch
            patch -Np1 -i ./gcc14.patch
            patch -Np1 -i ./configure.patch
            autoconf
            ./configure --prefix=/usr --with-mantype=man --libexecdir=/usr/lib/security --without-openssl-header-check
            # also have to edit makefile CLFAGS adding -Wno-incompatible-pointer-types
            make
          }
    BINS:
      - name: build.sh
        content: |
          echo hiho
  tasks:
    - import_tasks: tasks/compfuzor.includes
