#!/usr/bin/env bash
set -euo pipefail
root=$(realpath "$(dirname "$0")/../../..")
cd "$root"
for variant in native one-shot command-layer; do
  play="kinesis/kanata/smartset/$variant.srv.pb"
  ansible-playbook "$play" --syntax-check
  ansible-playbook -i 'localhost,' -c local "$play" \
    -e @kinesis/kanata/shared/render-only.yaml
done
python3 kinesis/kanata/shared/tests/check-rendered.py
