---
type: Guide
title: NFS exports and automounts
description: Separate server and client deployments, starting with a loopback export before a deliberate Samba migration.
resource: /doc/nfs/README.md
status: draft
generated:
  by: model:openai/gpt-6.1-sol#high
  at: 2026-10-14
sources:
  - resource: opencode://ses_ec3b9dd3effe33r8JIOsc5WGTJ
    title: NFS playbook direction, integration review, and local verification
  - resource: /cifs.etc.pb
    title: Existing separate systemd mount and automount pattern
  - resource: https://man7.org/linux/man-pages/man8/exportfs.8.html
    title: Scoped export updates and exports.d persistence
  - resource: https://man7.org/linux/man-pages/man5/exports.5.html
    title: Export access rules, AUTH_SYS identities, and subdirectory limitations
---

# NFS exports and automounts

- [nfs-export.srv.pb](/nfs-export.srv.pb) stages an exports.d fragment and an
  installer for the distribution's NFS server. It does not replace its unit.
- [nfs.etc.pb](/nfs.etc.pb) stages systemd `.mount` and `.automount` units.
  Only the automount is enabled; accessing its path mounts the export.

These are independent deployments. They leave [Samba](/samba.srv.pb),
[existing CIFS mounts](/cifs.etc.pb), fstab, and nanomachine unchanged.

## Loopback trial

Render both deployments without installing packages or activating services:

```sh
ansible-playbook -i 'localhost,' -c local nfs-export.srv.pb -e PKGS_BYPASS=True
ansible-playbook -i 'localhost,' -c local nfs.etc.pb -e PKGS_BYPASS=True
```

Then explicitly install their packages, publish configuration, and activate:

```sh
/srv/nfs-export-test/bin/install.sh
/etc/opt/nfs-test/bin/install.sh
```

Installers use sudo for privileged operations. Defaults export `/srv/nfs-test`
to **127.0.0.1 only**, mounted on `/mnt/nfs-test`. The server package may listen
on other interfaces; the client restriction is an export access rule, not a
network firewall or a change to the distribution's protocol configuration.

Exercise the mount as your normal user, not root:

```sh
printf 'loopback NFS trial\n' > /mnt/nfs-test/probe
cmp /mnt/nfs-test/probe /srv/nfs-test/probe
ln -s probe /mnt/nfs-test/probe-link
readlink /srv/nfs-test/probe-link
findmnt --mountpoint /mnt/nfs-test
sudo exportfs -v
```

The export installer creates a missing directory for the invoking user, but
does **not** change an existing directory's ownership or permissions. With
`root_squash`, client root is mapped to the anonymous identity and normally
cannot write this user-owned directory. NFS AUTH_SYS uses numeric UID/GID
credentials; unlike CIFS, there is no credentials file or forced client-side
`uid=`/`gid=` ownership. Align identities before using separate machines.

## Configure another export or client

Server example (run on the exporting host):

```sh
ansible-playbook -i 'localhost,' -c local nfs-export.srv.pb \
  -e INSTANCE=media -e export_path=/srv/media \
  -e '{"clients":["192.168.1.42"]}' -e PKGS_BYPASS=True
/srv/nfs-export-media/bin/install.sh
```

Client example (run on the mounting host):

```sh
ansible-playbook -i 'localhost,' -c local nfs.etc.pb \
  -e INSTANCE=media -e srv=fileserver \
  -e export_path=/srv/media -e where=/mnt/media -e PKGS_BYPASS=True
/etc/opt/nfs-media/bin/install.sh
```

Use a specific client address or a deliberately chosen trusted subnet, not
`*`. AUTH_SYS is not suitable for untrusted networks; it does not authenticate
the remote machine's users or encrypt traffic. Firewall the server accordingly.
The playbooks do not configure Kerberos, TLS, firewall rules, or identity maps.
For production, prefer exporting a filesystem root. Subdirectory exports with
`no_subtree_check` are not a strong isolation boundary against malicious clients;
see [exports(5), Subdirectory Exports](https://man7.org/linux/man-pages/man5/exports.5.html).

Server `export_opts` defaults to `rw,sync,no_subtree_check,root_squash`.
Client `mount_opts` appends to `vers=4.2,proto=tcp,hard,_netdev`; `idle` defaults
to `15min`. Hard mounts preserve retry semantics during outages, so processes
doing I/O may block until the server returns. Use another `vers=` only after
checking the server's capabilities. Mounted sub-filesystems are not implicitly
exported with `crossmnt`; declare them deliberately if needed.

## Reconfiguration and deliberate removal

Changing a declaration and rerunning its installer updates that declaration.
It does not stop or unexport older deployments. In particular, changing the
export path or client list does not revoke old active export entries; remove
those deliberately with `sudo exportfs -u CLIENT:/old/path`, and remove obsolete
fragments so they cannot return at server restart.

Systemd does not remount an already active mount just because its unit changed.
Stop users of the mount, stop its automount and mount, then rerun the installer.
Do not test a second filesystem on the path of an active CIFS mount.

For the default trial, stop the client first:

```sh
sudo systemctl disable --now mnt-nfs\\x2dtest.automount
sudo systemctl stop mnt-nfs\\x2dtest.mount
sudo exportfs -u 127.0.0.1:/srv/nfs-test
```

Remove only the corresponding managed unit links and exports.d fragment if
retiring the deployment, then `sudo systemctl daemon-reload`. Leave data and
other exports alone. Disabling the NFS server is a separate host-wide decision.

## Future Samba migration

The [CIFS playbook](/cifs.etc.pb) is the unit-layout precedent, not a migration
trigger. A later switch needs the actual export path, allowed client addresses,
UID/GID alignment, filesystem/submount requirements, and an explicit cutover of
the existing mountpoint. None of those decisions is implied by the loopback
trial or by these example hostnames.

## Render-only regression check

```sh
python3 tests/integration/nfs.test.py
```

The [integration probe](/tests/integration/nfs.test.py) renders the real playbooks
under `.test-agent/nfs/` without installing packages or starting services. It
checks export defaults, mount/automount contents, client overrides, and rejected
user-scope/root-path configurations. It is not a replacement for the live trial.

The use of scoped updates rather than global reconciliation follows
[exportfs(8)](https://man7.org/linux/man-pages/man8/exportfs.8.html): `-i -o`
updates a named client/path, while `-r` also revokes entries missing from the
host's configuration. The latter is deliberately not part of this installer.
The distribution's server unit still applies the host's exports on server
startup and removes them on server stop; these playbooks do not replace that
host-wide lifecycle.
