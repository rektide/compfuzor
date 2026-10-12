---
type: DesignProposal
title: Selected environment contributions and retained defaults in cfr
description: Preserve findable defaults and distinguish managed values from local overrides using selected runtime data, informed by the completed proxy adoption.
resource: /design/compfuzor-runtime/environment0.gpt6a.md
status: draft
generated: {by: 'model:openai/gpt-6-astra', at: 2026-10-12}
sources:
  - resource: opencode://ses_ed3f4aaaaffePYlWeomteOWlbg
    title: brave-meadow — human direction after proxy implementation to select env narrowly and retain default/change knowledge in new cfr
  - resource: /design/fuzings/proxy0.gpt61sol.md
    title: Completed proxy adoption, verified separation, and remaining envdefault/refresh limitations
  - resource: /doc/config/definitions.md
    title: Implemented ENV inputs and exact-file projections
  - resource: /design/fuzings/contract0.gpt6a.md
    title: Earlier managed-default refresh requirement, distinct from its obsolete routing-wrapper proposal
  - resource: /design/compfuzor-runtime/effect-draft2.gpt6a.md
    title: Proposed cfr shared initialization and mutable run data with explicit process projections
  - resource: /files/actions/session.ts
    title: Current action environment capture records effective exported values, not default lineage
  - resource: /files/_helpers/env
    title: Current whole-export sourcing and restored legacy envdefault preference
  - resource: /files/opencode-bus-proxy/opencode-proxy-env.zsh
    title: Runtime-derived native client arguments and source-time default behavior
---

# Direction after the proxy checkpoint

**Select the environment an operation needs; retain defaults as inspectable data
alongside effective values.** Put comparison and resolution in new cfr. A shell
bridge applies selected results and supplies shell-local observations; it does
not grow another general defaulting engine.

The human asked to let the proxy agent finish before taking this direction. Its
completed [adoption](../fuzings/proxy0.gpt61sol.md) provides the concrete baseline:

- Service config selects service input plus priority; client config selects only
  the client input. Both derive their endpoint from the shared port declaration.
- Normal ZIM import remains normal; its module sources a literal URL default and
  derives native OPENCODE_ARGS from the effective runtime URL.
- Generated commands still load whole env.export through the restored envdefault
  preference. This preserves old invocation behavior but is not selective cfr
  environment handling.
- Nonempty client args survive re-sourcing even when their formerly managed URL
  has changed. The current module has no last-applied state to explain or refresh
  that relationship.

Parent source review agrees with these boundaries. The agent reported isolated
render/import, conditional discovery/watch, override/empty, repeat-render, and
native CLI checks passing. Those results are trusted here, not independently
rerun or treated as proof of live deployment. No new runtime behavior is supplied
by this proposal.

## Fit the new runtime direction

