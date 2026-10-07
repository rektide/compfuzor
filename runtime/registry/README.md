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
User precedence is low-to-high: reversed XDG data roots, reversed XDG config roots,
then reversed config mask roots. Collections are `keybindings/providers.d`,
`keybindings/consumers.d`, and `zim/providers.d`; mask siblings use `.mask.d`.
Registration writes only the user XDG data-home collection. System scope ignores
HOME/XDG and uses explicit system locations; no automatic sudo is performed.
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
Effective masks produce blocked material with no links; registration never unmasks.
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
collection/scope values and explain IDs, not installed shell scripts.

Source imports require the installed `figmen-ts` sibling link and its source tree;
no absolute checkout paths are embedded in production imports. The existing
deployed `.mjs` bundle has **not** been cut over. Dependency-closure bundling belongs
to the next deployment slice.

See the [implementation checkpoint](/design/registry-discovery/implementation0.gpt61s.md)
for domain schemas, evidence and remaining native-integration decisions.
