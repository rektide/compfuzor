# dump-pstore.sh -- pretty-print crash records captured by the pstore backend.
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
# systemd-pstore normally moves records to /var/lib/systemd/pstore during early
# boot, so both locations are inspected. Override them with PSTORE_DIR and
# PSTORE_ARCHIVE_DIR.
#
# This is a compfuzor _bin body: files/_bin supplies the shebang,
# `set -euo pipefail`, env loading, and option restoration.
#
# Exit: 0 if empty (healthy steady state), 1 if records present (a crash was
# captured), 2 on usage/read error.

PSTORE_DIR="${PSTORE_DIR:-/sys/fs/pstore}"
PSTORE_ARCHIVE_DIR="${PSTORE_ARCHIVE_DIR:-/var/lib/systemd/pstore}"

# Prefer an unprivileged read for test fixtures and permissive installations,
# then fall back to sudo for the normal root-only pstore locations.
_cat() { cat "$1" 2>/dev/null || sudo cat "$1"; }
_find_live() {
  find "$PSTORE_DIR" -maxdepth 1 -type f -print 2>/dev/null \
    || sudo find "$PSTORE_DIR" -maxdepth 1 -type f -print
}
_find_archive() {
  find "$PSTORE_ARCHIVE_DIR" -type f -print 2>/dev/null \
    || sudo find "$PSTORE_ARCHIVE_DIR" -type f -print
}

if ! _live="$(_find_live 2>/dev/null)"; then
  printf 'dump-pstore.sh: cannot read %s (run as root?)\n' "$PSTORE_DIR" >&2
  exit 2
fi
_archive=""
if [ -d "$PSTORE_ARCHIVE_DIR" ]; then
  if ! _archive="$(_find_archive 2>/dev/null)"; then
    printf 'dump-pstore.sh: cannot read %s (run as root?)\n' "$PSTORE_ARCHIVE_DIR" >&2
    exit 2
  fi
fi
_entries="$(printf '%s\n%s\n' "$_live" "$_archive" | grep -v '^$' || true)"

# Count non-blank paths from the live and archived stores.
_n=$(printf '%s\n' "$_entries" | grep -c . || true)
if [ "$_n" -eq 0 ]; then
  printf 'no crash records in %s or %s\n' "$PSTORE_DIR" "$PSTORE_ARCHIVE_DIR"
  exit 0
fi

printf '=== pstore: %s live/archived record(s) ===\n\n' "$_n"

printf '%s\n' "$_entries" | while IFS= read -r _f; do
  [ -n "$_f" ] || continue
  # filename shape: <type>-<backend>-<id>  (dmesg-ramoops-0, pmsg-ramoops-0, ...)
  _name="${_f##*/}"
  _type="${_name%%-*}"
  printf '%s\n' "--- $_f ---"
  printf 'type: %s\n' "$_type"
  printf '%s\n' '----'
  # contents may look like garbage if the kernel was built with PSTORE_COMPRESS;
  # default ramoops dmesg records are plain text.
  _cat "$_f" 2>/dev/null || printf '(unreadable)\n'
  printf '%s\n' ''
done

printf 'live records can be cleared with: sudo rm %s/*\n' "$PSTORE_DIR"
exit 1
