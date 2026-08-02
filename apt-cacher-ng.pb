---
# apt-cacher-ng -- legacy C++ apt caching proxy (distro package).
#
# Superseded by apt-cacher-rs.src.pb (the active Rust successor; apt-cacher-rs
# even declares `Conflicts: apt-cacher, apt-cacher-ng` in its packaging). Kept
# here as the quick "install the distro package" path for releases that still
# ship it -- apt-cacher-ng was dropped from Debian around trixie.
#
# Hand-rolled rather than via compfuzor.includes: the hyphenated bare filename
# defeats compfuzor's filename-suffix type detection (vars_base.tasks:94 would
# parse the type as "ng"), and the package ships its own apt-cacher-ng.service
# so the systemd-generation subsystem does not apply. For a from-source,
# compfuzor-subsystem-managed cache, use apt-cacher-rs.src.pb.
#
# Clients (including this host, once the service is up) -- port 3142, same as
# apt-cacher-rs, so the snippet is identical:
#   echo 'Acquire::http::Proxy "http://<host>:3142/";' \
#     > /etc/apt/apt.conf.d/30proxy
- hosts: all
  become: true
  tasks:
    - name: Install apt-cacher-ng
      apt:
        name: apt-cacher-ng
        state: latest
        update_cache: true

    - name: Enable and start apt-cacher-ng
      service:
        name: apt-cacher-ng
        state: started
        enabled: true
