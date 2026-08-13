---
type: Design
title: OpenCode network service and discovery handoff
description: Findings, options, and intent for running OpenCode V2 under systemd and connecting local or LAN clients through explicit URLs or DNS-SD.
resource: /.design/opencode/service.md
tags: [opencode, systemd, mdns, dns-sd, networking, compfuzor]
status: draft
generated: { by: "agent:opencode:gpt-5.6-sol", at: 2026-08-13T00:00:00Z }
stale_after: 2026-11-13
sources:
  - id: opencode-v2-source
    resource: https://github.com/anomalyco/opencode/tree/dev/packages
    title: OpenCode V2 CLI, client, and server packages
    author: org:anomalyco
  - id: dns-sd
    resource: https://www.rfc-editor.org/rfc/rfc6763
    title: DNS-Based Service Discovery
    author: S. Cheshire and M. Krochmal
  - id: compfuzor
    resource: https://github.com/rektide/compfuzor
    title: Compfuzor source and service configuration
    author: rektide
---

# OpenCode network service and discovery handoff

## Purpose

We want OpenCode V2 to run as a durable systemd-managed service to which TUI,
CLI, desktop, and SDK clients can connect. The desired operating modes are:

- **LAN by default:** listen on all network interfaces and be discoverable on
  the local link.
- **Local-only option:** listen only on loopback and remain usable through the
  existing local service-discovery path.
- **Explicit connection:** permit a client to select a URL directly regardless
  of automatic discovery.
- **mDNS/DNS-SD discovery:** advertise enough public metadata to locate and
  assess a server, but never advertise its credential.

This document hands off repository findings and explores implementation choices.
It is not an accepted security or protocol specification. In particular,
"all interfaces by default" is recorded user intent, not an assertion that the
current password-over-HTTP transport is safe on every network.

## Executive direction

The smallest coherent first deployment is:

1. Run `opencode2 serve --service --hostname 0.0.0.0 --port 49374` as a
   **systemd user service**.
2. Retain OpenCode's generated persistent Basic Auth password.
3. Publish `_opencode._tcp.local.` using a systemd `.dnssd` file on Linux.
4. Keep the existing private registration file as the authoritative local
   connection record.
5. Use `opencode2 --server http://host.local:49374` plus an enrolled password
   for remote clients until native DNS-SD browsing and credential storage exist.
6. Offer loopback mode by changing the bind address to `127.0.0.1`; do not
   publish DNS-SD in that mode.

This deployment can be produced by Compfuzor before OpenCode gains native
systemd installation or DNS-SD browsing. It does not by itself solve remote
credential enrollment, transport confidentiality, service selection when more
than one server is found, or lifecycle conflict between systemd and OpenCode's
client-triggered process spawning.

## Confirmed OpenCode V2 behavior

The findings below came from the V2 package set in the OpenCode `dev` checkout,
not from `packages/opencode`, which is the V1 implementation.

### Server process

