set -euo pipefail
# Resolution order, weakest to strongest:
#   1. rendered profile defaults (src/archive; custom has none)
#   2. CARGO_SWEEP_SRC_ROOT/CARGO_SWEEP_SRC_DAYS or
#      CARGO_SWEEP_ARCHIVE_ROOT/CARGO_SWEEP_ARCHIVE_DAYS (matching profile only;
#      the user units load these from CARGO_SWEEP_ENV_FILE)
#   3. CARGO_SWEEP_ROOT / CARGO_SWEEP_DAYS (any profile; ad-hoc runs)
#   4. --root / --days flags
usage() {
    printf 'Usage: %s {src|archive|custom} [--root PATH] [--days N] [--apply]\n' "$0"
    printf 'Profiles src/archive use rendered defaults; custom requires --root and\n'
    printf -- '--days (or the CARGO_SWEEP_* environment). Env overrides, weakest to\n'
    printf 'strongest: CARGO_SWEEP_{SRC,ARCHIVE}_{ROOT,DAYS} (matching profile only),\n'
    printf 'then CARGO_SWEEP_ROOT/CARGO_SWEEP_DAYS. Flags override all environment.\n'
    printf 'Default is upstream --dry-run --verbose; only explicit --apply deletes.\n'
}
if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then usage; exit 0; fi
case "${1:-}" in
    src)
        profile=src
        def_root={{ CARGO_SWEEP_SRC_ROOT | quote }}
        def_days={{ CARGO_SWEEP_SRC_DAYS | string | quote }}
        profile_env=CARGO_SWEEP_SRC
        ;;
    archive)
        profile=archive
        def_root={{ CARGO_SWEEP_ARCHIVE_ROOT | quote }}
        def_days={{ CARGO_SWEEP_ARCHIVE_DAYS | string | quote }}
        profile_env=CARGO_SWEEP_ARCHIVE
        ;;
    custom)
        profile=custom
        def_root=
        def_days=
        profile_env=
        ;;
    *) usage >&2; exit 2 ;;
esac
shift
apply=false
flag_root=
flag_days=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --apply) apply=true; shift ;;
        --root)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            flag_root=$2; shift 2 ;;
        --root=*) flag_root=${1#--root=}; shift ;;
        --days)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            flag_days=$2; shift 2 ;;
        --days=*) flag_days=${1#--days=}; shift ;;
        *) usage >&2; exit 2 ;;
    esac
done
root=${CARGO_SWEEP_ROOT:-}
days=${CARGO_SWEEP_DAYS:-}
if [ -n "$profile_env" ]; then
    penv_root=${profile_env}_ROOT
    penv_days=${profile_env}_DAYS
    root=${!penv_root:-$root}
    days=${!penv_days:-$days}
fi
root=${flag_root:-$root}
days=${flag_days:-$days}
root=${root:-$def_root}
days=${days:-$def_days}
if [ -z "$root" ] || [ -z "$days" ]; then
    printf 'Missing root or days for profile %s.\n' "$profile" >&2
    usage >&2
    exit 2
fi
case "$days" in
    *[!0-9]*|'')
        printf 'Days must be a positive integer, got: %s\n' "$days" >&2
        exit 2 ;;
esac
if [ "$days" -lt 1 ]; then
    printf 'Days must be >= 1 (refusing an everything-sweep).\n' >&2
    exit 2
fi
if [ ! -d "$root" ]; then
    printf 'Requested sweep root does not exist: %s\n' "$root" >&2
    exit 1
fi
# Canonicalize before the cd below so relative --root values keep working.
root=$(realpath -- "$root")
printf 'sweep: profile=%s root=%s days=%s %s\n' \
    "$profile" "$root" "$days" \
    "$([ "$apply" = true ] && printf -- '--apply' || printf 'dry-run')" >&2
preview=(--dry-run --verbose)
if [ "$apply" = true ]; then preview=(); fi
lock={{ CARGO_SWEEP_LOCK | quote }}
mkdir -p -- "$(dirname -- "$lock")"
exec 9>"$lock"
# Wait rather than discard a persistent catch-up run. This is not a build lock.
flock 9
cd {{ HOMEDIR | quote }}
# Preserve mise's selected Rust environment without unattended installation.
export MISE_AUTO_INSTALL=false MISE_EXEC_AUTO_INSTALL=false RUSTUP_AUTO_INSTALL=0
cargo=$({{ RUST_STORAGE_MISE_BIN | quote }} which cargo --tool rust)
case "$cargo" in
    /*) ;;
    *) printf 'Mise-selected Cargo must be an absolute path: %s\n' "$cargo" >&2; exit 1 ;;
esac
if [ ! -x "$cargo" ]; then
    printf 'Mise-selected Cargo is not executable: %s\n' "$cargo" >&2
    exit 1
fi
# Preserve rustup proxy basename and mise's Rust env; force CARGO after mise env
# evaluation so metadata cannot fall back to an ambient/system Cargo command.
exec {{ RUST_STORAGE_MISE_BIN | quote }} exec --no-deps -- /usr/bin/env "CARGO=$cargo" {{ (BINS_DIR ~ '/cargo-sweep') | quote }} sweep --recursive --hidden --time "$days" "${preview[@]}" -- "$root"
