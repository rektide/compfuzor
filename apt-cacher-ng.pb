---
- hosts: all
  vars:
    TYPE: apt-cacher-ng
    INSTANCE: main

    # Legacy C++ apt caching proxy (distro package). Superseded by
    # apt-cacher-rs.src.pb; kept here for releases that still ship the package
    # (apt-cacher-ng was dropped from Debian around trixie). The package
    # provides and enables its own apt-cacher-ng.service, so this playbook only
    # installs it via the PKGS subsystem and drops client/README artifacts --
    # no SYSTEMD_* (we do not generate a unit over the package's own).
    PKGS:
      - apt-cacher-ng

    ETC_FILES:
      - name: 30proxy
        content: |
          # Client snippet -- install on apt clients (including this host, once
          # the service is up) to route through the proxy:
          #   cp {{DIR}}/etc/30proxy /etc/apt/apt.conf.d/30proxy
          # Edit the host below for remote clients. Port 3142 is identical to
          # apt-cacher-rs, so the snippet is interchangeable.
          Acquire::http::Proxy "http://127.0.0.1:3142/";

    README: |
      # apt-cacher-ng

      The legacy C++ apt caching proxy, installed from the distro package.
      Superseded by apt-cacher-rs.src.pb (the active Rust successor); kept for
      releases that still ship apt-cacher-ng (it was dropped from Debian around
      trixie).

      The package provides and enables its own `apt-cacher-ng.service` on
      port 3142. Config lives with the package at `/etc/apt-cacher-ng/acng.conf`
      (not under this DIR); this playbook only installs it and drops a client
      snippet + this README.

      ## Point apt clients at the proxy

          # cp {{DIR}}/etc/30proxy /etc/apt/apt.conf.d/30proxy

      (edit the host for remote clients). Web UI: http://<host>:3142/acng-report.html
  tasks:
  - import_tasks: tasks/compfuzor.includes
    vars:
      type: srv
