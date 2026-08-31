set -euo pipefail

# Rewrite OPENCODE_SERVER_CORS in env/env.export from live host names.
#
# The playbook renders the key empty; build.sh runs this before the bun build
# so every build refreshes the server's CORS origins without an Ansible pass.
# Origins: <short hostname>.local plus every name from hostname -A, trailing
# dots stripped, deduplicated in first-seen order, each http://<name>:<port>,
# comma-separated. serve.sh expands each origin into a repeatable --cors flag;
# an empty value means no flags. Manual runs are fine too -- restart
# opencode.service afterwards to apply.

dir=${DIR:?DIR is not set (the generated wrapper normally provides it)}
port=${OPENCODE_SERVER_PORT:-49373}

names=()
short=$(hostname -s 2>/dev/null || true)
if [[ -n $short ]]; then
  names+=("${short}.local")
fi
for name in $(hostname -A 2>/dev/null || true); do
  name=${name%.}
  if [[ -n $name ]]; then
    names+=("$name")
  fi
done

declare -A seen=()
origins=()
for name in "${names[@]}"; do
  if [[ -z ${seen[$name]+x} ]]; then
    seen[$name]=1
    origins+=("http://${name}:${port}")
  fi
done

csv=''
csv=$(IFS=,; printf '%s' "${origins[*]}")

set_env_key() {
  local file=$1 prefix=$2 value=$3
  [[ -f $file ]] || return 0
  local line="${prefix}OPENCODE_SERVER_CORS=\"${value}\""
  local tmp
  tmp=$(mktemp)
  awk -v line="$line" '
    /^OPENCODE_SERVER_CORS=|^export OPENCODE_SERVER_CORS=/ {
      if (!done) { print line; done = 1 }
      next
    }
    { print }
    END { if (!done) print line }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

set_env_key "$dir/env" '' "$csv"
set_env_key "$dir/env.export" 'export ' "$csv"

if [[ -n $csv ]]; then
  printf 'opencode CORS origins: %s\n' "$csv"
else
  printf 'opencode CORS origins: none discovered; OPENCODE_SERVER_CORS cleared\n'
fi
printf 'restart opencode.service to apply\n'
