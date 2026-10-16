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
    title: NFS playbooks, validation and ownership corrections, loopback verification, and no-sudo nanomachine staging
  - resource: /cifs.etc.pb
    title: Existing separate systemd mount and automount pattern
  - resource: /nfs-export.srv.pb
    title: Export declaration, scoped installer, and validation
  - resource: /nfs.etc.pb
    title: NFS mount and automount declaration
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
[existing CIFS mounts](/cifs.etc.pb) and fstab unchanged unless a separate cutover
is explicitly chosen. For named-export composition, no-sudo SSH staging, actual
host findings, and performance choices, see
[Nanomachine staging and tuning](/doc/nfs/nanomachine.md).

## Loopback trial

Render both deployments without installing packages or activating services:

```sh
ansible-playbook -i 'localhost,' -c local nfs-export.srv.pb \
  -e PKGS_BYPASS=True -e GLOBAL_BINS_BYPASS=True
ansible-playbook -i 'localhost,' -c local nfs.etc.pb \
  -e PKGS_BYPASS=True -e GLOBAL_BINS_BYPASS=True
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

The export installer creates a missing directory for the rendering user, even
when installation runs through sudo, but
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
Export clients currently support IPv4 addresses/subnets, hostnames, wildcard
hostnames, and netgroups, not IPv6 literals. Paths use a conservative
whitespace-free character set; dot components and trailing slashes are rejected.
For production, prefer exporting a filesystem root. Subdirectory exports with
`no_subtree_check` are not a strong isolation boundary against malicious clients;
see [exports(5), Subdirectory Exports](https://man7.org/linux/man-pages/man5/exports.5.html).

Server `export_opts` defaults to `rw,sync,no_subtree_check,root_squash`.
Client `mount_opts` appends to `vers=4.2,proto=tcp,hard,softreval,_netdev,nconnect=3`;
`idle` defaults to `15min`. Connections pool per server endpoint: every mount
to one endpoint shares the first mount's transport pool (and, on v4.1+, its
session/credits), so keep client instances to the same endpoint configured
alike — the shared default does. Hard mounts preserve retry semantics during outages, so processes
doing I/O may block until the server returns; `softreval` (2026-10-16) lets
timed-out attribute revalidation serve cache so listing and browsing stay
responsive while writes keep hard semantics. The considered-and-rejected
tuning menu (soft/softerr, nocto/actimeo, noac, nolock; async, wdelay,
nfsd threads) is recorded in the two playbooks' headers where the knobs live. Use another `vers=` only after
checking the server's capabilities. Mounted sub-filesystems are not implicitly
exported with `crossmnt`; declare them deliberately if needed.

## Reconfiguration and deliberate removal

Changing a declaration and rerunning its installer updates that declaration.
It does not stop or unexport older deployments. In particular, changing the
export path or client list does not immediately revoke old active export entries;
the distribution's next server restart reconciles its persistent fragments. Remove
those deliberately with `sudo exportfs -u CLIENT:/old/path`, and remove obsolete
fragments so they cannot return at server restart.

Systemd does not remount an already active mount just because its unit changed.
Stop users of the mount, stop its automount and mount, then rerun the installer.
Do not test a second filesystem on the path of an active CIFS mount.

For the default trial, stop the client first:

```sh
sudo systemctl disable --now 'mnt-nfs\x2dtest.automount'
sudo systemctl stop 'mnt-nfs\x2dtest.mount'
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
user-scope/root-path configurations. A mocked installer run checks publication
order, literal wildcard clients, preservation of existing data/permissions,
and failure before activation when the link runtime is missing. It is not a
replacement for the live trial.

### Observed local verification — 2026-10-14

On Linux `7.1.0-debplus.1`, Debian NFS utilities `3.1.1`, with a Btrfs export:

- The render-only probe passed, including embedded-whitespace/newline, quoting,
  empty-client-list, user-scope, and root-path rejection checks.
- Both generated `bin/install.sh` commands completed. `exportfs -v` showed only
  `127.0.0.1` for this export, with `sync` and `root_squash`; `findmnt` showed
  `vers=4.2,hard,proto=tcp`.
- Normal-user write/read, fsync, numeric ownership, chmod, symlinks, rename, and
  server-to-client visibility passed. Client root was denied writes as expected.
- Re-running the export installer through sudo preserved the existing export
  directory's ownership, group, and permissions.
- `systemd-analyze verify` accepted both installed units, with unrelated warnings
  from existing host units.

The loopback deployment was left enabled for further experiments. This verifies
one host/filesystem combination, not nanomachine or a Samba migration.

### Observed nconnect application — 2026-10-16

The client baseline gained `nconnect=3`. The loopback client was re-rendered
and reinstalled (its mount was idle-unmounted, so the automount picked up the
new unit on the next trigger). `findmnt` reports `nconnect=3` in effect;
`ss` shows exactly three established loopback TCP connections to port 2049 —
the one shared pool, not a set per mount — and the file-operation/root-squash
probe still passes.

The use of scoped updates rather than global reconciliation follows
[exportfs(8)](https://man7.org/linux/man-pages/man8/exportfs.8.html): `-i -o`
updates a named client/path, while `-r` also revokes entries missing from the
host's configuration. The latter is deliberately not part of this installer.
The distribution's server unit still applies the host's exports on server
startup and removes them on server stop; these playbooks do not replace that
host-wide lifecycle.
