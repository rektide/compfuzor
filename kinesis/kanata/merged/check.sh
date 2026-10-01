#!/usr/bin/env bash
set -euo pipefail
root=$(realpath "$(dirname "$0")/../../..")
cd "$root"
play=kinesis/kanata/merged/keyboard-pedal.srv.pb
ansible-playbook "$play" --syntax-check
ansible-playbook -i 'localhost,' -c local "$play" \
  -e @kinesis/kanata/shared/render-only.yaml
python3 kinesis/kanata/shared/tests/check-rendered.py b-merged
