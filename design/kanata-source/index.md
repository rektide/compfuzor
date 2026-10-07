# Kanata source migration

- [Migration intent and ownership checkpoints](/design/kanata-source/brief0.gpt61s.md): source-built TCP capability, scoped Debian replacement, persistent service/account ownership, and separation from input-routing changes.
- [Source build checkpoint](/design/kanata-source/build0.glm53.md): installed binary and TCP flag, parse checks, exact source lineage, package-removal hooks, and boot-prerequisite inventory.
- [Parent handoff decisions](/design/kanata-source/handoff0.gpt61s.md): accepted artifact, canonical service identity, Kanata-owned uinput rule, persistent account, and config-preserving cutover shape.
- [Services checkpoint](/design/kanata-source/services0.glm53.md): offline service declarations — canonical same-name unit, single `_kanata` sysusers owner with pinned 990:985, kanata-owned uinput udev rule, helper retargets, scratch-only regression fence; no cutover yet.

Related: [Surface Dial precision inquiry](/design/surface-dial-layers/index.md), whose installed-build limitation this migration addresses.
