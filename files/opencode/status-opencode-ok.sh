# status-opencode-ok.sh — verify this shell talks to the managed OpenCode V2
# deployment. Linked globally as opencode-status-ok so any shell — including
# ones that never loaded the client-env ZIM module — can quickly answer:
#
#   client   is the 0600 credential available (exported by the ZIM module
#            or readable through the pointer), and does the --publish
#            discovery registration reference this deployment's port?
#   global   do the operator-managed global links (install.sh: opencode,
#            opencode2-node) resolve, agree on version, and point into the
#            composed working workspace instead of a stale checkout?
#   shell    what does opencode resolve to on this shell's PATH, and
#            does that binary match the managed one?
#
# No network: versions come from --version on local binaries only; the
# registration is checked by grepping the discovery file, never by
# contacting the server or printing the file (it holds the password).
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
MANAGED="${OPENCODE_BINARY:-$GLOBAL_BINS/opencode}"
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
  deployment: client credential available and discovery registration
  present, managed global links healthy and current, and PATH-resolved
  opencode at the managed version.
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

# client credential ---------------------------------------------------------
if [ -n "${OPENCODE_PASSWORD:-}" ]; then
  ok "client credential exported (OPENCODE_PASSWORD)"
elif [ -r "${OPENCODE_PASSWORD_FILE:-}" ]; then
  ok "client credential readable through OPENCODE_PASSWORD_FILE (${OPENCODE_PASSWORD_FILE})"
else
  bad "client credential unavailable: OPENCODE_PASSWORD unset and OPENCODE_PASSWORD_FILE unreadable; source the opencode-client-args ZIM module"
fi

# discovery registration -----------------------------------------------------
# service-local.json holds the password: grep it, never print it.
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/opencode"
registration="$state_dir/service-local.json"
reg_port="${OPENCODE_SERVER_PORT:-49373}"
if [ -r "$registration" ]; then
  if grep -q '"mode":"server"' "$registration" 2>/dev/null \
     && grep -q ":${reg_port}\"" "$registration" 2>/dev/null; then
    ok "discovery registration present for port ${reg_port} (${registration})"
  else
    bad "discovery registration does not reference port ${reg_port}: ${registration}"
  fi
else
  bad "no discovery registration at ${registration}: clients without an explicit --server would spawn the stock managed service"
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

for name in opencode opencode2-node; do
  link="$GLOBAL_BINS/$name"
  if [ ! -e "$link" ] && [ ! -L "$link" ]; then
    if [ "$name" != opencode ]; then
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
for name in opencode; do
  resolved="$(command -v "$name" 2>/dev/null || true)"
  if [ -z "$resolved" ]; then
    bad "$name is not on PATH in this shell"
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
