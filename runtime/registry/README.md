# Rendezvous registry library

The library observes owner declarations, not accepted native membership. Producers
and consumers keep manifests/profiles in their own deployments. Rendezvous entries
are symlinks to those exact descriptors; the registry never copies their payloads.

```ts
import { keybindingConsumers } from "../keybindings/registry.ts";
import { registryPolicy } from "./policy.ts";
import { inspectRegistry, lookup } from "./read.ts";
import { register } from "./register.ts";

const policy = registryPolicy(keybindingConsumers.collection, "user", { ...process.env });
await register({ domain: keybindingConsumers, policy, source: "/owned/consumer.json" });
const snapshot = await inspectRegistry(keybindingConsumers, policy);
const receiver = lookup(snapshot, "deck-main"); // identity is not its native adapter
```

[`Domain<T>`](/runtime/registry/model.ts) supplies collection, decoding, identity,
participation and optional audience. The shared reader consumes Figments inventory,
whole-definition resolution and captured winner loading through
[`runtime/discovery/figments.ts`](/runtime/discovery/figments.ts). JSON inspection
retains root reports, every identity observation, conflict layers, payload errors
and independently retained storage/participation facts.

## Root and state policy

[`registryPolicy()`](/runtime/registry/policy.ts) binds the invocation environment.
User precedence is low-to-high: reversed XDG data roots, then root-major reversed
XDG config roots (each root's definitions followed by its mask layer). A higher
config declaration overrides a lower config mask; the local mask still wins.
Collections are safe domain-grouped relative `.d` paths, including `keybindings/providers.d`,
`keybindings/consumers.d`, and `zim/providers.d`; mask siblings use `.mask.d`.
Registration writes only the user XDG data-home collection. System scope ignores
HOME/XDG and uses explicit `/compfuzor/system/<collection>` system locations,
separate from shared user offers in XDG_DATA_DIRS; no automatic sudo is performed.
This default layout remains a policy proposal for generator cutover.

`explicitPolicy(scope, roots, writeRoot)` replaces defaults. Paths must be absolute,
writeRoot must occur in roots, and repeated roots retain their last occurrence.
Missing optional roots remain visible; failed roots make the snapshot incomplete,
block lookup and registration, and make CLI list exit 2.

- `.json.disabled` retains a definition but excludes ordinary participation.
- Payload `enabled:false` is independently retained; it can disable an active slot.
- A higher `/dev/null` symlink masks an identity without removing its definitions.
- Higher disabled/invalid definitions never fall through or field-merge with lower ones.
- Same-layer alternate slots conflict. IDs are literal safe stems, including dots.

## Registration and status

[`planRegistration()`](/runtime/registry/register.ts) emits a disposition, exact
source/destination, participation, observation guard, and ordinary LINKS v1 material.
`register()` replans immediately before delivering via existing LINKS primitives.
Current owner references are no-ops; disabled filename slots and their spelling
are retained. A new initially disabled descriptor uses a disabled slot. Operator
regular files or references to another owner are blocked rather than overwritten.
Higher masks/overrides do not block passive lower owner publication. Plans expose
local `disposition`/`participation` and independent pre-publication `effective.state`.
A mask occupying the writable slot produces blocked material with no links;
registration never unmasks. Execution policy, unlike publication, must reject masks.
Changing an owner locator across an existing slot currently requires explicit
operator action; no inferred ownership permits retargeting.

These are best-effort observation guards, not locks or immutable payload snapshots.
Captured reads do not rescan or widen membership, but bytes are read at load time.
Native admission must add its own selection/content guards before publication.

## CLI and checks

```sh
node runtime/cli/registry.ts list --collection keybinding-consumers --scope user --json
node runtime/cli/registry.ts explain deck-main --collection keybinding-consumers --scope user
node runtime/cli/registry.ts register --source /owned/consumer.json --collection keybinding-consumers --scope user
node runtime/cli/registry.ts status --source /owned/consumer.json --collection keybinding-consumers --scope user
node files/runtime/compfuzor-runtime.ts registry --help
pnpm exec vitest run tests/registry-discovery/registry.test.ts
pnpm check
```

Use repeated `--root /absolute/path` and `--write-root /absolute/path` for isolated
commands instead of live XDG paths. `complete --word explain --word ''` exposes
tab completion against an observed snapshot; it currently provides static verbs,
collection/scope values and explain IDs. `complete -- WORDS` uses tab's normal
protocol; `complete bash|zsh|fish|powershell` prints setup without installing it.

Source imports require the installed `figmen-ts` sibling link and its source tree;
no absolute checkout paths are embedded in production imports. The committed
deployment artifact now bundles Figments, confbox, Router and tab alongside the
existing native/CONFIG closure; no receiver-side sibling checkout or node_modules
is required. Source development still uses `.ts` entries.

See the [library predecessor](/design/registry-discovery/implementation0.gpt61s.md)
and [generated/native checkpoint](/design/registry-discovery/implementation1.gpt61s.md)
for domain schemas, evidence and remaining integration decisions.

## Advertised keybinding execution

```sh
node files/runtime/compfuzor-runtime.ts keybindings install-offer --manifest /owned/keybinding-producer.json
node files/runtime/compfuzor-runtime.ts keybindings install-offer --manifest /owned/keybinding-producer.json --target deck-main --force-enable
node files/runtime/compfuzor-runtime.ts registry complete bash
node files/runtime/compfuzor-runtime.ts keybindings complete bash
```

[`admitKeybindingBatch()`](/runtime/keybindings/invocation.ts) admits all compatible
active consumers by default or a declared/CLI subset. Disabled registration slots
and `enabled:false` metadata require `--force-enable` for explicit selection and
are otherwise skipped in default collection. Force is invocation-only, remains in
serialized admission, never removes masks, and does not enable consumer-owned
producer groups or individual actions/bindings.

Consumer profile selectors reuse [`PathSelector`](/files/config/context.ts), with
inert shape validation during inspection and binding only after selection. Relative
selectors/defaults bind against the owned descriptor's physical directory. Native
adapter/schema/audience/profile checks still apply under force.

The complete receiver IDs, profiles, roots, manifest/resources and guards are bound
before authored action bodies. Each receiver retains its existing independent
CONFIG membership/native commit. Selected registry topology and captured input
bytes are checked before execution and around native transaction validation.
Ordinary producer install publishes its prospective owned manifest reference, then
executes the frozen receiver batch. Ordinary owned-host install can bind its packaged
description prospectively and publishes its reference after successful native work;
assemble/check does not advertise. Separate generated registration endpoints support
passive publication while native work is disabled, masked or not yet installed.
