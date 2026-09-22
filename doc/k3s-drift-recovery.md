---
type: Runbook
title: k3s embedded-etcd IP-drift recovery & prevention
description: Why DHCP node-IP drift breaks single-server k3s etcd, the tools that recover it, and the static-pin + drift-guard deployment that prevents it.
tags: [k3s, etcd, systemd-networkd, recovery]
status: stable
generated: { by: agent:opencode-calm-squid, at: 2026-09-22 }
sources:
  - id: k3s-docs
    resource: https://docs.k3s.io/cli/etcd-snapshot
    title: k3s CLI reference -- etcd-snapshot / backup-restore / ha-embedded
  - id: k3s-release-136
    resource: https://github.com/k3s-io/k3s/tree/release-1.36
    title: k3s release-1.36 source (etcd.go, bootstrap.go, server.go)
---

# k3s embedded-etcd IP-drift recovery & prevention

## The failure mode

A single-server k3s cluster with embedded etcd registers its etcd **member
peer URL** (`https://<node-ip>:2380`) at the IP current when the cluster was
initialized — k3s derives it from the first `--node-ip`, or autodetects via
the default route when unset. On a DHCP host, a new lease leaves the
registered peer URL pointing at the old IP, and every start fails:

```
Failed to test etcd connection: this server is a not a member of the etcd
cluster. Found [<id>=https://OLD_IP:2380], expect: [<id>=https://NEW_IP:2380]
```

