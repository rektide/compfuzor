---
type: DesignProposal
title: Minimal deployment-local fuzing declaration and action contract
status: draft
generated: {by: 'model:openai/gpt-6-astra', at: 2026-10-11}
sources:
  - resource: urn:opencode:session:ses_ed3fd05d5ffeCPRCMwcAZY343U
    title: Begin with the minimal fuzing declaration/action contract
  - resource: /design/fuzings/handoff0.gpt61s.md
    title: Explicit fuzings and OpenCode client refresh requirements
  - resource: /design/compfuzor-runtime/composition-draft0.gpt6a.md
    title: Explicit membership distinct from action identity
  - resource: /runtime/registry/README.md
    title: Advertisement distinct from native membership
---

# Minimal contract

This is a proposed contract, with an initial **render and read-only planning**
slice. Implementation of that slice does not establish human acceptance of the
schema. Installation, execution, and the OpenCode lifecycle integration follow
after the declaration boundary is inspectable.

## Ownership and declarations

A **fuze** is a deployment-owned composition with named actions. A **fuzing** is
a constituent-owned contribution to that exact composition. Membership and action
selection are separate: installing a proxy can enroll it without restarting it.
One deployment may own one fuze and publish multiple fuzings, including a fuzing
to itself. IDs are literal safe stems; instance scope comes from the exact target
deployment plus fuze ID and audience, never from process or service names.

Proposed Ansible declarations (illustrative deployment paths):

```yaml
# Owner
FUZE:
  id: opencode
  scope: user
  actions:
    refresh-client: {kind: zim-import, required: [opencode-client]}
    activate-client: {kind: shell-source, required: [opencode-client]}
    check-client: {kind: exec}
    restart-dependencies: {kind: exec}

# Constituent; every action order is explicit.
FUZINGS:
  - id: bus-proxy
    target:
      dir: /usr/local/src/opencode-git
      fuze: opencode
      scope: user
    actions:
      refresh-client: {kind: zim-import, order: 60}
      activate-client:
        kind: shell-source
        order: 60
        path: etc/zim-modules/opencode-bus-proxy-env/init.zsh
      check-client: {kind: exec, order: 60, path: bin/check-client.sh}
      restart-dependencies: {kind: exec, order: 60, path: bin/restart.sh}
```

`FUZE` compiles to `etc/fuze.json`; `FUZINGS` compiles to constituent-owned
`etc/fuzings/<id>.json` and a closed `etc/fuzings.json` publication index. Both
carry version 1 and the rendering deployment's `{id: NAME, dir: DIR}`. An empty
explicit `FUZINGS: []` emits an empty index; historical descriptors are retained
but no longer offered by that index. Generation creates only local artifacts.

An installed `<owner>/etc/fuze.d/<id>.json` symlink to the exact constituent
descriptor establishes membership. This is a native composition directory, not
an XDG rendezvous registry or the ZIM host locator. The owner creates the directory;
the proposed constituent install action will validate target identity/scope and
publish its reference there through existing LINKS delivery. A missing target
will fail installation, with render-first/install-owner-first as the recovery.
Repeated install must retain a matching reference and any disabled state; a foreign
reference or regular file must not be overwritten. These installation semantics
are requirements for the next slice, not supplied by the initial planner.

Membership can be disabled by renaming the link to `<id>.json.disabled`, enabled
by reversing that rename, or removed by unlinking it deliberately. Both spellings
present is an error. A disabled dangling link is inspectable without loading its
producer. An active dangling link fails planning. Directory absence is an error
rather than a successful empty composition; an existing empty directory is valid.
Unrelated filenames are ignored and never pruned. Regular JSON membership files
are rejected: the descriptor's maintained home stays with its constituent.

## Actions and ordering

The owner declares supported action names and their kinds. A member may join a
subset; a join to an unknown action or with an incompatible kind fails admission.
Kinds describe invocation shape:

- `zim-import`: import the constituent deployment through the existing ZIM
  contributor/host machinery. It is not an alternate fragment compiler.
