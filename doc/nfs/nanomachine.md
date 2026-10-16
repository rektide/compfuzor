---
type: Guide
title: Nanomachine NFS staging, composition, and tuning
description: Privilege-free preparation of the bitblaster export, independent export ownership, and evidence-led performance choices.
resource: /doc/nfs/nanomachine.md
status: draft
generated:
  by: model:openai/gpt-6.1-sol#high
  at: 2026-10-14
sources:
  - resource: opencode://ses_ec3b9dd3effe33r8JIOsc5WGTJ
    title: Nanomachine share inspection, share-set staging, workhorse client mounts via nanomachine.lan, automount interaction verification, and tuning
  - resource: /nfs-export.srv.pb
    title: Per-deployment export fragment and scoped installer
  - resource: /nfs.etc.pb
    title: Independent path-named client units
  - resource: /examples/nfs/stage-no-sudo.yaml
    title: Explicit render-only system-scope policy
  - resource: ssh://nanomachine/etc/opt/samba-main/smb.conf
    title: Effective Samba configuration inspected with testparm over SSH
  - resource: ssh://nanomachine/run/systemd/generator/mnt-bitblaster.mount
    title: Bitblaster mount/automount units inspected through systemctl cat
  - resource: https://man7.org/linux/man-pages/man5/nfs.5.html
    title: Linux NFS retry, transfer-size, cache, connection, and locking semantics
  - resource: https://man7.org/linux/man-pages/man5/exports.5.html
    title: Export options, mountpoint protection, identities, and nested exports
  - resource: file:///usr/share/man/man7/nfs.systemd.7.gz
    title: Installed nfs.systemd(7) manual, especially backing-mount generator ordering
  - resource: https://learn.microsoft.com/en-us/azure/azure-netapp-files/performance-linux-mount-options
    title: Linux nconnect first-mount behavior; appliance-specific tuning recommendations are not adopted
---

# Nanomachine NFS staging, composition, and tuning

This is preparation, **not** the Samba cutover. The [general NFS guide](/doc/nfs/README.md)
owns the playbooks' baseline behavior and loopback verification.

## Observed host state — 2026-10-14

SSH and Ansible work as `rektide`; passwordless sudo does not. `/srv` and
`/etc/opt` are writable by that user, so normal system-layout artifacts can be
rendered without elevation. Do not use `USERMODE`: the eventual NFS services
and mounts still require system scope.

- Kernel: `6.12.10-amd64`; Node: `24.21.0`.
- Existing service: `samba-main.service`, using `/etc/opt/samba-main/smb.conf`.
- Samba's `bitblaster` share is `/mnt/bitblaster`, an entire Btrfs filesystem
  on a USB rotational disk. Fstab supplies a mount plus an automount with a
  30-minute idle timeout. `torrent/` is group `staff`, GID 50; user `rektide`
  has UID/GID 1000 and belongs to staff.
  Workhorse also has UID/GID 1000 and staff GID 50 membership, so those basic
  numeric identities already align; NFS will not force CIFS-style ownership.
- Other Samba paths include `/usr/local/src`, homes, `/mnt/keepstar/exkay`,
  `/mnt/nanoshakes/torrent`, and the nested `/mnt/bitblaster/backup/kat` share.
  They are **not** automatically translated into NFS exports. In particular,
  nanoshakes is NTFS through `fuseblk`; export/filehandle support needs separate
  investigation rather than assuming the Btrfs result applies.
- Wired `eno1`: `192.168.0.235`, 1000 Mb/s, MTU 1500. Wi-Fi also has an address.
  Locally, **`nanomachine` resolves to Tailscale `100.84.242.34`**, not the wired
  LAN address. The prepared LAN client must use `srv=192.168.0.235`.
  Workhorse's `/etc/hosts` (2026-10-16) maps `nanomachine`, `nanomachine.local`,
  and **`nanomachine.lan`** to `192.168.0.235`, so `srv=nanomachine.lan` selects
  the wired LAN; the client's connection pool keys on the resolved address.
- Workhorse's current source address toward that LAN endpoint is `192.168.1.8`.
  Confirm it remains correct before activation. No whole-LAN wildcard is needed.
