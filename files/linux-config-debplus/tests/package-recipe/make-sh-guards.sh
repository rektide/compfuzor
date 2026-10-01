#!/bin/sh
# Guard matrix for the MAKE.sh package recipe: pin, toplevel, hotfix
# allowance, status failure, and argument count. Self-contained — generates
# recording git+make stubs into a tempdir; no kernel tree, no kernel build.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
MAKE_SH="$HERE/../../MAKE.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/debplus-make-sh-guards.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin"
BIN="$WORK/bin"
PIN=551c722f40809618230001baccf219193e22fc5a
OTHER=1111111111111111111111111111111111111111
export TST_EPOCH=1790733261 TST_ISO=2026-09-29T18:54:21-07:00
fail=0

cat > "$BIN/git" <<'EOF'
#!/bin/sh
# Recording git stub; canned answers from TST_* env.
printf 'git %s\n' "$*" >> "${TST_LOG:?}"
case " $* " in
	*" rev-parse --show-toplevel "*) printf '%s\n' "${TST_TOPLEVEL:-$TST_SRC}"; exit 0 ;;
esac
for a in "$@"; do
	case "$a" in
		HEAD) printf '%s\n' "${TST_HEAD:-}"; exit 0 ;;
		--format=%ct) printf '%s\n' "${TST_EPOCH:?}"; exit 0 ;;
		--format=%cI) printf '%s\n' "${TST_ISO:?}"; exit 0 ;;
		--porcelain)
			[ "${TST_STATUS_FAIL:-0}" = "0" ] || exit 128
			cat "${TST_DIRTY_FILE:-/dev/null}"; exit 0 ;;
	esac
done
case "$*" in
	*cat-file*) exit "${TST_CATFILE:-0}" ;;
esac
echo "STUB-GIT-UNHANDLED: $*" >&2
exit 9
EOF

cat > "$BIN/make" <<'EOF'
#!/bin/sh
# Recording make stub; kernelversion from TST_KVER.
printf 'make cwd=%s %s\n' "$PWD" "$*" >> "${TST_LOG:?}"
last=""
for a in "$@"; do last="$a"; done
if [ "$last" = "kernelversion" ]; then
	printf '%s\n' "${TST_KVER:-7.3.0-rc5}"
	exit 0
fi
printf 'INVOCATION cwd=%s\n' "$PWD" >> "${TST_MAKE_OUT:?}"
exit 0
EOF
chmod +x "$BIN/git" "$BIN/make"

expect_reject() {
	name="$1" rc="$2" pattern="$3"
	if [ "$rc" -eq 0 ]; then
		echo "FAIL $name: expected reject, got success"
		fail=$((fail + 1)); return
	fi
	if grep -q "$pattern" "$WORK/err"; then
		echo "ok   $name"
	else
		echo "FAIL $name: rc=$rc, missing pattern '$pattern' in:"
		sed 's/^/     /' "$WORK/err"
		fail=$((fail + 1))
	fi
}

expect_pass() {
	name="$1" rc="$2" marker="${3:-}"
	if [ "$rc" -ne 0 ]; then
		echo "FAIL $name: expected success, rc=$rc:"
		sed 's/^/     /' "$WORK/err"
		fail=$((fail + 1)); return
	fi
	if [ -n "$marker" ] && ! grep -q "$marker" "$WORK/err"; then
		echo "FAIL $name: success but stderr lacks marker '$marker':"
		sed 's/^/     /' "$WORK/err"
		fail=$((fail + 1)); return
	fi
	echo "ok   $name"
}

mk_export() { # case name, marker content ("" = no marker)
	SRC="$WORK/$1"; mkdir -p "$SRC"
	if [ -n "${2:-}" ]; then
		printf '%s\n' "$2" > "$SRC/.debplus-source-revision"
	fi
}
mk_git() { # case name
	SRC="$WORK/$1"; mkdir -p "$SRC/.git"
}

