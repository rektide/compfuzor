---
- hosts: all
  vars:
    REPO: https://github.com/QuentinFuxa/WhisperLiveKit
    BINS:
      - name: build.sh
        content: |
          uv venv
          uv pip install -e /usr/local/src/faster-whisper-git  # local faster-whisper
          uv pip install -e .                                   # whisper-live-kit
      - name: wlk
        content: |
          . .venv/bin/activate
          wlk $*
      - name: whisperlivekit-server
        content: |
          . .venv/bin/activate
          whisperlivekit-server $*
  tasks:
    - import_tasks: tasks/compfuzor.includes
