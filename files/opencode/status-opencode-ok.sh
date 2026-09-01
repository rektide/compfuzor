# status-opencode-ok.sh — verify this shell talks to the managed OpenCode V2
# deployment. Linked globally as opencode-status-ok so any shell — including
# ones that never loaded the ZIM wrapper functions — can quickly answer:
#
#   wrapper  is the opencode/opencode2 --server wrapper loaded in the invoking
#            shell? Shell functions are invisible to child processes, so the
#            check reads the wrapper's observable footprint instead: the ZIM
#            module reads the 0600 password file and exports OPENCODE_PASSWORD
#            (the secret itself never reaches env or env.export).
#   global   do the operator-managed global links (install.sh: opencode2,
#            opencode2-node) resolve, agree on version, and point into the
#            composed working workspace instead of a stale checkout?
#   shell    what do opencode/opencode2 resolve to on this shell's PATH, and
#            does that binary match the managed one?
#
# No network: versions come from --version on local binaries only.
#
# Env overrides: OPENCODE_BINARY (managed binary), OPENCODE_GLOBAL_BINS_DIR
# (managed link directory), OPENCODE_WORKING_DIR (deployment workspace).
#
# Exit per status.sh convention: 0 ok, 1 drift, 2 usage.
#
# This is a compfuzor _bin body: files/_bin supplies the shebang,
# `set -euo pipefail`, env loading, and option restoration.

# rendered default kept in its own assignment so the raw (unrendered) source
# stays valid bash: a Jinja default inline in a parameter expansion would have
# its closing brace eaten by bash before Jinja ever renders it
RENDERED_GLOBAL_BINS="{{GLOBAL_BINS_DIR}}"
GLOBAL_BINS="${OPENCODE_GLOBAL_BINS_DIR:-$RENDERED_GLOBAL_BINS}"
MANAGED="${OPENCODE_BINARY:-$GLOBAL_BINS/opencode2}"
WORKING="${OPENCODE_WORKING_DIR:-}"

drift=0
ok() { printf 'ok: %s\n' "$*"; }
bad() { printf 'drift: %s\n' "$*"; drift=1; }
note() { printf 'note: %s\n' "$*"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
usage: status-opencode-ok.sh
  Check the invoking shell against the operator-managed OpenCode V2
  deployment: wrapper loaded, managed global links healthy and current, and
  PATH-resolved opencode/opencode2 at the managed version.
EOF
      exit 0 ;;
    *)
      printf 'status-opencode-ok.sh: unknown option: %s\n' "$1" >&2
      exit 2 ;;
  esac
done

version_of() {
  "$1" --version 2>/dev/null | tail -n 1
}

# the comparable part of a version line ("opencode2 v1.2.3-local-x" -> "v1.2.3-local-x"),
# so binary-name differences between the bun and node builds don't read as drift
version_token() {
  printf '%s\n' "$1" | grep -oE 'v[0-9]+[^ ]*' | tail -n 1 || true
}

realpath_of() {
  realpath -e -- "$1" 2>/dev/null || true
}

# wrapper -------------------------------------------------------------------
if [ -n "${OPENCODE_PASSWORD:-}" ]; then
  ok "wrapper loaded (OPENCODE_PASSWORD exported; routes --server ${OPENCODE_SERVER_URL:-<unset>})"
else
  bad "wrapper not loaded in this shell: OPENCODE_PASSWORD unset; the ZIM module exports it after reading ${OPENCODE_PASSWORD_FILE:-the password file}, and without it opencode/opencode2 skip --server and hit the default world"
fi

# global managed deployment -------------------------------------------------
managed_real="$(realpath_of "$MANAGED")"
managed_version=""
if [ -z "$managed_real" ]; then
  bad "managed binary unavailable: $MANAGED"
else
  managed_version="$(version_of "$managed_real")" || managed_version=""
  ok "managed binary $MANAGED -> $managed_real ($managed_version)"
fi
managed_token="$(version_token "$managed_version")"

for name in opencode2 opencode2-node; do
  link="$GLOBAL_BINS/$name"
  if [ ! -e "$link" ] && [ ! -L "$link" ]; then
    if [ "$name" != opencode2 ]; then
      note "global $name not installed; skipping"
    fi
    continue
  fi
  real="$(realpath_of "$link")"
  if [ -z "$real" ]; then
    bad "global $name is a broken link: $link -> $(readlink "$link" 2>/dev/null || printf '?')"
    continue
  fi
  if [ "$real" != "$managed_real" ]; then
    ver="$(version_of "$real")" || ver=""
    if [ -n "$managed_token" ] && [ "$(version_token "$ver")" != "$managed_token" ]; then
      bad "global $name ($ver) is stale against the managed binary ($managed_version)"
      continue
    fi
    ok "global $name -> $real ($ver)"
  fi
  if [ -n "$WORKING" ]; then
    case "$real" in
      "$WORKING"/*) ;;
      *) bad "global $name escapes the working workspace: $real is not under $WORKING" ;;
    esac
  fi
done

# shell resolution ----------------------------------------------------------
for name in opencode opencode2; do
  resolved="$(command -v "$name" 2>/dev/null || true)"
  if [ -z "$resolved" ]; then
    if [ "$name" = opencode ] && [ -n "${OPENCODE_PASSWORD:-}" ]; then
      note "opencode is not on PATH here; the wrapper function supplies that name in shells that loaded the module"
    else
      bad "$name is not on PATH in this shell"
    fi
    continue
  fi
  real="$(realpath_of "$resolved")"
  if [ -z "$real" ]; then
    bad "$name resolves to a broken link: $resolved"
    continue
  fi
  if [ -n "$managed_real" ] && [ "$real" = "$managed_real" ]; then
    ok "$name -> $real (managed binary)"
    continue
  fi
  ver="$(version_of "$real")" || ver=""
  if [ -z "$managed_version" ]; then
    bad "$name -> $real ($ver) but the managed binary has no version to compare"
  elif [ "$ver" = "$managed_version" ]; then
    note "$name -> $real ($ver) via an unmanaged path"
  else
    bad "$name -> $real ($ver) does not match the managed binary ($managed_version)"
  fi
done

if [ "$drift" = 0 ]; then
  printf 'ok: this shell matches the managed OpenCode V2 deployment\n'
fi
exit "$drift"