The **data is fine**; only the registration is stale. Observed on
`workhorse.voodoowarez.com` across leases `.173` (Jan) → `.177` (Jun) →
`.172` (Sep). A related trap: aggregating `ansible_all_ipv4_addresses` into
`--tls-san` at deploy time freezes the deploy-day lease into the unit
(`k3s-inv`'s `extraIpv4Domains` did this). `k3s.srv.pb` now builds
`TLS_SANS` from explicit names + the `NODE_IP` pin only.

Facts verified against k3s release-1.36 source and docs (full research log:
`.test-agent/k3s-research/findings.md`):

- `--cluster-reset` alone preserves data: etcd `--force-new-cluster` over
  the existing db, and k3s re-points the member peer URL to `--node-ip`.
- **`--cluster-reset-keep-control-plane-members` does not exist** in any
  k3s release — the June 2026 `launch.sh`/`recover.sh` on the deployed box
  were built around a phantom flag and would have failed if invoked.
- After a reset, `server/cred/passwd` (and sometimes other cred files) can
  be newer than bootstrap data and make k3s refuse to start; move `passwd`
  and any other named/newer offenders aside (k3s recreates them from
  the datastore) but **never** `encryption-config.json` /
  `encryption-state.json` —
  without that key every encrypted secret is permanently unreadable.
- `--cluster-init` on every start is a documented no-op once a datastore
  exists.
- Restores require `--cluster-reset` +
  `--cluster-reset-restore-path=<abs path>`; the current db is moved to
  `db/etcd-old-<ts>/`, `.zip` snapshots are handled transparently, and the
  cluster token must match the snapshot's.
- kubeconfig (`k3s.yaml`) points at `https://127.0.0.1:6443` — local API
  access never breaks from IP drift.

## The toolkit (`files/k3s-server/`, deployed to `<DIR>/bin/`)

All scripts discover their instance via `bin/lib.sh` → `<DIR>/env`, so they
work for any `k3s.srv.pb` instance. Safe by hand (sudo as needed) or from
root units.

| script | role |
|---|---|
| `status.sh` | read-only report: service, topology, node IP + pin, drift baseline, listeners, live etcd member list, snapshots, sink freshness |
| `drift-guard.sh` | `ExecStartPre` in the generated unit: auto cluster-reset on drift (single-server only — multi-server blocks with a runbook pointer), static-pin verification, and refusal to start a fresh cluster over existing snapshots |
| `reset.sh` | manual cluster-reset to a target IP (`reset.sh --yes 192.168.1.8`); refuses multi-server |
| `restore.sh` | snapshot restore (`restore.sh latest`); lists snapshots when run bare; refuses multi-server (HA restore is a different procedure) |
| `etcd.sh` | `list` / `status <snap>` (offline) / `members` / `health` (live) / `save` / `remove-member <id>` (HA stale-peer remedy) |
| `snapshot-sync.sh` | no-clobber copy of snapshot zips to the sink, pruned to newest `ETCD_SNAPSHOT_SINK_KEEP`; optional DR-credential mirror |

Snapshots: 12h cadence (`0 */12 * * *`), `--etcd-snapshot-compress`
(~2.7 MB zips), retention 28. With `ETCD_SNAPSHOT_SINK` set (e.g. the
autofs CIFS mount `/mnt/bitblaster/backup/kube-workhorse`), the playbook
generates an hourly `<NAME>-snapshot-sync.service` + `.timer` pair.

## Recovery (single-server)

```sh
cd /srv/k3s-server-<instance>/bin
./status.sh                      # what does etcd think? where are snapshots?
sudo ./etcd.sh list              # snapshot inventory
sudo ./etcd.sh status latest     # hash/revision/keys of the newest
sudo ./reset.sh                  # re-point member peer URL to current IP
sudo systemctl start <NAME>      # guard runs first, then k3s
```

Restore instead of reset when the db itself is bad:

```sh
sudo ./restore.sh                # pick a snapshot; old db kept in etcd-old-*/
```

Multi-server peer drift is a runbook, not a script: `etcdctl member remove`
the stale member from a healthy peer, then restart the node to rejoin.
`reset.sh`/`restore.sh` refuse on multi-member clusters.

## Prevention: static secondary IP + NODE_IP pin

The long-term fix is to stop deriving the kube node IP from DHCP at all,
without touching the host's DHCP mobility:

1. **Static secondary address** —
   [`systemd-iface-extra-addr.etc.pb`](/systemd-iface-extra-addr.etc.pb)
   drops `[Network] Address=<ip>/22` into
   `/etc/systemd/network/en.network.d/`; DHCP keeps owning the default
   route. Pick an address **outside the DHCP pool** (or reserve it
   router-side).
2. **Pin k3s** — deploy `k3s.srv.pb` with `-e NODE_IP=<static-ip>`: the
   unit gains `--node-ip`, `TLS_SANS` includes it, and `drift-guard.sh`
   verifies it is assigned before every start (blocking loudly if the
   drop-in vanished).
3. **One-time re-registration** — `sudo ./reset.sh --yes <static-ip>`
   re-points the etcd member peer URL at the pin; drift then cannot recur.

Tailscale addresses (e.g. `100.76.116.2`) belong in `TLS_SANS` for remote
API access; making one the node-ip would chain kube availability to
tailscaled, so the LAN pin is preferred.

### Inventory-driven deployment

Keep host policy under its cluster group in `~/.ansible/k3s` and deploy with
the established limit rather than reconstructing extra-vars:

```yaml
workhorse:
  vars:
    k3s_node_ip: 192.168.1.8
    NODE_IP_CIDR: 192.168.1.8/22
    extraSans: [100.76.116.2]
    k3s_cluster_cidr: 10.39.0.0/16
    k3s_service_cidr: 10.40.0.0/16
    k3s_cluster_dns: 10.40.0.2
    k3s_kubelet_args:
      - eviction-hard=nodefs.available<25Gi,imagefs.available<30Gi
      - image-gc-high-threshold=98
      - image-gc-low-threshold=97
    k3s_etcd_snapshot_sink: /mnt/bitblaster/backup/kube-workhorse
    k3s_etcd_snapshot_sink_keep: 120
    k3s_etcd_snapshot_sink_creds: "true"
```

```sh
ansible-playbook -i ~/.ansible/k3s -c local \
  systemd-iface-extra-addr.etc.pb --limit workhorse
ansible-playbook -i ~/.ansible/k3s -c local \
  k3s.srv.pb --limit workhorse
```

The root and container image filesystems on workhorse are the same 3.4 TiB
btrfs filesystem. Percentage defaults caused permanent DiskPressure at 149
GiB free (`5%` still means roughly 170 GiB) and futile image GC attempts at
85%/80%. Absolute 25/30 GiB eviction plus 98%/97% image GC keeps meaningful
safety margins without demanding hundreds of GiB of unrelated host storage.

## Cross-references

- [`k3s-cluster-rebuild.md`](/doc/k3s-cluster-rebuild.md) — companion
  runbook for when data (not just the registration) is the problem: snapshot
  restores, total teardown/redeploy, HA member surgery, quorum loss, and
  fresh-hardware DR.
- [`k3s.srv.pb`](/k3s.srv.pb) — the playbook wiring (drift-guard
  ExecStartPre, `TLS_SANS`, `ETCD_SNAPSHOT_SINK` units).
- [`watcher-ops.md`](/doc/watcher-ops.md) — sibling ops-runbook style and
  drift-report conventions.
- `.test-agent/k3s-research/findings.md` — verified-source research log
  behind the claims above (gitignored scratch; regenerate if absent).
