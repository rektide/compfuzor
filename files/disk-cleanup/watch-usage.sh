#!/bin/bash
# Hourly / free-space sampler for disk-cleanup's watch-usage timer.
# One line per run — ISO timestamp + `df -m /` numbers (1MiB blocks) —
# appended to a state log and echoed to stdout (journald captures it).
# Read-only: no deletion path anywhere in this bin. The log self-rotates
# at 10 MiB, keeping a single `.1` generation, so an always-on hourly
# timer cannot grow it unbounded (~0.9 MiB/year otherwise).
set -euo pipefail
log_dir=${XDG_STATE_HOME:-$HOME/.local/state}/disk-cleanup
log=$log_dir/usage.log
mkdir -p -- "$log_dir"
if [ -f "$log" ] && [ "$(stat -c %s -- "$log")" -gt 10485760 ]; then
    mv -f -- "$log" "$log.1"
fi
line="$(date -Is) $(df -m --output=source,size,used,avail,pcent,target / | tail -n 1)"
printf '%s\n' "$line" | tee -a -- "$log"