- NFS server/client executables and the NFS server unit were absent when inspected.

## Composition contract

One invocation per named instance is the pattern:

| Owner | Deployment / output |
| --- | --- |
| Export `INSTANCE=bitblaster` | `/srv/nfs-export-bitblaster/`, fragment `/etc/opt/nfs-export-bitblaster/nfs-export-bitblaster.exports` |
| Its future publication | `/etc/exports.d/nfs-export-bitblaster.exports` |
| Another export instance | Its own deployment and `.exports` file; no shared exports-file rewrite |
| Client mount | Own deployment; unit names derive from `where`, not the export's instance name |
| Host lifecycle | One distribution-owned `nfs-server.service`, shared intentionally |

Separate instances compose for **distinct client/path entries**. Installing one
adds/updates its own `exportfs -i -o ... CLIENT:PATH` entries; it does not run
`exportfs -ra`, unexport other entries, or restart/reload NFS. The installer
refreshes the systemd manager after fragment publication so the distro's
`nfs-server-generator` discovers backing-mount dependencies before service start.
That manager refresh does not restart the NFS service.

Boundaries, rather than claims of complete isolation:

- Different instance names declaring the **same client/path** conflict; one
  instance must own that pair. Different client mount instances targeting the
  **same local mountpoint** also conflict. No host-wide collision detector exists.
  Overlapping client selectors on the same path follow exports(5) precedence,
  not an independent per-fragment access policy.
- Avoid overlapping parent/child exports as independent security boundaries.
  Do not assign `fsid=0` per export or use `crossmnt` to expose children implicitly.
- Server startup/restart still processes the host's complete persistent exports.
  NFS worker counts, protocol configuration, and filesystem permissions are
  host/filesystem concerns, not independent per-export knobs.
- Clients may share transport connections and filesystem caches. Linux's first
  mount to an endpoint establishes the shared connection pool; later instances
  cannot be assumed to have independent connection counts (all client
  instances now default to `nconnect=3`, so inheritance stays consistent). Duplicate mounts of one export normally
  share caches and some effective options. Do not force `nosharecache` to fake
  isolation; that can introduce incoherent caches.
- AUTH_SYS uses numeric IDs, not Samba's `valid users`. The restricted `kat` share
  does not acquire equivalent user authentication merely by being nested under
  the bitblaster export. Root squashing is not protection against a trusted
  client administrator impersonating other nonzero UIDs.
- Samba leases/oplocks and NFS client caches are not a promise of cross-protocol
  coordination. Keep the trial isolated, and quiesce writers for the eventual
  mountpoint cutover rather than assuming concurrent SMB/NFS writes are harmless.

## Stage over SSH, without sudo

The ignored local profile `private/nfs/nanomachine-bitblaster.yaml` selects:

```yaml
INSTANCE: bitblaster
export_path: /mnt/bitblaster
clients: [127.0.0.1, 192.168.1.8]
export_opts: rw,sync,no_subtree_check,root_squash,mountpoint
```

