# Kanata source migration

- [Migration intent and ownership checkpoints](/design/kanata-source/brief0.gpt61s.md): source-built TCP capability, scoped Debian replacement, persistent service/account ownership, and separation from input-routing changes.
- [Source build checkpoint](/design/kanata-source/build0.glm53.md): installed binary and TCP flag, parse checks, exact source lineage, package-removal hooks, and boot-prerequisite inventory.
- [Parent handoff decisions](/design/kanata-source/handoff0.gpt61s.md): accepted artifact, canonical service identity, Kanata-owned uinput rule, persistent account, and config-preserving cutover shape.
- [Identity and rollback preflight](/design/kanata-source/preflight0.glm53.md): both configs validate as `_kanata`; scoped previous-artifact backups, config hashes, account IDs, and enable-link topology captured before cutover.
- [Services checkpoint](/design/kanata-source/services0.glm53.md): offline service declarations — canonical same-name unit, single id-less `_kanata` sysusers declarer (existing account untouched, fresh hosts allocate), kanata-owned uinput udev rule, helper retargets, `KANATA_CONFIG_PRESERVE` write-once cutover rerender, scratch-only regression fence; no cutover yet.
- [Live cutover report](/design/kanata-source/cutover0.glm53.md): executed handoff — preserve rerender, owned unit/sysusers/udev publication, `apt remove` (not purge), both instances active on `/usr/local/bin/kanata` 1.12.1-prerelease-1 with configs/account byte-identical; residual manual feel/pedal tests listed.

Related: [Surface Dial precision inquiry](/design/surface-dial-layers/index.md), whose installed-build limitation this migration addresses.
