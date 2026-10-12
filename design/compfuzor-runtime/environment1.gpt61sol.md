---
type: DesignFindings
title: A selected environment view and a live-shell receipt
description: An isolated executable probe establishes the smallest retained-default contract, works the proxy URL/native-args cases, and bounds the first new-CFR implementation slice.
resource: /design/compfuzor-runtime/environment1.gpt61sol.md
status: draft
generated: {by: 'model:openai/gpt-6.1-sol#xhigh', at: 2026-10-12}
sources:
  - resource: opencode://ses_ed1977ea9ffeC1qwSdlWJr88V4
    title: tidy-cabin — independent follow-up, selected-default and live-shell prototype, scenario verification, and next-slice recommendation
  - resource: /design/compfuzor-runtime/environment0.gpt6a.md
    title: Parent's direction and recorded human intent; proposal, not accepted schema
  - resource: /design/fuzings/proxy0.gpt61sol.md
    title: Completed selective service/client adoption and source-time-default limitations
  - resource: /doc/config/definitions.md
    title: Actual complete CONFIG bindings, exact projections, literal grammar, and context boundary
  - resource: /design/runtime-direction/index.md
    title: Runtime direction and distinction between existing implementations and intended new CFR
  - resource: /design/compfuzor-runtime/effect-draft2.gpt6a.md
    title: Shared init, explicit child projections, mutable run-data snapshots, and unresolved execution integration
  - resource: /design/runtime-sourcing/direction0-syn.gpt61sol.md
    title: Implementation-provider identity differs from the deployment being operated on
  - resource: /files/config-env.py
    title: Actual assignments parser and ordered dictionary reduction imported by the probe
  - resource: /library/filter_plugins/env_compile.py
    title: Exact-file projection authoring and independent ENV CONFIG generation
  - resource: /files/config/context.ts
    title: Existing named-recipe and context-path binding to reuse rather than replace
  - resource: /files/config-run.sh
    title: Existing ordered input manifest, processor boundary, and publication-only worker semantics
  - resource: /opencode-bus-proxy.src.pb
    title: Actual separate service/client files and native Zim module binding
  - resource: /files/opencode-bus-proxy/opencode-proxy-env.zsh
    title: Actual empty-or-unset bootstrap and effective-URL-derived native args
  - resource: /files/_helpers/env
    title: Whole env.export compatibility loading followed by restored execution context
  - resource: /files/actions/environment.sh
    title: Existing setup subprocess, not observation or mutation of calling-shell variables
  - resource: /files/actions/session.ts
    title: Exported process-environment capture and prepared-invocation transport
  - resource: /files/actions/process.ts
    title: Existing explicit subprocess environment and inherited marker filtering
  - resource: file:///home/rektide/src/envdefault/envdefault
    title: Current set-variable preservation with no retained last-applied default
  - resource: file:///home/rektide/src/opencode-working/packages/cli/src/args/environment.ts
    title: Real native shell-word reader and explicit-argument suppression, checked for the new quoting case
  - resource: file:///home/rektide/src/opencode-working/packages/cli/src/args/environment.test.ts
    title: Existing native argument fixture used to construct one new focused verification, not rerun wholesale
verification:
  date: 2026-10-12
  scope: Isolated scratch resolver, selected literal snapshots, explicit child env, Zsh bridge, and focused native argument preparation only
  result: Nine scenario groups passed; scratch core/CLI/tests strict typecheck passed; three new native argument assertions passed
---

# Recommendation

**Implement a selected environment view plus an application receipt, not another
envdefault and not a global environment manager.** One pure CFR resolver consumes
an immutable default snapshot, selected current observations, and a receipt from
the *same live owner*. A domain function supplies derived candidates. A shell
adapter observes/applies/acknowledges; it does not decide precedence.

The isolated probe establishes this contract without Effect bootstrapping or a
production CLI. Existing CONFIG and the actual proxy module are unchanged. The
parent retains architectural responsibility; the rules here remain a proposed
first slice, not accepted user policy.

## What this changes in the parent's proposal

- Its four information sets are useful, but do **not** require four mutable stores,
  services, or an environment-history database. Start with a snapshot, a pure plan,
  and one nonexported, shell-local receipt for the proxy binding.
- Preserve **a recorded preservation decision** for untracked inputs after an
  apply succeeds. Otherwise an initially present legacy URL C later unset in that
  shell looks like a fresh absent key and is silently defaulted again. Recording
  `held/untracked` avoids that without pretending C was an explicit user pin.