[`packages/cli/src/commands/commands.ts`](https://github.com/anomalyco/opencode/blob/dev/packages/cli/src/commands/commands.ts)
defines:

```text
opencode2 serve [--hostname HOST] [--port PORT] [--service | --stdio]
```

[`packages/cli/src/server-process.ts`](https://github.com/anomalyco/opencode/blob/dev/packages/cli/src/server-process.ts)
implements the process:

- `--service` changes to the user's home directory before startup.
- The current managed-service bind default is `127.0.0.1`, not all interfaces.
- The current stable-channel default port is hexadecimal `0xc0de`, decimal
  `49374`; other channels can choose different deterministic ports.
- Managed-service mode generates and persists a random 32-byte base64url
  password if one is not already configured.
- The server writes a private registration containing instance ID, version,
  URL, PID, and password with mode `0600`.
- The process remains alive until server shutdown.
- A configured wildcard bind is already translated into concrete interface
  URLs by the server and exposed through the server-info API.

The server therefore already has the process shape systemd needs. It should be
executed directly in the foreground; there is no need for `Type=forking`, a
shell wrapper, or systemd process guessing.

### Local discovery and automatic startup

[`packages/client/src/effect/service.ts`](https://github.com/anomalyco/opencode/blob/dev/packages/client/src/effect/service.ts)
documents and implements the current discovery contract:

- Local discovery reads one registration file from the user's XDG state
  directory and authenticates a health probe.
- `Service.ensure` starts a detached `opencode2 serve --service` contender when
  no healthy compatible registration is found.
- Version matching and replacement policy are part of client connection
  resolution.
- `Service.stop` first asks the exact authenticated server instance to stop,
  then can escalate through process signals.

This is local file discovery, not network discovery. A remote client cannot
read the host's registration file, and that file intentionally contains the
password, so it must never be served or mirrored through mDNS.

### Explicit remote connection

[`packages/cli/src/services/server-connection.ts`](https://github.com/anomalyco/opencode/blob/dev/packages/cli/src/services/server-connection.ts)
supports `--server URL`. When selected, it:

- Does not launch or replace a managed service.
- Reads the password from `OPENCODE_PASSWORD` or the supported server password
  environment source.
- Sends Basic Auth with username `opencode`.
- Probes `/api/health` and warns, but continues, on version mismatch.

Thus explicit remote operation exists today. Discovery and durable remote
credential storage are the missing client-facing pieces.

### Pairing output

[`packages/cli/src/commands/handlers/pair.ts`](https://github.com/anomalyco/opencode/blob/dev/packages/cli/src/commands/handlers/pair.ts)
already obtains concrete interface URLs, displays the username and password,
and emits the connection information as a QR code. This is useful enrollment
material, but it currently reveals a shared long-lived server password. It is
not yet a one-time pairing protocol.

### Existing service configuration

The managed service accepts persisted `hostname`, `port`, and `password` keys:

```sh
opencode2 service set hostname 0.0.0.0
opencode2 service set port 49374
opencode2 service get password
```

Changing one of these values stops the current service. The ordinary managed
default remains loopback unless OpenCode code or configuration changes it.

## Confirmed Compfuzor behavior

[`/opencode.src.pb`](/opencode.src.pb) presently builds and configures the V1
OpenCode package path. Its `etc_d/mdns.json` contains the V1
`server.mdns: true` setting. That setting is useful historical intent but is
not evidence of V2 support and should not be copied into a V2 design.

Compfuzor already has generic systemd unit generation:

- [`/tasks/compfuzor/vars_systemd_unit.tasks`](/tasks/compfuzor/vars_systemd_unit.tasks)
  detects service and DNS-SD declarations and emits unit files.
- [`/files/systemd.unit`](/files/systemd.unit) renders free-form sections.
- [`/vars/systemd.yaml`](/vars/systemd.yaml) defines `.dnssd` as a supported
  unit type with a `[Service]` section.
- [`/systemd-mdns.etc.pb`](/systemd-mdns.etc.pb) enables mDNS globally in
  `systemd-resolved`.
- [`/systemd-resolved-multicast.etc.pb`](/systemd-resolved-multicast.etc.pb)
  also supports enabling multicast DNS on selected `systemd-networkd` links.

This makes systemd-native publication a lower-complexity Compfuzor option than
adding a Bonjour library to the OpenCode server. A `.dnssd` publisher is
system-scoped configuration even when the OpenCode process itself is a user
service, so installing it may require privilege. Other platforms still need a
native advertiser or an external implementation such as Avahi.

## Why a user service

A user service is the appropriate default because OpenCode owns and observes
user-scoped resources:

- `~/.config/opencode` configuration and provider credentials;
- XDG state and data, including the database and registration file;
- the user's projects, repositories, tools, shell environment, and SSH access;
- permission decisions and plugins intended for that user.

A system service would require an explicit service account and a deliberate
model for which user's home, projects, and credentials it may access. Running a
system service as an arbitrary login user is possible but is a less clear
ownership model than `systemctl --user`.

For a user service that should survive logout and start at boot, enable linger:

```sh
loginctl enable-linger "$USER"
```

That is an operational choice: lingering allows the user's services to run
without an active login session.

## Baseline systemd shape

The following is a design sketch, not yet a generated Compfuzor artifact:

```ini
[Unit]
Description=OpenCode V2 service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/bin/opencode2 serve --service --hostname 0.0.0.0 --port 49374
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
```

Properties worth preserving in the final generated unit:

- `ExecStart` uses an absolute, stable executable path.
- No password is placed in the unit or process arguments. OpenCode loads its
  persisted private service configuration.
- `Restart=on-failure` avoids immediately undoing a deliberate graceful stop.
- The port is fixed when DNS-SD is generated statically. Dynamic port `0` is
  incompatible with a static `.dnssd` record unless publication is updated
  after binding.
- The default working directory is the user's home, matching existing
  `serve --service` behavior.

The local-only variant changes only the bind address and disables publication:

```ini
ExecStart=%h/.local/bin/opencode2 serve --service --hostname 127.0.0.1 --port 49374
```

An IPv6-capable all-interface deployment should separately evaluate `::` and
dual-stack socket behavior. `0.0.0.0` is specifically IPv4 wildcard binding.

## DNS-SD profile proposal

[RFC 6763](https://www.rfc-editor.org/rfc/rfc6763) defines discovery as PTR
enumeration followed by SRV/TXT resolution. The SRV record supplies host and
port; TXT should remain small and contain only non-secret selection metadata.

Proposed service type:

```text
_opencode._tcp.local.
```

Proposed initial TXT profile:

| Key | Example | Purpose |
|---|---|---|
| `txtvers` | `1` | DNS-SD profile version; RFC 6763 recommends this convention. |
| `api` | `2` | OpenCode API generation, distinct from package version. |
| `version` | `1.18.4` | Informational server version for filtering or warnings. |
| `auth` | `basic` | Indicates that enrollment/authentication is required. |
| `tls` | `0` | Explicit transport capability until HTTPS is available. |
| `id` | stable server ID | Lets clients recognize a previously paired server across address changes. |

Do not publish:

- password, token, Authorization header, or password-derived verifier;
- user name, project paths, provider names, session IDs, or model credentials;
- raw registration-file contents;
- interface addresses or port duplicated in TXT, because SRV/A/AAAA already
  carry addressing information.

The DNS-SD instance name should be user-friendly and configurable, for example
`OpenCode on workstation`. A stable opaque `id` belongs in TXT for identity;
the display label should not be forced to encode uniqueness. The exact service
type should be checked for registration and collision before it is treated as
public protocol.

Illustrative systemd publisher:

```ini
[Service]
Name=OpenCode on %H
Type=_opencode._tcp
Port=49374
TxtText=txtvers=1
TxtText=api=2
TxtText=auth=basic
TxtText=tls=0
```

Whether `%H` and other specifiers are accepted in each `.dnssd` field must be
verified against the systemd version deployed by Compfuzor. A generated literal
name is an adequate fallback.

## Discovery is not pairing

mDNS answers only: "Which OpenCode services are visible on this link, and where
are they?" It must not answer: "Who is authorized to use them?"

A complete remote client flow has separate stages:

```mermaid
flowchart LR
  browse[Browse DNS-SD] --> select[Select server]
  select --> probe[Unauthenticated identity or health probe]
  probe --> trust[Confirm server identity]
  trust --> enroll[Enroll credential]
  enroll --> store[Store credential locally]
  store --> connect[Authenticated API connection]
```

Today the explicit approximation is:

1. Run `opencode2 pair` on the server host.
2. Transfer or scan the generated URL and shared password through a trusted
   physical or side channel.
3. Set `OPENCODE_PASSWORD` when invoking a remote client with `--server`.

The stronger future flow would issue a one-time, short-lived pairing code and
mint a distinct revocable client credential. That permits per-device revocation
and avoids copying the server's administrative shared secret. It is a separate
authentication/API feature and should not be smuggled into the DNS-SD design.

## Architecture options

### Option A: Compfuzor-managed systemd service and `.dnssd`

Compfuzor generates both units. OpenCode remains unaware of mDNS.

**Strengths**

- Smallest Linux implementation using facilities already represented in this
  repository.
- Advertising lifetime follows system configuration rather than an extra JS
  dependency.
- No V2 Protocol or Server `HttpApi` change is required for initial deployment.
- Service configuration remains inspectable with ordinary systemd tools.

**Weaknesses**

- Linux/systemd-specific and `.dnssd` installation is generally system-scoped.
- A static publisher can advertise while the user service is down unless their
  lifecycle is coupled.
- A static port is required.
- OpenCode clients still need native DNS-SD browsing or an external resolver.

**Fit:** recommended first Compfuzor deployment and interoperability prototype.

### Option B: OpenCode advertises and browses DNS-SD natively

The server publishes after binding; clients browse as another connection
source.

**Strengths**

- Cross-platform behavior can be made consistent.
- Publication exactly follows server lifetime and actual dynamically assigned
  port.
- Native UI can continuously present discovered servers.
- Protocol metadata and compatibility filtering live near their consumers.

**Weaknesses**

- Adds platform integration or a runtime dependency to startup-sensitive code.
- Multihomed hosts, VPNs, interface changes, duplicate instance names, and sleep
  behavior broaden scope substantially.
- Discovery policy must be reconciled with local auto-start, explicit `--server`,
  and multiple discovered candidates.

**Fit:** likely long-term product behavior after the profile and selection UX
are established externally.

### Option C: Avahi or another sidecar publisher/browser

Use Avahi service files or `avahi-publish-service`; clients use a system DNS-SD
API or command wrapper.

**Strengths**

- Mature Linux mDNS implementation and broader distro coverage where
  `systemd-resolved` is not authoritative.
- Keeps OpenCode runtime unchanged.

**Weaknesses**

- Adds another daemon and Compfuzor branch.
- Client integration remains external.
- Static publication has the same health/lifecycle concern as `.dnssd`.

**Fit:** compatibility backend, not the first path on systemd-resolved hosts.

### Option D: Explicit URL only

Deploy systemd but defer mDNS. Operators configure `--server` and credentials.

**Strengths**

- Works with current V2 behavior.
- Deterministic, scriptable, and usable across routed networks where mDNS does
  not cross subnets.
- Avoids ambiguous multi-server selection.

**Weaknesses**

- No zero-configuration discovery.
- Host naming and credential distribution remain manual.

**Fit:** fallback that should remain supported even after discovery ships.

### Option E: systemd socket activation

Let systemd own the listening socket and start OpenCode on demand.

**Strengths**

- Strong lifecycle ownership and immediate stable port availability.
- Potential idle shutdown and activation behavior.

**Weaknesses**

- The current server process expects to bind its own socket; no socket-activation
  handoff was found.
- Streaming requests and long-running session execution make idle semantics
  non-trivial.
- This is not a minimal deployment change.

**Fit:** future investigation only; do not assume current support.

## Lifecycle ownership problem

Systemd and `Service.ensure` can both act as supervisors. Without an explicit
policy, the following sequence escapes systemd ownership:

1. systemd starts `opencode2 serve --service`;
2. `opencode2 service stop` gracefully stops it;
3. `Restart=on-failure` correctly leaves it stopped;
4. a later ordinary client sees no registration and launches a detached server
   itself.

Conversely, aggressive `Restart=always` can race a client that is deliberately
stopping or replacing a version-mismatched server.

Options for resolving this include:

| Policy | Behavior | Tradeoff |
|---|---|---|
| Registration-compatible coexistence | Keep current behavior; systemd owns normal boot, but a client may later spawn a detached replacement. | Minimal, but ownership is not durable. |
| Systemd-aware client | Local client asks `systemctl --user start opencode.service` instead of spawning when installation is detected. | Clean ownership on Linux; adds platform-specific control and unit discovery. |
| No-spawn client mode | Configuration/environment tells clients discovery may wait or fail but must not spawn. | Simple boundary; requires an operator-visible failure and explicit startup. |
| Server-owned install command | `opencode2 service install/start/stop` installs and controls the platform service manager. | Best product UX, but substantially expands cross-platform service management. |

For the Compfuzor prototype, a no-spawn mode would be the cleanest missing
primitive. Until it exists, document that clients can reactivate a detached
service after a deliberate systemd stop.

## Connection selection policy

Native discovery must not silently connect to an arbitrary LAN server. A
reasonable precedence is:

1. Explicit `--server` URL.
2. Explicit `--standalone` private process.
3. Healthy local registration file.
4. Previously paired server selected in client-local state.
5. Interactive list of newly discovered DNS-SD instances.
6. Local managed-service startup when policy permits it.

Automatic use of the only discovered LAN server is tempting but unsafe and
surprising, especially on shared networks. Discovery should feed selection;
mere visibility should not establish trust.

The client should persist a stable server identity plus credential, not merely
an IP address. DNS-SD can then update the endpoint of an already trusted server
without requiring repeated selection, consistent with RFC 6763's persistence
goal.

## Security and exposure

The current server uses Basic Auth over an HTTP URL. Basic Auth encodes but does
not encrypt the password. On an untrusted LAN, observers or an active attacker
may capture credentials or API contents unless a confidential transport is
provided. The server also controls powerful filesystem, shell, credential, and
session capabilities, so compromise has approximately the impact of the user's
OpenCode process.

Consequences for the requested all-network default:

- A password remains mandatory, but is not sufficient protection against
  network observation without TLS or another encrypted tunnel.
- Firewall policy should constrain interfaces or trusted network zones.
- Public Wi-Fi, container bridges, VPNs, and unexpected cloud interfaces make
  `0.0.0.0` broader than "the home LAN".
- mDNS is link-local discovery, but wildcard HTTP binding is not link-local;
  routing and firewall configuration determine reachability.
- CORS is not an authorization boundary for CLI/API clients.

Deployment choices, from narrowest to broadest:

| Mode | Bind | Advertisement | Intended use |
|---|---|---|---|
| Local-only | `127.0.0.1` | none | Same-host clients; safest current default. |
| LAN interface | specific private address | selected link | Preferred constrained remote mode. |
| Wildcard LAN | `0.0.0.0` plus firewall | selected link(s) | Requested convenience default with explicit trust assumptions. |
| Tunnel | loopback plus SSH/WireGuard/Tailscale forwarding | tunnel-specific discovery/config | Routed remote use with transport protection. |
| TLS proxy | loopback or private upstream behind Caddy/nginx | advertise HTTPS endpoint | Browser and LAN use with managed certificates/trust. |

The intent remains all-network by default, but implementation should make the
effective URLs and a clear HTTP credential warning visible at install/start
time. A specific-interface option is valuable beyond the requested binary
choice between wildcard and loopback.

## Scope boundaries

The first implementation should avoid conflating these independently useful
changes:

- systemd process installation and ownership;
- server bind defaults and interface selection;
- DNS-SD publication;
- DNS-SD browsing and selection UX;
- credential enrollment and storage;
- TLS or tunnel transport;
- routed discovery beyond the local multicast link.

In particular, changing V2's global managed-service default to `0.0.0.0` is not
required to let Compfuzor choose that default. A deployment can explicitly pass
the wildcard address first, gather operational experience, and later propose a
product-wide default with evidence.

## Suggested implementation sequence

### 1. Prototype the deployment in Compfuzor

- Add a V2-specific service definition rather than extending the current V1
  `opencode.src.pb` assumptions invisibly.
- Generate a user service with a fixed port and explicit wildcard or loopback
  bind mode.
- Generate/install `.dnssd` only in network mode.
- Ensure `systemd-resolved` mDNS and the desired network links are enabled.
- Document linger, firewall, password retrieval, and explicit client use.

Acceptance checks:

```sh
systemctl --user status opencode.service
opencode2 api get /api/health
opencode2 pair
resolvectl service _opencode._tcp local
OPENCODE_PASSWORD=... opencode2 --server http://host.local:49374
```

The exact `resolvectl` invocation should be verified on the target systemd
version; `avahi-browse -rt _opencode._tcp` is a useful independent check where
Avahi tools are installed.

### 2. Harden lifecycle behavior

- Decide whether systemd or OpenCode's client is the sole process supervisor.
- Prefer adding a no-spawn or external-supervisor mode before promising durable
  systemd ownership.
- Verify graceful stop, crash restart, version upgrade, stale registration,
  and concurrent client startup.
- Keep the private registration-file format and permissions unchanged unless a
  concrete migration requires otherwise.

### 3. Establish the DNS-SD profile

- Validate/register the service type or choose an experimental name while the
  profile is unstable.
- Define `txtvers=1`, stable identity semantics, and capability keys.
- Test multiple interfaces, duplicate instance names, IPv4/IPv6, VPNs, and
  network changes.
- Couple advertisement lifetime to actual health, or clearly accept static
  stale advertisements for the initial prototype.

### 4. Add client browsing and remembered selection

- Add DNS-SD as a discovery source, not as a replacement for explicit URLs or
  local registration.
- Present discovered instances interactively.
- Probe compatibility and authentication requirements.
- Persist selection by stable server identity.
- Never auto-trust a newly observed service.

### 5. Improve enrollment and transport

- Replace shared-password transfer with one-time pairing and per-client,
  revocable credentials.
- Add TLS directly or define supported reverse-proxy/tunnel configurations.
- Advertise transport capability accurately and reject downgrade surprises.

## Tests and failure cases

At minimum, exercise:

- wildcard, specific-interface, IPv4 loopback, and IPv6 loopback binding;
- mDNS enabled and disabled, including a host without systemd-resolved;
- service process healthy, starting, failed, stopped, and stale-advertised;
- systemd crash restart versus deliberate stop;
- client auto-start while the systemd unit is disabled or stopped;
- version match and mismatch between client and discovered server;
- missing, wrong, rotated, and revoked credentials;
- two visible servers with the same display name;
- a server address change while stable identity remains the same;
- laptop network/interface changes and suspend/resume;
- firewall blocking the TCP port while mDNS remains visible;
- malicious TXT values, oversized records, unknown keys, and a spoofed server;
- no credential or sensitive path appearing in DNS packets, journal output, or
  process arguments.

## Open decisions

1. Is `0.0.0.0` intended as the OpenCode product default, or specifically the
   Compfuzor deployment default?
2. Should the preferred remote mode bind a selected LAN address before falling
   back to wildcard?
3. Is plaintext HTTP acceptable only on a trusted LAN, or must the first remote
   release include TLS/tunneling?
4. Does systemd become the sole supervisor, and how do clients suppress their
   existing detached auto-start?
5. Should Compfuzor create a new V2 playbook, migrate `opencode.src.pb`, or keep
   V1 and V2 installations side by side during the transition?
6. What stable server identity survives process restart, package upgrade, and
   address changes? It should not be the process instance ID.
7. Which DNS-SD service type and TXT keys become public compatibility surface?
8. How does a remote client store and select credentials without environment
   variables?
9. Should a static `.dnssd` advertisement remain active while the user service
   is stopped, or must publication follow health?
10. Which non-Linux publishers and browsers are required for the initial scope?

## Recommended near-term decision

Adopt **Option A** as an explicitly Linux/Compfuzor prototype, while preserving
explicit URL connection as the reliable fallback. Do not yet change OpenCode's
product-wide loopback default. Use the prototype to settle:

- whether wildcard binding is operationally acceptable;
- the DNS-SD profile and instance-selection experience;
- how systemd ownership interacts with client auto-start;
- what secure enrollment and transport need to precede broader release.

If the prototype is successful, implement **Option B** for cross-platform
native discovery, but keep systemd publication available as a deployment-level
backend and diagnostic reference.

## Cross-references

- [`/opencode.src.pb`](/opencode.src.pb) is the existing Compfuzor OpenCode
  checkout/configuration path. It records earlier V1 mDNS intent but needs an
  explicit V2 migration decision.
- [`/.design/config-mcp/init.0.md`](/.design/config-mcp/init.0.md) scopes the
  current OpenCode configuration assembly work. Service management should not
  accidentally reintroduce competing writers for `opencode.json`.
- [`/.design/config-mcp/draft2.gpt56t.md`](/.design/config-mcp/draft2.gpt56t.md)
  provides the broader design for layered OpenCode configuration inputs that a
  future V2 service deployment should consume rather than bypass.
- [`/PLAN-systemd-refactor.md`](/PLAN-systemd-refactor.md) explains the ongoing
  move toward generic generated systemd units; the OpenCode service should use
  that path instead of adding another bespoke installer.
- [`/systemd-mdns.etc.pb`](/systemd-mdns.etc.pb) and
  [`/systemd-resolved-multicast.etc.pb`](/systemd-resolved-multicast.etc.pb)
  are the existing host and link-level mDNS prerequisites.
- [RFC 6763](https://www.rfc-editor.org/rfc/rfc6763) is the protocol basis for
  service enumeration, SRV/TXT resolution, persistent instance selection, and
  the `txtvers` convention used in this proposal.
