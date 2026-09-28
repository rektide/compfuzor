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
# is composed and deployed with OPENCODE_PASSWORD_FILE support, this vector
# moves to the variable the CLI parses natively, serve.sh is deleted, and
# ExecStart composes the credential path itself — systemd expands
# ${CREDENTIALS_DIRECTORY} in ExecStart argv (not in Environment=), so the
# unit runs `/usr/bin/env
# OPENCODE_PASSWORD_FILE=${CREDENTIALS_DIRECTORY}/OPENCODE_PASSWORD
# <binary> serve`.
#
# The playbook renders the key empty, so an Ansible re-render resets it
# until the next build (or a manual run of this script). Manual runs are
# fine -- restart opencode.service afterwards to apply.

dir=${DIR:?DIR is not set (the generated wrapper normally provides it)}
hostname=${OPENCODE_SERVER_HOSTNAME:?OPENCODE_SERVER_HOSTNAME is not set}
port=${OPENCODE_SERVER_PORT:?OPENCODE_SERVER_PORT is not set}
cors=${OPENCODE_SERVER_CORS:-}

args=(--hostname "$hostname" --port "$port")
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
