#!/bin/bash

# MIT License
#
# Copyright (c) 2025 Kristofer Lund
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# via https://github.com/jmpaz/ostt/blob/45336f55/environments/niri/ostt-remote.sh

set -euo pipefail

OSTT_BIN="${OSTT_BIN:-ostt}"
OSTT_CLASS="${OSTT_CLASS:-com.local.ostt}"
OSTT_SOCKET="${OSTT_REMOTE_SOCKET:-${XDG_RUNTIME_DIR:-/tmp}/ostt.sock}"
OSTT_LAUNCH_CMD="${OSTT_LAUNCH_CMD:-ghostty --class ${OSTT_CLASS} -e ${OSTT_BIN} remote}"

ACTION="complete"
OUTPUT_MODE="${OSTT_REMOTE_OUTPUT_MODE:-paste}"

for arg in "$@"; do
  case "$arg" in
  cancel | --cancel)
    ACTION="cancel"
    ;;
  type | typed | manual | --type)
    OUTPUT_MODE="type"
    ;;
  paste | --paste)
    OUTPUT_MODE="paste"
    ;;
  esac
done

has_ostt_window() {
  if command -v niri >/dev/null 2>&1; then
    niri msg -j 2>/dev/null |
      grep -Eq "\"app_id\"[[:space:]]*:[[:space:]]*\"${OSTT_CLASS}\""
  else
    return 1
  fi
}

if has_ostt_window; then
  if [ "${ACTION}" = "complete" ] && [ "${OUTPUT_MODE}" = "type" ]; then
    "${OSTT_BIN}" remote "${ACTION}" type || true
  else
    "${OSTT_BIN}" remote "${ACTION}" || true
  fi
  exit 0
fi

if [ -S "${OSTT_SOCKET}" ]; then
  if "${OSTT_BIN}" remote ping >/dev/null 2>&1; then
    if [ "${ACTION}" = "complete" ] && [ "${OUTPUT_MODE}" = "type" ]; then
      "${OSTT_BIN}" remote "${ACTION}" type || true
    else
      "${OSTT_BIN}" remote "${ACTION}" || true
    fi
    exit 0
  fi
fi

if [ "${ACTION}" = "cancel" ]; then
  exit 0
fi

if [ "${OUTPUT_MODE}" != "paste" ]; then
  exec bash -c "OSTT_REMOTE_OUTPUT_MODE=${OUTPUT_MODE} ${OSTT_LAUNCH_CMD}"
else
  exec bash -c "${OSTT_LAUNCH_CMD}"
fi
