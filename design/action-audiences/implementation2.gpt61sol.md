---
type: ImplementationCheckpoint
title: User-first actions adopted with home-local material defaults
description: Completed representative playbook adoption, invocation-time consumer selectors, persistent SteamOS mixed audiences and isolated placement/native-validation proof.
resource: /design/action-audiences/implementation2.gpt61sol.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-06 }
verified: { by: model:gpt61sol, method: real-playbook-isolated-generation-and-native-validation }
sources:
  - resource: /design/action-audiences/implementation1.gpt61sol.md
    title: Accepted domain implementation and approved next placement primitives
  - resource: /tests/integration/action_placement.test.py
    title: Default placement proof without DIR/ETC/PREFIX_DIR overrides
  - resource: /niri.etc.pb
    title: Home-local Niri host adoption
  - resource: /umbriel.etc.pb
    title: Home-local Umbriel material/receiver separation
  - resource: /media-keys.etc.pb
    title: Pure producer placement and dynamic consumer selection
  - resource: /steamos-niri.opt.pb
    title: Persistent mixed provisioning/user-configuration plans
---

# Outcome

The requested representative repo implementation is complete: general user-first
action families, complete CONFIG/keybinding operations, home-local material defaults,
invocation-time consumer selectors and explicit mixed SteamOS audiences are now
integrated. **No live deployment/desktop/service was migrated, activated, moved or
cleaned up.** No pushes occurred.

This checkpoint supersedes the earlier “placement/adoption pending” boundary, not
the transaction/scope distinctions or the history preserved in prior checkpoints.

# Accepted behavior

| Deployment | Default material | Ordinary interface / available audiences |
|---|---|---|
| Niri consumer | `${XDG_DATA_HOME:-$HOME/.local/share}/compfuzor/etc/niri` | `install.mjs`/`install-user.mjs`; `assemble.mjs`/`assemble-user.mjs`; user receiver only |
| Umbriel consumer | same group, `umbriel` | same user action families; root template/personal fragments staged separately from `.config` receiver |
| Media Keys producer | same group, declared `<NAME>` | `install.mjs`/`install-user.mjs`; actual two-target registration; no fabricated host assembly/system receiver |
| SteamOS Niri | persistent `/opt/steamos-niri-main` | bare/user install configures the user; explicit `install-system.mjs` provisions readonly/packages; only user assembly |
| Vicinae source producer | existing source checkout/deployment unchanged | compatible installers/service policy unchanged; consumer selectors now follow home-local hosts |

The etc-typed declarations use only existing `PREFIX_DIR`, `DIR`, `ETC` and
`BINS_DIR` semantics. PREFIX defaults come from the **target's gathered XDG/HOME
environment**, with HOME fallback; ETC is explicitly bound to DIR. The structural
`DIR/etc` exposure link remains valid. Existing sibling `env.NAME` links remain
inside the same grouped material prefix. No MATERIAL_ROOT API, hierarchy rewrite
or USERMODE flip was introduced.

Receiver roots remain invocation-time XDG config or explicitly declared scoped
roots. Material placement does not choose an audience, grant privilege, invent
compositor fallback behavior or select copy/link/assemble delivery.

Only actual declared plans produce aliases. User-only Niri/Umbriel hosts have no
install-system/assemble-system alias. Media Keys' default target pairs declare only
user audiences. The isolated two-context fixture demonstrates a real system
receiver operation from the **same home-local material**, not a fake fallback.
Shared material alone does not make a system operation appear.

## Consumer selectors and explicit overrides

Media Keys and Vicinae no longer pin consumer deployments under `/etc/opt`:

```yaml
consumer:
  env: COMPFUZOR_NIRI_PROFILE
  default: "${XDG_DATA_HOME}/compfuzor/etc/niri/etc/keybinding-niri.json"
```

Umbriel uses the parallel `COMPFUZOR_UMBRIEL_PROFILE` selector. HOME/XDG resolve at
invocation; no literal rendering-user home is baked into those consumer arguments.
Explicit JSON profile paths select shared/other consumers. Vicinae's build,
source workspace, installed binaries and user-service enablement were not moved,
executed or casually opted into another audience policy.

Shared material remains an ordinary override:

```sh
ansible-playbook -i 'localhost,' -c local niri.etc.pb -e PREFIX_DIR=/etc/opt
export COMPFUZOR_NIRI_PROFILE=/etc/opt/niri/etc/keybinding-niri.json
```