- Target-scoped receipts alone do not solve ownership of one shell variable by
  two targets. The first proxy adapter should refuse a foreign binding, not keep
  independent receipts which can take turns reclaiming the same OPENCODE_ARGS.
- Removed defaults are reported and retained. No automatic unsetting/pruning is
  necessary for this capability. Reset to a nonexistent default fails explicitly.
- A selected-child invocation is useful, but it does not prove live-shell refresh.
  Prefer the narrow proxy receipt/bridge proof over migrating a generated helper
  first; the latter still reloads whole env.export internally.

# 1. Selection is a request, not an environmental search

An operation requests **explicit target + CONFIG definition + named recipe +
context**. The ENV projection's existing ordered exact input list is the source
of selection; do not duplicate it in a new authored env manifest. Reuse
[CONFIG context binding](/files/config/context.ts), then reduce the selected
literal files with the existing parser. The proxy client's compiled recipe is
`proxy-client.env`, exposed as `etc/env-projections/proxy-client.env.export`;
inspect the generated spec rather than infer recipe identity from the output.

| Operation | Selected literal inputs | Domain output |
|---|---|---|
| Proxy service view | `50-proxy-service.env`, then `99-local-priority.env` | Service settings, no client args |
| Proxy client view | `60-proxy-client.env` only | URL; client domain can derive args |

Three independent decisions remain visible:

1. **Contribution selection:** which defaults/keys are contributed by this request.
2. **Host inheritance:** child env may inherit the host or be constructed explicitly.
   Selecting the client does not remove an already inherited BUS_PROXY_PASSWORD.
   An explicit-only child also needs consciously supplied PATH/HOME/etc if required.
3. **Execution identity:** admitted target, command root and cwd come from binding,
   not an application variable called DIR. An env view may contain DIR as data.
   A legacy consumer requiring bound DIR gets it from its process adapter last.

Do not scan all env.d, then filter variable names by a type guess. Independent
CONFIGs and their exact recipes already supply the useful boundary. Runtime
implementation-provider selection is another independent concern; choosing
canonical CFR code must not silently change the deployment whose env is read.

# 2. Defaults stay readable while overridden

The snapshot holds ordered source identities, content digests, each source's
normalized assignments, final values, and winning-source indexes. This exposes
both per-input authored literals and reduced defaults. It is not the original
Ansible/Jinja expression, nor a parser of generated shell exports.

The probe imports **`files/config-env.py:assignments`** and uses its existing
ordered `dict.update` reduction. Dollar expressions remain literal data. No second
dotenv grammar, shell eval, new ENV_CONFIG format or assembly transaction is needed.
Production should expose a read-only structured reducer from that same module;
only the first exact-file path is required, not a new general glob enumerator.

An applied managed record retains the relevant literal value, winning source
path/digest, and last applied value. A derived record retains its domain identity
and effective input. An inferred hold retains that predecessor. Rewriting the
source from A to B cannot erase the live shell's A comparison baseline. Digests
identify observed content; they do **not** archive old full source bytes.

`defaults` reads authored/reduced literals even if current URL is C; `plan/explain`
shows effective C, held/untracked/edit status, and candidate args derived from C.
Neither commits a receipt. An args default is a domain formula, not a fictitious
authored assignment. An optional “args from default URL B” preview must be labeled
separately from “managed args candidate from effective URL C.”

# 3. Minimum change knowledge

Presence is `absent` or `present(string)`; present empty is not absent. Receipt
entries need only two ownership modes with distinct causes:

```text
managed { lastApplied, basis: literal-winner or domain-effective-input }
held    { cause: explicit-pin | detected-edit | untracked-input,
          optional prior managed basis }
```

“Held” means preserve *whatever is observed now*, not keep rewriting a frozen
override value. Untracked is an uncertainty label, not inferred authorship. A
successful initial application records its preservation stance so later empty
or absent observations do not reacquire management by accident.

| State and observation | Proposed resolution |
|---|---|
| Managed; current equals lastApplied | Follow new literal/domain candidate |
| Managed; current differs, including empty/absent | Preserve; record held/detected-edit |
| Held | Preserve until explicit reset, even if equal to today's default |
| No history; absent | Bootstrap selected candidate |
| No history; present | Preserve as untracked; after apply, record held/untracked |
| Generic no-history empty | Present/untracked; do not default |
| Previously managed; default removed | Retain value/basis, report removed; do not prune |

