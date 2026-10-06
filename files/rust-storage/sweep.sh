set -euo pipefail
usage() {
    printf 'Usage: %s {src|archive} [--apply]\nDefault: upstream --dry-run --verbose. --apply deletes.\n' "$0"
}
if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then usage; exit 0; fi
case "${1:-}" in
    src) root={{ CARGO_SWEEP_SRC_ROOT | quote }}; days={{ CARGO_SWEEP_SRC_DAYS | string | quote }} ;;
    archive) root={{ CARGO_SWEEP_ARCHIVE_ROOT | quote }}; days={{ CARGO_SWEEP_ARCHIVE_DAYS | string | quote }} ;;
    *) usage >&2; exit 2 ;;
esac
shift
preview=(--dry-run --verbose)
if [ "${1:-}" = --apply ]; then preview=(); shift; fi
if [ "$#" -ne 0 ]; then usage >&2; exit 2; fi
if [ ! -d "$root" ]; then
    printf 'Requested sweep root does not exist: %s\n' "$root" >&2
    exit 1
fi
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
exec {{ RUST_STORAGE_MISE_BIN | quote }} exec --no-deps -- /usr/bin/env "CARGO=$cargo" {{ (BINS_DIR ~ '/cargo-sweep') | quote }} sweep --recursive --time "$days" "${preview[@]}" -- "$root"
