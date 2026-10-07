# Kanata dial implementation

- [Implementation guide](/doc/input/kanata-dial.md): current operational interfaces and explicit no-live-deployment/readiness gates.
- [Parent offline review](/design/kanata-dial/review0.gpt61s.md): code-reviewed architecture and limits after Sol M's completed integration.
- [Current implementation decisions](/design/kanata-dial/decisions0.gpt61s.md): confirmed 0.003 precision amount and legacy OFF fallback, private control namespace, artifact/audience boundaries, and reset/native-TS review requirements.
- [Implementation brief](/design/kanata-dial/brief0.gpt61s.md): optional media-key contribution, genuine TCP-selected precision, keyboard signaling, fallback, and no-live-deployment checkpoints.

Related: [device-aware Kanata inquiry](/design/kanata-devices/index.md), running independently; this contribution uses existing device-scoped instances rather than waiting for an upstream hack.
