# pstore-dump.sh -- pretty-print crash records captured by the pstore backend.
#
# After a panic/oops the active pstore backend (ramoops here) flushes the trace to
# /sys/fs/pstore as <type>-<backend>-<N> files (dmesg-ramoops-0, pmsg-ramoops-0,
# console-ramoops-0, ...). This lists each record with a header and prints its
# contents -- the human-readable readout you want after a crash-test
# (pstore.etc.pb README "Crash-testing"). Steady state is empty; non-empty means a
# dump was captured and awaits inspection/clear.
#
# Complements status-ramoops.sh (which checks clean backend registration) and
# status-dirs.sh (which surfaces /sys/fs/pstore as generic TSV). This is the
# focused readout for "what did we capture?".
#
# /sys/fs/pstore is root-only (drwxr-x---); reads use sudo when not root.
# Override the directory with PSTORE_DIR=...
#
# This is a compfuzor _bin body: files/_bin supplies the shebang,
# `set -euo pipefail`, env loading, and option restoration.
#
# Exit: 0 if empty (healthy steady state), 1 if records present (a crash was
# captured), 2 on usage/read error.

PSTORE_DIR="${PSTORE_DIR:-/sys/fs/pstore}"

# /sys/fs/pstore is drwxr-x--- root root; mirror status-dirs.sh's sudo-vs-user
# split so this works whether or not you remembered to sudo.
if [ "$(id -u)" -eq 0 ]; then
  _cat() { cat "$1"; }
  _ls() { ls -1 "$1"; }
else
  _cat() { sudo cat "$1"; }
  _ls() { sudo ls -1 "$1"; }
fi

if ! _entries="$(_ls "$PSTORE_DIR" 2>/dev/null)"; then
  printf 'pstore-dump.sh: cannot read %s (run as root?)\n' "$PSTORE_DIR" >&2
  exit 2
fi

# count non-blank lines (ls -1 gives one entry per line)
_n=$(printf '%s\n' "$_entries" | grep -c . || true)
if [ "$_n" -eq 0 ]; then
  printf '%s: empty -- no crash records (healthy steady state)\n' "$PSTORE_DIR"
  exit 0
fi

printf '=== %s: %s record(s) ===\n\n' "$PSTORE_DIR" "$_n"

printf '%s\n' "$_entries" | while IFS= read -r _f; do
  [ -n "$_f" ] || continue
  # filename shape: <type>-<backend>-<id>  (dmesg-ramoops-0, pmsg-ramoops-0, ...)
  _type="${_f%%-*}"
  printf '%s\n' "--- $_f ---"
  printf 'type: %s\n' "$_type"
  printf '%s\n' '----'
  # contents may look like garbage if the kernel was built with PSTORE_COMPRESS;
  # default ramoops dmesg records are plain text.
  _cat "$PSTORE_DIR/$_f" 2>/dev/null || printf '(unreadable)\n'
  printf '%s\n' ''
done

printf 'clear with: sudo rm %s/*\n' "$PSTORE_DIR"
exit 1
