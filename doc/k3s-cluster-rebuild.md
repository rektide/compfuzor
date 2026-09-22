---
type: Runbook
title: k3s cluster rebuild procedures
description: Restore and rebuild procedures for single-server and HA embedded-etcd k3s - snapshot restore, total teardown/redeploy, HA member surgery, quorum loss, and fresh-hardware DR.
tags: [k3s, etcd, disaster-recovery, runbook]
status: stable
generated: { by: agent:opencode-calm-squid, at: 2026-09-22 }
sources:
  - id: k3s-etcd-snapshot
    resource: https://docs.k3s.io/cli/etcd-snapshot
    title: k3s CLI reference - etcd-snapshot (single & multiple server restore steps, snapshot security)
  - id: k3s-ha-embedded
    resource: https://docs.k3s.io/datastore/ha-embedded
    title: k3s HA embedded etcd
  - id: k3s-roll-back
    resource: https://docs.k3s.io/upgrades/roll-back
    title: k3s roll-back (restore procedure, server: entry requirement)
  - id: k3s-uninstall
    resource: https://github.com/k3s-io/k3s/blob/release-1.36/install.sh
    title: k3s-uninstall.sh / k3s-killall.sh behavior (install.sh source)
  - id: k3s-node-password
    resource: https://docs.k3s.io/architecture#how-agent-node-registration-works
    title: node registration and node-password secrets
---

# k3s cluster rebuild procedures

Companion to [`k3s-drift-recovery.md`](/doc/k3s-drift-recovery.md) (that one
covers *data intact, registration stale* - the IP-drift case). This one
covers *data damaged, lost, or needing surgery*: snapshot restores, total
teardown/redeploys, HA member replacement, quorum loss, and fresh-hardware
disaster recovery. All claims verified against docs.k3s.io and k3s
release-1.36 source unless marked **(inferred)**; the full research log is
`.test-agent/k3s-research/findings.md` (gitignored scratch).

## The model that makes the procedures obvious

- **Restore has exactly one trigger**: `k3s server --cluster-reset
  --cluster-reset-restore-path=<path>`. There is **no auto-restore**: with an
  empty db, a plain start (`--cluster-init`) creates a *fresh* cluster and
  silently ignores snapshots on disk. `drift-guard.sh` blocks that
  combination and points here.
- **A snapshot is self-contained for identity**: it carries the datastore
  plus all CA certs/keys and the secrets-encryption config, PBKDF2-encrypted
  with a key **derived from the server token**. Restore to any host
  therefore requires the original cluster token or the snapshot is unusable.
  `ETCD_SNAPSHOT_SINK_CREDS=true` mirrors token/agentToken/encryption-config
  into `<sink>/creds/` for exactly this.
- **Cluster membership is mutable state**: joining servers add themselves as
  learners automatically (`MemberAddAsLearner`, never manual `member add`),
  but k3s does **not** self-heal a stale peer URL. `join()` refuses a
  duplicate node name, so a stale member must be removed before the changed
  node can rejoin.
- **Node registration** uses the token plus `/etc/rancher/node/password`
  (hash stored in a `<node>.node-password.k3s` Secret, which dies with its
  Node object).

## Scenario matrix

