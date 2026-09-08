# Consumer config: current implementation and design history

The consumer toolkit is implemented and tested in isolated deployments. It has
**not been deployed to the live Zim/Mise installation**.

The implemented default is **linked donor drop-in files, locally assembled
configuration**. Copying drop-ins and copying/linking whole donor outputs remain
explicit alternatives. User input choices stay local; canonical donor
administration is a separate operation. CONFIGS reuses one assembly engine and
shares file-delivery primitives with LINKS. Zim's shell-loader blocks remain
separate, and Mise gains block status without an unnecessary assembly layer.

## Start here

- [User workflow](/doc/config/consumer-toolkit.md): declarations, full initial
  setup, daily assembly, input management, copy/link alternatives, and Mise.
- [Latest implementation checkpoint](/.design/config-user-target/build4.solx.md):
  review fixes, exact verification results, limitations, and preserved demo.
- [Final architectural review](/.design/config-user-target/review-final0.unknown.md):
  independent standards/spec review resolutions and the two remaining unrelated
  OpenCode test failures.
- [Architectural assessment](/.design/config-user-target/assessment0.unknown.md):
  why consumer-specific configuration, delivery, and execution scope should not
  become separate system/user implementations.

## Implementation checkpoints

Work proceeded through one Sol implementation agent with parent code review
between consequential steps:

- [Build 1](/.design/config-user-target/build1.solx.md): bind reusable CONFIGS
  recipes to runtime consumer inputs and outputs.
- [Build 2](/.design/config-user-target/build2.solx.md): seed, refresh, copy/link,
  local input operations, status, and shared LINKS delivery.
- [Build 2 review](/.design/config-user-target/build2-review0.solx.md): system
  composition, reporter semantics, accurate diagnostics, and Zim migration plan.
- [Build 3](/.design/config-user-target/build3.solx.md): Zim donor/consumer split,
  independent loaders and caches, and Mise Bash-block status.
- [Build 4](/.design/config-user-target/build4.solx.md): review corrections,
  deployment-rooted orchestration, shared runtime packaging, and test sweep.

The [initial build brief](/.design/config-user-target/build0.unknown.md) is a
proposal retained for history, not a second specification to implement.

## Background and superseded proposals

- [Original human brief](/.design/config-user-target/brief.glm53.md): the
  assemble-into-user direction and earlier comparison/scope decisions.
- [Historical status handoff](/.design/config-user-target/status.glm53.md): the
  original Zim/Mise incident and pre-build state. Its draft3 authority and
  pending implementation list were superseded by the later assessment/build.
- [Draft 2](/.design/config-user-target/draft2.solx.md): earlier direct/canonical
  assembly and target contracts.
- [Draft 3](/.design/config-user-target/draft3.solx.md): earlier broad strategy
  toolkit proposal. Its whole-copy-first Zim rollout and complete 16-step plan
  are **not** the current implementation direction. In particular, global-bin
  migration, universal artifact targets, and historical three-way evidence
  were not silently included in this build.
