# Repo jj archive inquiry

## Current toolkit

- [Toolkit design, landed surface](/design/repo-jj-archive/draft1.gpt6sol.md) — composable commands, remote/ghost hardening, Ansible JSON mode, and deferred work. Start here for implementation decisions; the user guide is [`archive/README.md`](/archive/README.md).

## Prior art and evidence

- [Ghost-head incident](/design/repo-jj-archive/incident-ghost-heads.glm53.md) — observed failure and operator repair that motivated preflight and flag-gated healing.
- [Archive subsystem design](/design/repo-jj-archive/draft0.gpt6sol.md) — existing refresh ordering and recovery guarantees retained in the toolkit.
- [Scaffold record](/design/repo-jj-archive/scaffold0.glm53max.md) — source-first launcher and committed bundle before the command refactor.

## Next design boundary

- [Archive deployment premise](/design/archive-deployment-premise/draft0.glm53.md) — separate workspace/per-bookmark-sync direction, intentionally outside this toolkit slice.
