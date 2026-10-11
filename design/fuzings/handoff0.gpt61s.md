---
type: Handoff prompt
title: "Explicit Compfuzor fuzings — OpenCode client refresh and bus proxy"
status: draft
generated:
  by: model:openrouter/openai/gpt-6.1-sol
  at: 2026-10-11
sources:
  - resource: urn:opencode:session:ses_ed40033a8ffeUXhktJmUbygUQg
    title: "Human direction in cosmic-engine: explicit fuzings and ZIM refresh before client restart"
  - resource: /opencode.src.pb
    title: OpenCode deployment and restart operations
  - resource: /opencode-bus-proxy.src.pb
    title: Bus proxy deployment, supplied as the initiating example
---

# Handoff: start explicit Compfuzor fuzings

Work in `/home/rektide/src/compfuzor`. Read its `AGENTS.md` and the applicable
workspace instructions. Use jj; preserve unrelated work. This handoff is the
only change made by the originating session, not an implemented feature or an
accepted schema.

## Human direction — do not narrow this to an OpenCode-only workaround

The initial request was to make `opencode-bus-proxy.src.pb` contribute a ZIM
piece that sets the appropriate client environment/port, understand how the
variables interpolate, improve OpenCode dependency restart, and make the
constituent pieces easy to update together. The human suggested `fuze.d/`.

Two subsequent clarifications govern the work:

> “the net idea being that when we restart client we can run the zim thing that
> runs all the zim pieces for opencode before restarting the client somehow”

> “but giving compfuzor explicit fuzings”

Build a **formal Compfuzor composition concept**, exercised first by OpenCode
and its bus proxy. Do not solve this solely with a hard-coded proxy path/list
inside OpenCode's restart script. A constituent should declare its contribution
and join the selected fuze through the normal deployment/install machinery.

The human has not selected variable names, descriptor schema, registry scope,
or command names. `fuze.d/` is their suggested shape, not a settled complete
protocol. Establish a small, understandable contract before implementing it;
distinguish your proposed mechanics from the requirements above.

## Expected useful result

- Compfuzor can explicitly describe a fuze and its constituent fuzings, rather
  than inferring membership from process names, matching paths, or systemd
  dependencies. Explain membership, ownership, order, and action selection.
- The bus proxy owns its client-routing ZIM contribution and its enrollment
  with the OpenCode fuze. Installing the constituent supplies the declared
  configuration automatically to the intended owner; rendering alone must not
  mutate a live OpenCode deployment or restart services.
- There is one easy operation to apply **all selected OpenCode constituent ZIM
  contributions**. Reuse the existing ZIM contributor/host machinery, not a
  competing fragment compiler.
- Client restart uses that aggregate update before bringing clients back, and
  relaunched clients actually inherit the refreshed environment in their
  existing tmux pane shells.
- Dependency restart has an explicit composition surface too. Keep service
  restart distinct from client-only restart and from ZIM/config refresh. The
  human wants better dependency handling, not implicit authorization to bounce
  every nearby daemon whenever a TUI restarts.
- Origin and proxy ports are explicit and derived consistently. Document the
  boundary between Ansible render-time interpolation, generated ENV/ZIM
  values, and shell/runtime overrides.

## Verified starting points in the source

These observations come from reading source, not live deployment inspection.
Recheck after concurrent work; the starting parent was commit `ce951493`
(“opencode: default interactive clients to the bus proxy”).

### OpenCode and proxy

- `opencode.src.pb` already declares `OPENCODE_SERVER_PORT`: primary `git`
  defaults to 49373; secondaries require an explicit distinct port.
  `OPENCODE_SERVER_URL` is derived from it. Do not introduce an unexplained
  second origin-port authority just because the request says “explicit var.”
- The primary is wildcard-bound, secondaries loopback-bound. Primary owns the
  unsuffixed unit, global commands, config link, and interactive ZIM surface;
  secondaries have instance-specific launchers and bypass ZIM generation.
- OpenCode ENV currently hard-codes primary `OPENCODE_PROXY_URL` to
  `http://127.0.0.1:49372`, but **does not include it in `ZIM_ENV`**. Its ZIM
  projection only includes server URL, server port, and password-file pointer.
  Thus generating deployment ENV is not proof that a fresh shell gets proxy
  routing.
- The OpenCode env module is phase 54; `opencode-client-args`, sourced from
  `files/opencode/opencode-client-env.zsh`, is phase 55. That file exports the
  credential and conditionally defines `opencode()` only if the proxy URL is
  already present. A proxy contribution loaded later cannot simply assume
  this function was created. It currently tests bypass arguments only at
  `$1`; examine explicit `--server`/`--standalone` elsewhere in argv and
  lifecycle/non-client commands when deciding the routing contract.
- `opencode-bus-proxy.src.pb` currently has no ZIM declaration. It hard-codes
  upstream `http://127.0.0.1:49373` and listen `127.0.0.1:49372`. It shares
  the primary's stable password-file view. Its unit Wants/After
  `opencode.service`, deliberately not Requires; independent restarts and
  reconnect are supported. `/_bus/health` is source readiness, not just
  process liveness.
- Selective delivery requires a bus-smart origin and client
  `experimental.session_streaming: true`; do not accidentally present proxy
  routing alone as enabling selective delivery.

### ZIM interpolation and activation

- `tasks/compfuzor/gen_zim.tasks` projects explicitly listed `ZIM_ENV` keys
  from effective ENV, resolving value templates at task scope. It generates
  local module bodies under `etc/zim-modules/<name>/init.zsh` and declarations
  under `etc/zim/<channel>/active/` or `disabled/`.