`mountpoint` is deliberate: this data lives on a separate disk, not an arbitrary
directory to create on the OS filesystem. If a disk is genuinely absent, the
entry is skipped instead of exporting the empty directory on the OS filesystem;
when the disk is present but its systemd automount is idle, activation triggers
it automatically (see [Automount interaction](#automount-interaction)).

From the controller's Compfuzor checkout:

```sh
ansible-playbook -i 'nanomachine,' nfs-export.srv.pb \
  -e @examples/nfs/stage-no-sudo.yaml \
  -e @private/nfs/nanomachine-bitblaster.yaml
```

The [staging overrides](/examples/nfs/stage-no-sudo.yaml) use real YAML booleans
for `BECOME: false` and `ansible_become: false`, bypass package installation,
global bin links, bin execution, and systemd activation. They retain link plans
and installer generation. This also avoids the legacy auto-become filter's
controller-side permission guesses for SSH destinations.

Staging writes deployment/configuration artifacts only. It does **not** install
NFS packages, publish anything into `/etc/exports.d`, start NFS, change data
ownership, or touch Samba/fstab. It does not need a remote Compfuzor checkout:
the controller ships the runtime bundle into the deployment.

### Verified staged state

The SSH playbook run completed without sudo. The fragment, generated installers,
link manifest, runtime bundle, and this README are staged in the deployment.
`bash -n` accepted the export installer; Node 24 accepted the runtime bundle.
Read-only LINKS status reports the intended publication **MISSING**, as expected:
`/etc/exports.d/nfs-export-bitblaster.exports` does not exist. NFS remains
uninstalled/inactive, `samba-main.service` remains active, and the data mount's
ownership/mode remain unchanged. This is readiness verification, not a remote
NFS throughput or file-operation test.

For a later, deliberate privileged activation, inspect the staged fragment and
README, confirm the LAN client IP, and then use a terminal:

```sh
ssh -t nanomachine 'sudo bash /srv/nfs-export-bitblaster/bin/install.sh'
```

The other staged exports activate the same way (no disk pre-flight is needed —
see [Automount interaction](#automount-interaction)):

```sh
ssh -t nanomachine 'sudo bash /srv/nfs-export-src/bin/install.sh'
ssh -t nanomachine 'sudo bash /srv/nfs-export-exkay/bin/install.sh'
```

Run the installers **sequentially**: each runs its own apt lane, and concurrent
runs collide on the dpkg frontend lock (observed 2026-10-16; the loser fails
before publishing its units and is safe to rerun). After activation, check
`sudo exportfs -v` on nanomachine and `ls /mnt/nfs-bitblaster /mnt/nfs-src
/mnt/nfs-exkay` on workhorse, then `findmnt` for effective options.

The root-run aggregate installs the declared packages and publishes/activates
this export. This is **not** executed by the staging command. Disk ownership and
permissions are preserved. Confirm the generated mount dependencies and export
table afterwards; make the Samba cutover separately.

A safe first workstation mount would use a **new** path, not live CIFS's
`/mnt/bitblaster`. That plan is now realized below: all client mounts live
under `/mnt/nfs-*` and leave the CIFS mount untouched.

## Staged share set and client mounts — 2026-10-16

Server profiles live in `private/nfs/nanomachine-*.yaml` (SSH staging, no
sudo); client profiles in `private/nfs/workhorse-nanomachine-*.yaml`.

| Samba share | Server export (deployment) | Guard | Workhorse mount |
| --- | --- | --- | --- |
| bitblaster | `/mnt/bitblaster` (`nfs-export-bitblaster`) | `mountpoint` | `/mnt/nfs-bitblaster` |
| src | `/usr/local/src` (`nfs-export-src`) | none (OS-filesystem subdirectory) | `/mnt/nfs-src` |
| exkay | `/mnt/keepstar/exkay` (`nfs-export-exkay`) | `mountpoint=/mnt/keepstar` | `/mnt/nfs-exkay` |

- All three exports allow `127.0.0.1` and workhorse's LAN source `192.168.1.8`
  (recheck with `ip -4 route get 192.168.0.235` before activating). The exkay
  export is a subdirectory of keepstar, so the guard names the **backing**
  mount: if the disk is absent, the export disappears rather than exposing the
  empty mountpoint directory on the OS filesystem.
- All three client deployments are rendered with `srv=nanomachine.lan` and
  installed on workhorse: automounts `mnt-nfs\x2d{bitblaster,src,exkay}.automount`
  are enabled and active (2026-10-16), sharing one `nconnect=3` pool per the
  resolved `192.168.0.235` endpoint. Mounts complete once the server side is
  activated; trigger with `ls /mnt/nfs-bitblaster` etc.
- `src` and `exkay` server staging is verified (fragments + installers staged,
  nothing published), same as bitblaster earlier.

Not staged, deliberately:

- **nanoshakes** (`/mnt/nanoshakes`, NTFS via ntfs-3g `fuseblk`): the kernel
  NFS server cannot export FUSE filesystems — they implement no export
  operations, and `exportfs` refuses them ("does not support NFS exporting";
  verifiable with `sudo exportfs -i -o ro 127.0.0.1:/mnt/nanoshakes`, which
  fails without persisting anything). Keep this one on Samba or relocate the
  data to a btrfs/ext4 volume.
- **homes**: per-user home exports are a separate identity/autofs design
  decision, not a share-by-share mirror of Samba.
- **kat**: nested inside `/mnt/bitblaster`, so it is already reachable through
  the bitblaster export; a separate overlapping export would be an
  anti-pattern.

## Automount interaction

Nanomachine's data disks are fstab systemd automounts (`/mnt/bitblaster`,
`/mnt/keepstar`, 30-minute idle timeouts). Verified locally on 2026-10-16 with
an equivalent transient tmpfs automount + `mountpoint`-guarded export:

- **Activation triggers the automount itself.** `exportfs` stats the export
  path to validate it; that stat walks the direct autofs mount and systemd
  mounts the real filesystem. `exportfs -i` returned success with the backing
  fs mounted by the export operation alone — no manual pre-mount.
- **An export pins the backing mount.** With the entry in the kernel export
  table, the automount could not idle-expire the filesystem even with zero
  clients attached (idle timeout 20 s, still mounted after 25 s+ unattended),
  and fresh client mounts resolved normally afterwards. Unmounting an exported
  disk would fail busy by design.
- **Boot needs no manual steps either**: `nfs-server.service` runs
  `exportfs -r` at start, which performs the same validation-trigger across
  all published fragments.
- The `mountpoint` guard's real job is the failure case: if a disk is pulled
  or fails to mount, the entry is skipped rather than exporting the empty
  directory on the OS filesystem underneath.

Trade-off: idle-expiry is effectively disabled for exported disks — bitblaster
and keepstar stay mounted while their exports exist. That is normally
irrelevant, but if USB disk spindown matters, it belongs to hd-idle-style
tooling rather than automount unmounting.

## Performance choices

No throughput benchmark has been run against nanomachine's NFS service: it is not
active. Prioritize the known topology rather than copying a long option list.

1. **Use wired LAN deliberately.** The 1-Gb/s link has a theoretical 125-MB/s
   line-rate ceiling before protocol overhead; this is not a measured disk or
   NFS throughput result. The bare hostname currently selects Tailscale, whose
   routing/encryption behavior is a different benchmark. USB disk seeks and
   durable writes will matter especially for small-file workloads.
2. **Keep NFSv4.2/TCP, hard mounts, server sync, and normal locking/caching.**
   Avoid `soft`, server `async`, `noac`, `actimeo=0`, `nocto`, and local-only locking
   as blanket speed fixes. They either weaken correctness/coherence or can make
   performance substantially worse. Samba and local applications still write
   these files, so assuming a single immutable writer is inappropriate.
3. **Let transfer sizes negotiate.** Modern Linux can negotiate up to 1 MiB for
   `rsize` and `wsize`; inspect effective sizes with `nfsstat -m`/`findmnt`. Do not
   adopt Azure NetApp's appliance-specific 256-KiB recommendation for this host.
4. **Connection pooling is on by default (`nconnect=3`, 2026-10-16).** The
   client baseline pools three TCP connections per server endpoint; it cannot
   exceed the NIC/disk ceiling, so measure whether it helps or hurts before
   trusting it — a comparison client can render with
   `-e mount_opts=nconnect=1` or a higher count. Pools are shared per
   endpoint: the first mount to `192.168.0.235` fixes the pool for every
   mount to that address, so keep client instances to it configured alike;
   the shared default keeps them consistent. Verified on the loopback trial
   (three established connections, probe passing).
5. **Tune the server only on evidence.** Watch `nfsiostat`, `nfsstat`, `iostat -xz`,
   CPU/network use, and negotiated sizes under representative sequential and
   metadata-heavy workloads. Consider nfsd worker counts or read-ahead only if
   those observations show a bottleneck. Avoid generic sysctl/jumbo-frame changes.

The source filesystem already has `noatime`; no filesystem-wide atime change is
needed for this migration. Identity/group checks and successful permissions/lock
tests should precede performance work. Keep initial validation files isolated;
do not benchmark destructively on existing media, backups, or repositories.
