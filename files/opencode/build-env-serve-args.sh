set -euo pipefail

# Rewrite OPENCODE_SERVE_ARGS in env/env.export: the complete `serve`
# argument vector, baked once per build instead of reassembled per boot.
#
# Inputs come from the sourced deployment env: OPENCODE_SERVER_HOSTNAME and
# OPENCODE_SERVER_PORT are playbook-rendered; OPENCODE_SERVER_CORS is the
# comma-separated origin list refreshed by build-env-cors.sh, which the
# compositor runs just before this leaf (BINS order decides within the
# lane). serve.sh word-splits the baked vector into exec argv because
# systemd cannot — ExecStart ${VAR} expansion passes the whole value as a
# single argument.
#
# Drop-in plan: when the opencode-args feature line (~/src/opencode-args)
# is composed and deployed with the serve --password-file flag and
# serve-route environment argument parsing, this vector moves to the
# variable the CLI parses natively, serve.sh is deleted, and the unit
# regains LoadCredential while ExecStart composes the credential path
# itself — systemd expands the %d specifier in ExecStart argv (while
# Environment= cannot compose credential paths), so the unit runs
# `<binary> serve --password-file %d/OPENCODE_PASSWORD`.
#
# The playbook renders the key empty, so an Ansible re-render resets it
# until the next build (or a manual run of this script). Manual runs are
# fine -- restart opencode.service afterwards to apply.

dir=${DIR:?DIR is not set (the generated wrapper normally provides it)}
hostname=${OPENCODE_SERVER_HOSTNAME:?OPENCODE_SERVER_HOSTNAME is not set}
port=${OPENCODE_SERVER_PORT:?OPENCODE_SERVER_PORT is not set}
cors=${OPENCODE_SERVER_CORS:-}

# --publish registers this foreground server as the operator-owned
# mode:"server" entry in the channel's service registration file
# (~/.local/state/opencode/service-local.json under OPENCODE_CHANNEL=local),
# claiming the single local-discovery slot: clients connect natively with no
# OPENCODE_ARGS routing. The register path refuses to replace a live
# registration, so stop any channel-local managed service
# (`opencode service stop`) before restarting the unit with --publish baked,
# or the boot fails and Restart=always crash-loops.
args=(--hostname "$hostname" --port "$port" --publish)
if [[ -n $cors ]]; then
  IFS=',' read -r -a origins <<<"$cors"
  for origin in "${origins[@]}"; do
    [[ -n $origin ]] && args+=(--cors "$origin")
  done
fi

# Hostnames, ports, and origin URLs contain no spaces or shell metacharacters,
# so a plain space join round-trips through serve.sh's word split.
vector=''
for arg in "${args[@]}"; do
  vector+="${vector:+ }${arg}"
done

set_env_key() {
  local file=$1 prefix=$2 value=$3
  [[ -f $file ]] || return 0
  local line="${prefix}OPENCODE_SERVE_ARGS=\"${value}\""
  local tmp
  tmp=$(mktemp)
  awk -v line="$line" '
    /^OPENCODE_SERVE_ARGS=|^export OPENCODE_SERVE_ARGS=/ {
      if (!done) { print line; done = 1 }
      next
    }
    { print }
    END { if (!done) print line }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

set_env_key "$dir/env" '' "$vector"
set_env_key "$dir/env.export" 'export ' "$vector"

printf 'opencode serve args: %s\n' "$vector"
printf 'restart opencode.service to apply\n'