Explicit **pin** marks preservation even when current equals lastApplied.
Explicit **reset** selects the current default/domain candidate and becomes managed
only after successful apply. Neither guesses intent from equality. Edit-and-revert
before observation cannot be detected; pin is the proportionate escape hatch.
No disk environment dump is required. Initial support should restrict this receipt
to nonsecret proxy values; history can record source/reason metadata rather than
persist ambient credentials or selected secret plaintext.

# 4. Worked proxy cases

Let A=`http://127.0.0.1:49372`, new default B=`http://127.0.0.1:50372`, and local
override C=`http://operator.example:6000`. The domain resolves URL **first**, then
computes `OPENCODE_ARGS` from its effective URL and resolves args ownership with
the same primitive. This is ordinary domain code, not a universal dependency DSL.

| Before refresh | Result with default B |
|---|---|
| Managed URL A, managed args(A), both unchanged | Managed B and args(B) |
| URL changed to C, args still equal lastApplied args(A) | Held C; managed args(C) |
| Managed URL A, custom args `--standalone` | Managed B; held custom args |
| Legacy present A/args(A), no receipt | Both preserved/untracked; no ownership guess |
| Legacy URL C, args absent | Held/untracked C; bootstrap managed args(C) |
| Explicit URL pin at A | A survives; managed args follow A |
| Reset legacy URL only | B; present untracked/custom args survive |
| Reset URL and args | Managed B and args(B) |

Two deliberately different empty policies are essential:

- **Bootstrap with no receipt:** preserve today's proxy module semantics: empty
  *or* unset URL/args takes the default. A nonempty unexported URL is observed and
  exported, rather than lost by taking subprocess process.env as its observation.
- **After a recorded decision:** a change to empty/unset is a local change and
  remains held. For intentionally empty/absent effective URL, the proposed domain
  candidate is **absent args**, not malformed `--server `; still-managed args are
  unset, custom/held args survive. This is an explicitly requested domain refresh,
  not automatic deletion of removed literal defaults. Reset re-enables routing.

The latter policy is **new proposed behavior**, not silently equivalent to
re-sourcing the existing module. Legacy present args cannot safely be inferred
as managed even if they spell the old generated endpoint. An explicit reset is
needed to migrate them; automatically installing a new module would not solve it.

The probe quotes the URL as one native shell-word value rather than concatenating
arbitrary text into args. A focused check through the real native argument reader
verified quote/space/dollar/backslash/backtick preservation, and that explicit
`--server`/`--standalone` still win. No OpenCode process was launched.

# 5. Boundary: plan, apply, acknowledge

```text
bound inputs → immutable defaults snapshot
selected shell observations + receipt → pure plan / explain
recheck observed presence/value + receipt revision → apply in caller's shell
verify resulting values → replace receipt
```

CFR owns input selection/reduction, value decisions, reasons and proposed receipt.
The shell owns observation of unexported parameters, presence, assignability and
application in its own process. It exports the proxy's two values by domain policy,
not because generic CFR treats every shell parameter as an exported string.

The bridge preflights all keys before the first write and rejects ordinary stale
observations or state. Only after all assignments/unsets and value verification
succeed does it replace its nonexported receipt. Read-only explain is not adoption.
Failed application leaves the old receipt; that is **not** an atomic rollback
promise. A partially changed value then differs from its baseline and is handled
conservatively on the next explicit refresh.

The source snapshot remains the plan's input even if files change before apply.
Report its digests; another explicit refresh reads newer files. No file lock,
“always latest” claim, or automatic retry is needed for this first slice. Traps or
signals interrupting multi-variable application are not transactionally fenced.

The first adapter uses **one binding per live proxy receipt**. Foreign target,
CONFIG, recipe or domain-policy identity fails; an explicit switch/reset can be
designed later. New shells do not inherit the nonexported receipt. Separate child
execution gets an explicit environment, but must not acknowledge/advance the
parent shell's receipt merely because a child was started or exited successfully.

# 6. Smallest useful new-CFR slice

| Starting slice | Payoff / limitation |
|---|---|
| Structured selected-default inspection only | Immediately findable defaults; no managed refresh |
| Selected native child env first | Useful process isolation; exported-input transport only, no live-shell change knowledge |
| **Selected view + pure resolver + explicit proxy refresh** | Proves the user's retained-default case without broad runtime migration; recommended |