| # | situation | procedure |
|---|---|---|
| S1 | single-server: db bad, want snapshots back | [restore.sh](#s1-single-server-restore-from-snapshot) |
| S2 | single-server: total rebuild, same host | [teardown + redeploy + optional restore](#s2-single-server-total-rebuild-same-host) |
| S3 | dead hardware: rebuild elsewhere from the off-box sink | [fresh-hardware DR](#s3-fresh-hardware-disaster-recovery) |
| S4 | HA: one server's IP changed / peer URL stale | [member remove + rejoin](#s4-ha-server-ip-changed--stale-peer-url) |
| S5 | HA: one server lost/rebuilt | [member remove + wipe db + rejoin](#s5-ha-server-rebuiltreplaced) |
| S6 | HA: quorum lost / cluster-wide restore | [stop all, restore on one, peers wipe db](#s6-ha-quorum-loss--full-restore) |
| A | agents after any of the above | [agent rejoin](#agents-after-a-rebuild) |

Multi-server vs single-server is visible in `status.sh` ("topology:"), and
`K3S_MULTISERVER=1` in the unit env is what makes `drift-guard.sh` refuse to
auto-reset.

## S1: single-server restore from snapshot

The db is untrustworthy (corruption, bad write, accidental deletion of
objects) but snapshots exist on disk or in the sink.

```sh
cd /srv/k3s-server-<instance>/bin
./etcd.sh list                 # inventory (name, size, timestamp)
sudo ./etcd.sh status latest   # hash / revision / key count of the newest
sudo ./restore.sh              # lists snapshots, prompts for one
# ... or non-interactive, from anywhere (absolute paths work):
sudo ./restore.sh /mnt/bitblaster/backup/kube-workhorse/etcd-snapshot-<name>-<ts>.zip --yes
sudo systemctl start <NAME>
```

Semantics: `--cluster-reset` is required; the current db is **moved aside**
to `db/etcd-old-<ts>/` (nothing deleted); `.zip` snapshots are handled
transparently; the cluster token must match the snapshot's. `restore.sh`
also performs the cred-file stash (files newer than the datastore make k3s
refuse to start; it recreates them - encryption files are never moved).
After the restore, one normal start clears `db/reset-flag`.

Roll your own point-in-time? `etcd.sh save <name>` first.

## S2: single-server total rebuild (same host)

Teardown via [`k3s-clean.pb`](/k3s-clean.pb), then redeploy. The ordering
rule that matters: **redeploy without starting k3s, restore, then start** -
a fresh start with `--cluster-init` over leftover snapshots creates an empty
cluster (and the drift guard will refuse it anyway).

Decide the identity question first:

- **keep cluster identity** (recommended unless starting over): do NOT wipe
  `/etc/opt/<NAME>` - the token there is what makes old snapshots
  restorable.
- **scorched earth**: `force_clean=True` wipes etc too; old snapshots become
  unrestorable (wrong token); this is a brand-new cluster.

```sh
# teardown (keeps /etc/opt/<NAME> unless force_clean=True)
ansible-playbook -i 'localhost,' -c local k3s-clean.pb -e server=<instance-domain>

# redeploy WITHOUT starting k3s (the systemd thunk is what starts units)
ansible-playbook -i 'localhost,' -c local k3s.srv.pb ... \
  -e SYSTEMD_THUNK_BYPASS=True -e BINS_RUN_BYPASS=True

# either restore the latest snapshot...
sudo /srv/k3s-server-<instance>/bin/restore.sh latest --yes
# ...or confirm a deliberate fresh start:
sudo SYSTEMD_THUNK_BYPASS= systemctl start <NAME>   # guard blocks; use override if fresh is truly wanted:
#   edit env: K3S_ALLOW_FRESH_OVER_SNAPSHOTS=1 (or move snapshots aside)

# then re-enable the thunk lanes on the next normal playbook run
```

`k3s-clean.pb` removes the data dir + unit + `/etc/rancher` links *and* the
system state a naive delete misses: `/var/lib/kubelet`, `/var/lib/cni`,
`/run/{k3s,flannel}` (umounting runtime mounts first), `cni*`/`flannel*`
links, and `KUBE-`/`CNI-`/`flannel` iptables. It leaves the k3s binary and
`/etc/rancher/node` (node password; delete by hand if it exists and you want
a clean node registration).

## S3: fresh-hardware disaster recovery

Needs: one snapshot zip + the **original cluster token** (both live in the
off-box sink if `ETCD_SNAPSHOT_SINK_CREDS=true`). Without the token, the
snapshot is cryptographically unusable - this is the step people forget.

1. Pre-seed the token **before** the first k3s start, so compfuzor's
   password generation sees it and keeps it:

   ```sh
   sudo mkdir -p /etc/opt/k3s-server-<instance>/secrets
   sudo cp <sink>/creds/token        /etc/opt/k3s-server-<instance>/secrets/token
   sudo cp <sink>/creds/agentToken   /etc/opt/k3s-server-<instance>/secrets/agentToken  # if agents will rejoin
   ```

2. Deploy the static node-IP pin first if using one
   ([`systemd-iface-extra-addr.etc.pb`](/systemd-iface-extra-addr.etc.pb))
   - restore re-registers the etcd member at `--node-ip`, so have the pin in
   place before the first start.
3. Deploy `k3s.srv.pb` with `SYSTEMD_THUNK_BYPASS=True
   BINS_RUN_BYPASS=True` (do not start yet).
4. `sudo ./restore.sh <sink>/etcd-snapshot-<name>-<ts>.zip --yes`
5. Start the unit. Identity is preserved **(inferred from the bootstrap
   inventory: same CA + service-account signing key, so existing kubelet
   certs and SA tokens stay valid)**.
6. Clean up stale Node objects for hardware that no longer exists:
   `kubectl get nodes` / `kubectl delete node <gone>` - dead nodes block
   nothing, but node-password Secrets conflict if a *new* machine reuses a
   name (see [agents](#agents-after-a-rebuild)).
7. Workloads with node-affinity to the dead node need rescheduling;
   local-path PVs on the dead host need manual attention (the provisioner's
   data was on that disk).

## S4: HA: server IP changed / stale peer URL

Symptom: the changed server crash-loops with "this server is a not a member
of the etcd cluster. Found [...=https://OLD:2380]". k3s will not fix this by
itself, and `drift-guard.sh` deliberately refuses to auto-reset on
multi-server.

On a **healthy peer** (one whose k3s is running):

```sh
./etcd.sh members                      # note the stale member's hex ID
./etcd.sh remove-member <hex-id>       # or: kubectl delete node <changed-node>
                                       # (the member controller removes the peer)
```

Then restart the changed server; it rejoins as a learner at its new IP via
its `--server` join config. With static NODE_IP pins per server this
scenario should not arise at all.

## S5: HA: server rebuilt/replaced

Same as S4, plus wiping that node's stale db so it joins instead of
resurrecting:

```sh
# on a healthy peer:
./etcd.sh members && ./etcd.sh remove-member <hex-id>
# on the rebuilt node:
sudo systemctl stop <NAME>
sudo rm -rf <DATA>/server/db            # db only - keep cred/ and tls/
sudo systemctl start <NAME>             # rejoins via its --server config
```

## S6: HA: quorum loss / full restore

Majority of etcd members permanently gone, or cluster-wide restore wanted.
Recovery = restore on one server, peers rejoin; data after the last
snapshot is lost.

1. Stop k3s on **all** servers.
2. On the restore server (S1): `sudo ./restore.sh <snapshot> --yes`.
   k3s itself prints the peer instructions during the restore.
3. Start S1.
4. On every other server: `sudo rm -rf <DATA>/server/db` **only** (db/,
   not `cred/`, not `tls/`), then start. They rejoin via their `server:`
   join config - a peer with neither a db nor a `--server`/`server:` entry
   would bootstrap a brand-new empty cluster instead **(requirement implied
   by the roll-back doc + code; not stated explicitly in docs)**. Keep the
   inventory's `K3S_BOOTSTRAP` pointing at the restore server until
   everyone's back.

Restore removes all etcd members except the restorer; the peers re-add
themselves as learners.

## Agents after a rebuild

- **Server restored, token unchanged**: agents reconnect on their own -
  their Node objects and node-password Secrets came back inside the
  snapshot. Nothing to do.
- **Node-password conflict** (new machine reusing a name, or restored
  Secret vs fresh `/etc/rancher/node/password`): `kubectl delete node
  <name>` or remove `/etc/rancher/node` on the agent, then restart it.
- **Fresh cluster / new token**: agents fail auth and must be redeployed
  (their old token no longer decrypts/authenticates anything) **(inferred)**.
- Agents hold kubelet state under their own data dir; a confused agent can
  be cleaned with `k3s-clean.pb` (agent instance) and redeployed.

## Failure-mode quick reference

| symptom | meaning | tool |
|---|---|---|
| `not a member of the etcd cluster` | stale peer URL | single: `reset.sh`; HA: S4 |
| guard blocks: fresh cluster over snapshots | no db + snapshots + plain start | `restore.sh`, or override deliberately |
| guard blocks: NODE_IP not assigned | static pin missing | fix the networkd drop-in |
| `newer than datastore and could cause a cluster outage` | cred mtimes post-reset | `reset.sh`/`restore.sh` stash automatically; by hand move `server/cred/*` aside, never the encryption files |
| `cluster token does not match` on restore | foreign token | seed the original token (S3 step 1) |
| apiserver cert SAN wrong | tls-san set wrong at deploy | redeploy with `TLS_SANS` (cert auto-regenerates) |
| agent `node password ... requires delete` | password secret conflict | delete Node or `/etc/rancher/node` |

## Cross-references

- [`k3s-drift-recovery.md`](/doc/k3s-drift-recovery.md) - IP-drift failure
  mode, the bin/ toolkit overview, and the static-pin prevention design.
- [`k3s.srv.pb`](/k3s.srv.pb), [`k3s-clean.pb`](/k3s-clean.pb),
  [`systemd-iface-extra-addr.etc.pb`](/systemd-iface-extra-addr.etc.pb) -
  the playbooks these procedures drive.