run() { # case name (SRC already created); extra args go to MAKE.sh
	name="$1"; shift
	: > "$WORK/err"
	rc=0
	PATH="$BIN:$PATH" TST_LOG="$WORK/log" TST_MAKE_OUT="$WORK/make.out" \
		TST_SRC="$SRC" sh "$MAKE_SH" "$SRC" "$@" > "$WORK/out" 2> "$WORK/err" || rc=$?
}

# 1. unmarked plain export
mk_export unmarked ""
run unmarked
expect_reject unmarked "$rc" "unmarked export"

# 2. marked export, wrong revision
mk_export wrongmark "$OTHER"
run wrongmark
expect_reject wrongmark "$rc" "declares base revision"

# 3. marked export, right revision -> passes
mk_export markedok "$PIN"
run markedok
expect_pass markedok "$rc"

# 4. export, wrong kernelversion
mk_export wrongkver "$PIN"
TST_KVER=7.3.0-rc3 run wrongkver
expect_reject wrongkver "$rc" "not kernel 7.3.0-rc5"

# 5. git checkout, HEAD != pin
mk_git wronghead
TST_HEAD="$OTHER" run wronghead
expect_reject wronghead "$rc" "HEAD is not pinned"

# 6. git checkout, SRC is not the physical toplevel
mk_git parentrepo
TST_HEAD="$PIN" TST_TOPLEVEL="$WORK/parentrepo/outer" run parentrepo
expect_reject parentrepo "$rc" "physical root"

# 7. git checkout missing the pin object
mk_git nopin
TST_HEAD="$PIN" TST_CATFILE=1 run nopin
expect_reject nopin "$rc" "lacks pinned commit"

# 8. git checkout at pin, clean -> passes
mk_git cleanpin
TST_HEAD="$PIN" TST_TOPLEVEL="$SRC" run cleanpin
expect_pass cleanpin "$rc"

# 9. dirty = exactly the 4 allowed AMD patch files -> passes, count is 4
mk_git hotfixdirty
printf ' M drivers/gpu/drm/amd/amdgpu/amdgpu.h\n M drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c\n M drivers/gpu/drm/amd/pm/amdgpu_pm.c\n M drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c\n' > "$WORK/dirty"
TST_HEAD="$PIN" TST_TOPLEVEL="$SRC" TST_DIRTY_FILE="$WORK/dirty" run hotfixdirty
expect_pass hotfixdirty "$rc" "NOT pristine/reproducible"
grep -qF 'plus 4 uncommitted hotfix file(s)' "$WORK/err" || { echo "FAIL hotfixdirty: count not 4"; fail=$((fail+1)); }

# 10. dirty includes a file outside the allowance -> refuses
mk_git otherdirty
printf ' M drivers/gpu/drm/amd/pm/amdgpu_pm.c\n M kernel/sched/core.c\n' > "$WORK/dirty"
TST_HEAD="$PIN" TST_TOPLEVEL="$SRC" TST_DIRTY_FILE="$WORK/dirty" run otherdirty
expect_reject otherdirty "$rc" "kernel/sched/core.c"

# 11. foreign AMD file (not one of the 4 patch paths) -> refuses
mk_git foreignamd
printf ' M drivers/gpu/drm/amd/amdgpu/amdgpu.h\n M drivers/gpu/drm/amd/display/amd_gpu_dc.c\n' > "$WORK/dirty"
TST_HEAD="$PIN" TST_TOPLEVEL="$SRC" TST_DIRTY_FILE="$WORK/dirty" run foreignamd
expect_reject foreignamd "$rc" "amd_gpu_dc.c"

# 12. git status itself fails -> refuses, never assumes pristine
mk_git statusfail
TST_HEAD="$PIN" TST_TOPLEVEL="$SRC" TST_STATUS_FAIL=1 run statusfail
expect_reject statusfail "$rc" "git status failed"

# 13. extra positional arguments -> usage refusal
mk_git extraargs
TST_HEAD="$PIN" TST_TOPLEVEL="$SRC" run extraargs /some/other/tree
expect_reject extraargs "$rc" "usage: MAKE.sh"

if [ "$fail" -gt 0 ]; then
	echo "RESULT: $fail FAILURE(S)"
	exit 1
fi
echo "RESULT: all guard cases pass"