The [cfr runtime draft](effect-draft2.gpt6a.md#4-shared-init-is-an-extensible-pipeline)
already makes environment initialization visible work and keeps environment in
run data rather than mutating process-global state. Its next section supports
typed fields, revisions, and writer provenance. This proposal specializes that
direction; it does not identify today's audience-action implementation as the
completed new cfr.

Today's action capture stores effective exported env and cwd after setup. It can
preserve a prepared invocation, but cannot recover which values were defaults,
which defaults were replaced, or non-exported values in the calling shell.
Retain that useful transport distinction instead of renaming its env map into
an override/default history it never recorded.

## Selection first

An operation binds a target CONFIG and its named env contribution/projection.
Use the existing exact input list as the authored source of selection. A process
requiring a few build settings does not automatically receive proxy client args,
daemon discovery settings, or every active historical file in env.d.

The new runtime should separately hold:

1. **Selected defaults:** values resolved from selected literal contributions,
   with winning source and enough source/revision information to explain them.
2. **Current values:** the invoking process or shell's observed values for the
   selected keys, including presence. An empty string is not absence.
3. **Prior managed state:** what this same target/session previously applied,
   with ownership and the default/derivation that led to it.
4. **Effective result:** the selected values and per-key resolution reasons.

Keep defaults available even while an override is effective. Re-rendering a
source must not erase the prior comparison baseline for an already-running shell.
Changing a default never requires overwriting the observed current value just to
inspect it.

Compfuzor execution identity remains a separate binding. An application value
called DIR does not change the target CONFIG or command root. Selecting contribution
keys is not equivalent to deleting every unrelated inherited process variable;
the host environment inheritance policy remains explicit and separate.

## What "unchanged from default" can mean

For an already managed key, compare the observed current value with its **last
applied value**, not merely today's newly rendered default. For simple literals
the last applied value equals the previous default. A derived value can differ
from an authored fallback because it was computed using an effective override.

| Observation and recorded ownership | Resolution |
|---|---|
| Managed key still equals its last applied value | Follow the new selected default or recomputed managed value. |
| Managed key differs, including a change to empty/unset | Preserve the local change and mark it as an override. |
| Explicit override was previously recorded | Preserve it until explicitly released, even if it happens to equal a default. |
| No prior state; current key is absent | Apply the selected default and establish managed state. |
| No prior state; current key is present | Preserve it as untracked/current input; equality alone does not prove managed ownership. |
| Previously managed key no longer has a selected default | Report removal; an explicit refresh policy may unset an unchanged managed value, while preserving local overrides. |

Equality is evidence about values, not proof of user intent. Someone explicitly
pinning the current default needs a way to mark an override; someone returning
to managed defaults needs a reset/default operation. Avoid claiming to detect
every edit solely from string comparison.

Presence, override, and management are separate facts. Generic empty handling
should preserve intentional empties. The proxy module's established empty-means-
default behavior is a domain policy to migrate deliberately, not a reason for
every cfr env key to treat empty as unset.

## Defaults remain findable

Proposed views, with CLI spelling still open:

- **defaults:** selected authored/resolved defaults even when overridden;
- **effective:** what this invocation would receive after resolution;
- **changes/explain:** managed/untracked/overridden state, winning source, and
  the reason a key is preserved, refreshed, absent, or removed.

Read-only views do not establish management or advance last-applied state. Advance
that state only when application succeeds. A new child process can receive its
computed environment directly. Updating an existing shell needs a shell-local
bridge that captures selected variables (including unexported ones), applies
quoted changes in that shell, and records the resulting managed baseline there.
A subprocess's process.env cannot accomplish that on its own.

Scope baseline state to the target/config/projection and the particular live
shell or run, rather than a machine-wide map of variable names. Track credential
pointers as selected config; avoid persisting runtime-loaded credential values
as default history. Existing cfr provenance/history is useful for source identity
and decisions, not an excuse to dump whole environments.

## Proxy as the first worked case

Suppose the managed URL and native args originally describe port A. Config now
selects port B:

- If both current values still match their managed values, refresh URL and args
  together to B.
- If the URL is locally changed to C but args remain managed, preserve URL C and
  recompute the managed args from effective C.
- If args are locally changed, preserve them, independently of the URL's status.
- Without prior state, preserve present values and expose the uncertainty; do not
  assume all old nonempty args are user-authored or all are safe to overwrite.

Keep the URL-to-native-args derivation with the OpenCode client domain. Reuse cfr's
selected values and management decisions around it. This does not require putting
arbitrary shell evaluation into the literal ENV parser or designing a universal
dependency language. Native explicit CLI routing still has its existing priority.

## Implementation sequence

1. Expose one selected ENV input set as resolved defaults plus source winners.
   Reuse the existing literal grammar/reduction; do not introduce a divergent
   TypeScript dotenv parser next to the Python processor.
2. Add a pure cfr resolution interface taking defaults, current observations,
   and optional prior managed state. Return effective values, reasons, and the
   proposed next state. Test the table above independently of shell execution.
3. Use the interface in a selected native child invocation. Its env selection
   should be inspectable before launch and kept separate from execution identity.
4. Add a narrow Zsh observation/application bridge for the proxy case. Verify
   unexported variables, empty/unset distinctions, explicit overrides, changes
   between observation/application, and baseline update only after success.
5. Migrate the relevant generated helpers onto selected env bindings. The existing
   envdefault fallback remains predecessor behavior until an actual caller adopts
   the new path; do not deepen its role in the new runtime.

The choice worth settling at the next interface checkpoint is how cfr exposes
explicit override/default ownership and shell-local state. Selectivity and readable
defaults can land before general live-shell refresh or broader fuze traversal.

## Related work

- [Proxy adoption](../fuzings/proxy0.gpt61sol.md): concrete implemented baseline
  and the native runtime derivation this proposal must preserve.
- [Original refresh requirement](../fuzings/contract0.gpt6a.md#intended-opencode-flow):
  earlier prior-default comparison and shell-local state idea; its old routing
  wrapper and port-authority suggestions are superseded by current proxy work.
- [Complete CONFIG and ENV](../../doc/config/definitions.md): actual selected
  input/projection interfaces, separate from proposed managed-state behavior.
- [cfr shared init/run data](effect-draft2.gpt6a.md#4-shared-init-is-an-extensible-pipeline):
  intended runtime home for selection, effective values, and provenance.