- `shell-source`: identify a constituent's deployment-relative `etc/` shell
  file, to source in the **calling shell**, not in a subprocess.
- `exec`: identify a deployment-relative `bin/` command and optional literal
  argv array. No shell interpolation or broadcast caller arguments.

Each action selects only its own joins. Sort by numeric `order`, then literal
member ID (code-unit ordering, independent of locale/filename enumeration).
There are no implicit child actions, inferred dependencies, retries, parallelism,
or transitive fuze traversal. A required-ID list on an owner action makes absent,
disabled, or nonparticipating members an error for that action. Without required
members, an empty action plan is valid and visibly empty.

The initial planner validates descriptors and binds paths, but does not verify
handler executability, ZIM availability, or service readiness. Those are execution
admission checks. Plans include owner/constituent identity, exact source descriptor,
selected action, order, resolved path/producer and fixed argv. They are inspection
results, not durable authorization tokens: execution must admit a fresh selection
and guard its inputs. Sequential execution will stop on first failure, report
completed work, and preserve recovery state; it cannot promise rollback of an
arbitrary command or imports already committed by ZIM.

## Intended OpenCode flow

The primary declares a fuze and its own client contribution. The proxy owns its
routing ZIM module and its fuzing. Secondary deployments have distinct exact targets
and do not enroll into the primary's interactive surface implicitly.

1. `refresh-client` applies all selected constituent ZIM imports. Resolve one
   intended host/context for the operation; missing host or bypass is **incomplete**,
   not the existing bridge's successful skip. The present ZIM importer assembles
   and rebuilds each import; reuse that behavior initially rather than adding a
   batch compiler or claiming an aggregate transaction.
2. `check-client` checks the chosen origin/proxy endpoint and credentials. Perform
   refresh/readiness before terminating clients during one-pass restart.
3. Retain the existing client inventory, session/pane resolution, exclusions, idle
   gate, and process termination boundaries.
4. Relaunch rechecks refresh/readiness (including split kill/relaunch), then sends
   an owner-controlled narrow activation command into each existing pane shell,
   followed by the client command only on successful activation. Failure retains
   the registry and leaves clients stopped rather than launching into a broken
   endpoint. No blanket `.zshrc` reload.
5. `restart-dependencies` is a separately selected action. The origin's existing
   restart stays origin-only; a later owner operation can explicitly sequence
   origin restart, selected dependency restarts, and readiness.

Shell activation needs a follow-on domain policy, beyond a source-path list:
remember each managed default in shell-local state; replace values still equal to
their prior managed defaults, preserve deliberately changed overrides, and track
credential pointers without persisting secret values. Legacy shells lacking that
state need an explicit migration rule. Define the routing function independently
of module arrival order; respect routing overrides across argv and exclude lifecycle
commands. A plain source of current ZIM env modules is not sufficient proof.

`OPENCODE_SERVER_PORT` remains the origin port authority. A common vars input
loaded independently by both playbooks can provide its primary default and a
distinct proxy port; per-instance overrides must be supplied consistently to both
renders. Ansible interpolation produces literal ENV/ZIM defaults. Runtime shell
overrides do not reconfigure rendered systemd listen addresses. The forthcoming
integration must expose mismatched independently rendered endpoints through
readiness checks. Proxy routing alone does not enable selective delivery; that
also requires a bus-smart origin and client `experimental.session_streaming`.

## First implementation boundary

Implement strict declaration compilation, ordinary local artifact rendering, and
a source-only read-only planner. Prove membership, deterministic order, instance
and audience matching, required/disabled/missing contributions, action separation,
and nonmutation in isolated fixtures. This makes the contract testable without
bundling unrelated unfinished `files/config/registration.ts` changes into the
shared runtime. Deployed command aliases and runtime rebuilding belong with the
installation/execution slice once that shared build input has an agreed state.

Then connect constituent installation, native ZIM refresh and narrow shell
activation, and finally the OpenCode/proxy declarations and client lifecycle.
Keep each checkpoint's verified behavior distinct from the intended flow above.