Generation and runtime consumer selection remain separate decisions. The complete
[operator example and deliberate migration steps](/doc/config/keybinding-producers.md#home-local-consumer-and-producer-example)
show adoption first, producer registration and assembly/check without auto reload
or pruning. Existing producer NAME/group changes belong to their declarations;
tests derive that identity instead of imposing a new name.

# Exact changed paths and commits

This final adoption work changed:

- [`niri.etc.pb`](/niri.etc.pb), [`umbriel.etc.pb`](/umbriel.etc.pb),
  [`media-keys.etc.pb`](/media-keys.etc.pb): local defaults and action-mode entrypoints.
- [`vicinae.src.pb`](/vicinae.src.pb): selectors only; build/service policy retained.
- [`steamos-niri.opt.pb`](/steamos-niri.opt.pb): explicit mixed action families,
  persistent material and updated operator instructions.
- [`action_placement.test.py`](/tests/integration/action_placement.test.py): actual
  defaults, full user action, shared/system fixtures and target HOME fallback.
- [`consumer-host test/helper`](/tests/integration/keybindings_consumer_hosts.test.py),
  [`media test`](/tests/integration/keybindings_media_keys.test.py),
  [`SteamOS test`](/tests/integration/keybindings_steamos_niri.test.py),
  [`Vicinae test`](/tests/integration/keybindings_vicinae_proposal.test.py): updated
  assertions/interfaces and verified service/source-render isolation.
- [`doc/actions/README.md`](/doc/actions/README.md),
  [`producer guide`](/doc/config/keybinding-producers.md),
  [`consumer guide`](/doc/config/keybinding-consumers.md),
  [`Noctalia operator example`](/doc/noctalia/README.md), inquiry index and historical
  adoption note: current defaults/usage, distinctions and deliberate migration.

Coherent commits:

- `26a02097` — media home-local declarations/selectors (hunk-selected).
- `872dd0b7` — Niri/Umbriel/Vicinae/SteamOS adoption declarations.
- `367e90d1` — media target HOME/XDG fallback (hunk-selected).
- `9e648cf2` — final target-local placement and isolated adoption/service tests.

The pre-existing media NAME→INSTANCE edit was preserved and excluded from our
commits via full-ID jj-hunk selection/dry runs. Other user source changes were not
discarded or swept into commits. This slice did not change the distributed bundle;
the accepted prior bundle's isolated-registration provenance remains intact.

# Verification and safety

- **Real default placement:** actual playbooks imported into a disposable HOME/XDG,
  without DIR/ETC/BINS_DIR/PREFIX_DIR overrides. Resolved material destinations and
  emitted directories stay under the chosen group; etc structural exposure works.
  Generation leaves receiver configuration absent. Explicit shared override is
  tested separately, not used to bypass the default-placement proof.
- **Full default runtime path:** real hosts run install.mjs, the real producer runs
  its bare install.mjs, both Niri/Umbriel native validation executes, exact durable
  membership/resource counts are checked, and host assemble/check/apply works.
  The staged Umbriel template remains independent from the published live root.
- **Both audiences:** the real Niri profile fixture declares an isolated absolute
  system root; system host install/assembly and producer registration use the same
  home-local material. No real `/etc` receiver is written.
- **Shared selection:** PREFIX_DIR explicitly selects owned shared test material;
  a profile override changes source registration to copy and native placement to
  its declared location. It does not fabricate system receiver availability.
- **HOME fallback:** Node 20.19 test confirms unset XDG_DATA_HOME uses the target's
  disposable HOME, not the controller account's home, and can install/check.
- **SteamOS:** isolated render checks real aliases/bodies; only user configuration
  is executed. systemctl is stubbed. readonly/package/session commands are never
  executed on this workstation; forbidden test commands fail if accidentally called.
- **Vicinae:** declared producer/profile selectors and native outcomes are exercised
  without build/install/service execution. Its render fixture confines/suppresses
  `/usr/share` directories, archive workspaces and source-to-/opt exposure links.
- Modified real consumer/media/SteamOS/Vicinae integrations pass. Final placement
  integration passes under **Node 20.19.0**, including both native targets.
- Syntax-check passes for all five changed playbooks. Prior accepted source suite
  evidence remains 38 Vitest tests, typecheck/lint and domain integration; passing
  suites were not rerun wholesale for YAML/document-only adoption changes.

HOME isolation alone does not isolate the session bus. The shared test environment
now places a recording systemctl stub before system commands, with privileged and
SteamOS session commands denied. This corrects the old integration hazard rather
than assuming a fake HOME prevents service graph mutations.

# Limitations and operator responsibilities

- New repo defaults do not migrate existing live material or reload services.
  Existing input/native files and obsolete trees are not pruned. Migration remains
  explicit, with preserved producer group identity and reviewed references.
- Native validators, Node, jq, block-in-file and Umbriel's separately installed
  read-only baseline remain prerequisites. `.mjs` cannot bootstrap Node itself;
  provisioning/activation is not inferred from audience selection.
- Declaring a system context means a real receiver plan, not automatic privilege
  escalation. The caller still needs the underlying filesystem/service rights.
- Ansible generation can have declared render-side effects outside material for
  other playbooks; a user-default public action is not a global rendering switch.
  The placement proof suppresses package/repo/global-link/service work explicitly.
- Vicinae and other context-selecting service/install domains are not silently
  generalized beyond this approved scope. Their compatible low-level interfaces
  remain available; the shared declaration seam does not claim every arbitrary
  script is audience-safe.

# Cross-references

- [Operator intent](/design/action-audiences/intent0.gpt61sol.md): filename
  consolidation did not approve system-first material placement.
- [Complete domain checkpoint](/design/action-audiences/implementation1.gpt61sol.md):
  binding, selector freezing, typed transaction reuse and invocation cleanup.
- [Historical adoption checkpoint](/design/keybindings/adoption0.glm53.md): original
  render/adoption evidence retained with a succinct supersession note.
- [Maintained actions](/doc/actions/README.md): public interface, actual supported
  aliases and the separation of material, receiver audience and delivery strategy.
