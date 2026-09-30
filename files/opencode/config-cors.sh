# config-cors.sh — regenerate this host's CORS origins as server config.
#
# The serve unit carries no --cors flags. With none given, `opencode serve`
# falls back to the top-level `cors` array in the assembled opencode.json
# (cli server-process: options.cors ?? config.cors). This bin computes the
# origins from live host state — <short hostname>.local plus every name
# from `hostname -A`, trailing dots stripped, deduplicated in first-seen
# order, each http://<name>:<server port> — writes them to the host-owned
# etc_d/cors.json fragment (deliberately not a playbook ETC_FILES entry:
# Ansible re-renders never touch it), and reassembles the config recipe.
#
# New origins apply on the next server start: pass --restart to restart
# the unit here, or run bin/restart.sh yourself. localhost/127.0.0.1
# origins are always allowed by the server and never need listing.
#
# Env: DIR (deployment root), OPENCODE_SERVER_PORT (origin port),
# OPENCODE_UNIT (unit to restart). The generated wrapper normally
# provides all three.
#
# This is a compfuzor _bin body: files/_bin supplies the shebang,
# `set -euo pipefail`, env loading, and option restoration.

set -euo pipefail

dir=${DIR:?DIR is not set (the generated wrapper normally provides it)}
port=${OPENCODE_SERVER_PORT:-{{OPENCODE_SERVER_PORT}}}
unit="${OPENCODE_UNIT:-{{OPENCODE_UNIT}}.service}"

restart=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --restart) restart=1 ;;
    -h|--help)
      cat <<'EOF'
usage: config-cors.sh [--restart]

Regenerate etc_d/cors.json from this host's live names (<short>.local plus
hostname -A, deduped first-seen, trailing dots stripped), reassemble the
server config, and optionally restart the unit to apply. The server reads
the config `cors` array because its ExecStart passes no --cors flags.
EOF
      exit 0 ;;
    *)
      printf 'config-cors.sh: unknown option: %s\n' "$1" >&2
      exit 2 ;;
  esac
  shift
done

names=()
short=$(hostname -s 2>/dev/null || true)
if [ -n "$short" ]; then
  names+=("${short}.local")
fi
for name in $(hostname -A 2>/dev/null || true); do
  name=${name%.}
  if [ -n "$name" ]; then
    names+=("$name")
  fi
done

declare -A seen=()
items=''
count=0
for name in "${names[@]}"; do
  [ -n "${seen[$name]+x}" ] && continue
  case "$name" in
    *[!A-Za-z0-9.-]*)
      printf 'config-cors.sh: refusing to encode host name needing JSON escaping: %s\n' "$name" >&2
      exit 1 ;;
  esac
  seen[$name]=1
  items+="${items:+, }\"http://${name}:${port}\""
  count=$((count + 1))
done

etc_d="$dir/etc/etc_d"
fragment="$etc_d/cors.json"
mkdir -p "$etc_d"
tmp=$(mktemp)
printf '{\n  "cors": [%s]\n}\n' "$items" >"$tmp"
mv "$tmp" "$fragment"
printf 'config-cors: wrote %d origins to %s\n' "$count" "$fragment"

"$dir/bin/config-assemble.sh" opencode

if [ "$restart" -eq 1 ]; then
  systemctl --user restart "$unit"
  printf 'config-cors: restarted %s\n' "$unit"
else
  printf 'config-cors: restart %s to apply (or rerun with --restart)\n' "$unit"
fi