In the desired shared init, load an `EnvironmentView(binding)` snapshot into run
data, allow declared init adjustments, then resolve an immutable view at the
consuming operation's revision. Native services/children receive explicit values;
do not overwrite global process.env or make all operations use one universal
merged Environment field. A later workflow can record snapshot/plan results and
update run data outside cached Activity bodies, as draft2 requires. No new Effect
service/layer/workflow API was implemented or needed by this probe.

**Exact next coding task to commission:** add an importable, unregistered new-CFR
environment module and one explicit proxy refresh adapter, with these bounds:

1. Reuse the selected independent CONFIG spec/context and named *exact-file ENV
   recipe*. Extend `files/config-env.py` with a structured read-only snapshot
   function/mode sharing its reducer. Reject unsupported recipes; no whole-env
   fallback, new authored selection map or installation/publication side effects.
2. Implement the pure TypeScript decision/plan/ack contract with boundary validation
   and cloned/immutable snapshots. Keep the OpenCode URL→args function domain-owned.
   Support pin/reset, held-untracked state, missing-source errors and removed-retained
   explanation. Keep application identity out of contributed env.
3. Add an **explicitly invoked**, nonregistered Zsh adapter for ordinary global
   scalar proxy parameters, one nonexported receipt, stale recheck and post-apply
   acknowledgment. Do not wire normal Zim startup, change generated env helpers,
   refresh existing panes, or automatically switch owner bindings in this slice.
4. Promote the scenario fixtures below into tracked tests. Demonstrate default
   inspection while overridden, A→B, C with managed args, custom args, legacy
   reset, empty/unset, removal without pruning, foreign binding and failed apply.
   Stop at this interface checkpoint before Effect workflow integration or adoption.

Two plausible domain-grouped homes are `runtime/environment/{snapshot,resolve,...}`
with `runtime/opencode/...` for domain derivation, or a new `files/cfr/environment/...`
alongside other CFR source domains. Choose with the parent; neither is a command
added to the existing multicall/action runtime under a new name.

# Evidence and reproduction

Scratch lives in `.test-agent/cfr-environment/` with a README, imported literal
snapshot executable, pure TS resolver, explicit proxy executable, tiny Zsh bridge,
scenario tests and one native-reader check. It is intentionally gitignored, not
shipped. The contract/tables above and session provenance preserve the result;
scratch code is an oracle for the next implementation, not an accepted library.

```sh
node --test .test-agent/cfr-environment/verify.ts
pnpm exec tsgo --ignoreConfig --noEmit --target esnext --module nodenext \
  --moduleResolution nodenext --allowImportingTsExtensions --strict --types node \
  .test-agent/cfr-environment/resolve.ts .test-agent/cfr-environment/probe.ts \
  .test-agent/cfr-environment/verify.ts
bun .test-agent/cfr-environment/native.ts
```

Verified: nine scenario groups pass; strict scratch typecheck passes; three new
native preparation assertions pass. Fixtures use the actual 50/60/99 input names
and values, retain source snapshots across an in-place rewrite, and launch an
explicit-env Node child plus isolated `zsh -f`. The shell exercises A→B, unexported
URL edits, literal quoting, no receipt export, stale args rejection and readonly
preflight. Expected stale/unsupported diagnostics are test outcomes, not failures.

Not proven: generated-spec admission/deployment delivery, source line-level loser
history, generic shell attributes, multi-owner arbitration, signal-safe rollback,
secret persistence, automatic startup adoption, or durable Effect replay. Prior
proxy/CONFIG checks are trusted rather than repeated. No production source,
systemd state, client/pane, daemon build, ticket or live deployment changed.

## Connections

- [Parent direction](environment0.gpt6a.md): extends its last-applied comparison;
  narrows storage, removal policy and first adoption order with concrete evidence.
- [Completed proxy adoption](../fuzings/proxy0.gpt61sol.md): implemented native
  contribution separation; this wave targets its explicitly unimplemented refresh.
- [CONFIG definitions](../../doc/config/definitions.md#literal-grammar-and-projections):
  owns actual selection/grammar; this proposal adds a view, not another assembly owner.
- [Shared init/run data](effect-draft2.gpt6a.md#4-shared-init-is-an-extensible-pipeline):
  future integration point, not a mandatory prerequisite for the selected view.
- [Runtime sourcing](../runtime-sourcing/direction0-syn.gpt61sol.md#2-keep-three-catalogs-and-two-roots-distinct):
  precedent for keeping selected implementation code separate from env target identity.