- `library/filter_plugins/zim_fragment.py` assigns phase-prefixed filenames.
  Generated env modules preserve existing nonempty values unless
  `COMPFUZOR_ENV_OVERWRITE` opts into replacement. This matters when a pane
  shell already has the old port/URL: sourcing a fresh module may otherwise
  leave it unchanged. Decide a targeted refresh policy; do not stomp unrelated
  shell environment to fix OpenCode.
- Contributors get `bin/install-zimfw.sh`, which locates the host via the ZIM
  registry pointer or `ZIM_HOST_DIR` and calls its `install-zim-context.sh`.
  The bridge currently reports a skip if the host is absent; decide whether
  that counts as sufficient refresh for a restart that depends on new routing.
- `files/install-zim-context.sh` delegates to the ZIM runtime's import action.
  Read `files/zim/runtime.ts`, `files/zim/activation.ts`, and
  `doc/config/consumer-toolkit.md#zim-complete-installation` for actual behavior.
- Rebuilding ZIM configuration/cache **does not change an existing shell's
  environment**, and a subprocess cannot export back into its parent shell.
  Updating on disk and loading refreshed pieces in the pane are separate jobs.
  Do not just run the installer and assume relaunch sees new values. Avoid
  blindly sourcing all of `.zshrc` in every pane; consider a narrow,
  repeatable activation operation owned by the fuze.

### Restart operations

- OpenCode's authored `bin/restart.sh` reloads systemd if needed, restarts the
  selected origin unit, authenticates `/api/info`, and checks its inherited
  Watchman socket. It does not currently restart the bus proxy.
- `files/opencode/restart-clients.sh` is a raw Bash bin. It records clients
  using cotail and tmux into a tmpfs TSV registry, kills them, and types
  `opencode --session <id>` into their existing panes. It does not reload
  shell config. Default `restart` is client-only; separate `kill` and
  `relaunch` preserve the registry around an operator-controlled server restart.
- Retain the safety boundaries: spare serve/server processes, server-spawned
  tool shells, and the script's own tree; retain session/pane resolution,
  idle gating, and dry-run behavior. Consider both one-pass restart and split
  kill/relaunch so the latter cannot silently miss refresh.

## Fit the existing toolkit before adding machinery

Read `doc/config/consumer-toolkit.md`, `tasks/compfuzor.includes`, the config
compiler/runtime, and the relevant composition inquiry in
`design/compfuzor-runtime/`. `CONFIGS` and `config-remote.mjs` already support
owned producer files referenced by consumer input symlinks, assembly, and
deliberate enable/disable. `runtime/registry/README.md` explains the newer
registry and distinguishes advertisement from native membership/execution.
Do not conflate these different registries or assume a ZIM offer is already
imported because it is advertised.

Choose the smallest generic declaration/compiler/runtime seam that represents
explicit fuzings. Do not invent a second scheduler, global dependency scanner,
or parallel ZIM implementation. Make commands inspectable; order should be
declared and deterministic, not accidental directory enumeration. Define
missing/disabled contributions, failure behavior, and how an operator changes
membership. No automatic broad pruning of undeclared historical artifacts.

Open design questions to resolve visibly:

1. What does a fuze own, and what does a constituent publish? How does an
   explicit target relate to `fuze.d/`, deployment identity, and instance scope?
2. How do actions select contributions without equating “is a member” with
   “restart this service for every action”? How do config, ZIM, shell activation,
   and dependency restart relate without becoming one undifferentiated install?
3. How are independently rendered origin/proxy port inputs shared? Ansible
   variables from one playbook do not magically exist in another playbook.
4. What refresh can safely run before client termination? On refresh or
   readiness failure, do not blindly relaunch into a known-broken endpoint;
   keep a usable recovery route and the recorded registry.
5. How does existing-shell activation apply new defaults while respecting
   deliberate user overrides, instance isolation, credentials, and load order?

## Verification and operating boundaries

Use isolated fixture deployments under `/home/rektide/tmp-opencode`, not live
installation. Invoke playbooks with `-i 'localhost,' -c local`; bypass packages,
repos, bin execution, global links, and systemd activation, redirecting every
generated root. Syntax-check both OpenCode playbooks as well.

Test the generic fuzing contract independently and its OpenCode use case:
membership/order, contributor installation, repeatability, disabled/missing
pieces, action separation, custom ports, primary/secondary isolation, fresh
shell routing, already-running shell refresh, explicit routing overrides,
client restart ordering, dry-run nonmutation, and failure/recovery behavior.
Stub tmux/systemctl/curl/cotail and clients; never kill real clients as a test.

Existing `tests/integration/opencode_instances.test.py` and
`opencode_foreground_service.test.py` contain assertions for older serve
wrappers/OPENCODE_ARGS that no longer match current source. Treat them as
historical test scaffolding, not proof that those removed behaviors should be
restored. Diagnose pre-existing failures separately from the new coverage.

At handoff there was unrelated working-copy work in registry-discovery docs,
`files/config/registration.ts`, its tests, `vit.src.pb`, `.beads/issues.jsonl`,
and other files. Preserve it; if rebuilding the shared runtime would bundle
unrelated unfinished changes, resolve that scope explicitly rather than
silently committing them. Do not create tickets or spawn agents without the
appropriate human/instruction authorization.

Start by presenting the minimal declaration/action contract and the intended
OpenCode flow. Then implement a coherent, tested slice with file-scoped jj
checkpoints. Keep proposed schema choices and verified behavior distinct in
the resulting explanation. Do not deploy, rebuild the live OpenCode binary,
restart the server/proxy, or restart this session's clients without explicit
authorization.
