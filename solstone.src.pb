---
- hosts: all
  vars:
    TYPE: solstone
    INSTANCE: git
    REPO: https://github.com/solpbc/solstone-journal.git
    PYTHON: True
    PYTHON_BUILD_COMMAND: make install
    PYTHON_CONSOLE_SCRIPTS:
      - sol
      - journal
    MISE_VERSIONS:
      uv: latest
    PKGS:
      - ripgrep
      - ffmpeg
      - pipewire
      - gstreamer1.0-tools
      - gstreamer1.0-pipewire
      - pulseaudio-utils
    BINS:
      - name: setup.sh
        content: |
          : "${SOLSTONE_JOURNAL:?Set SOLSTONE_JOURNAL to the journal directory before setup}"
          exec .venv/bin/journal setup "$@"
      - name: modes.sh
        content: |
          cat "$DIR/etc/RUNTIME-MODES.md"
    ETC_FILES:
      - name: RUNTIME-MODES.md
        content: |
          # Solstone runtime modes

          `SOLSTONE_JOURNAL` selects the journal directory. Set it in your shell
          before running `bin/setup.sh`; this playbook does not install global
          `sol` or `journal` wrappers.

          ## Local inference

          Run `mise exec -- uvx solstone check` before enabling Solstone's bundled
          local model. Linux requires a real supported GPU: NVIDIA RTX 30-series+
          uses CUDA; AMD, Intel, and older NVIDIA use the hardware Vulkan driver.
          CPU and software Vulkan devices are rejected for local thinking.

          `solstone-journal` uses CPU ONNX for transcription. The separate
          `solstone-journal-cuda` package uses CUDA for transcription; do not
          install both because they share the `onnxruntime` import directory.

          ## Hosted or host-provided inference

          A journal can instead use one active provider profile: Google AI Studio,
          OpenAI, Anthropic, or an OpenAI-compatible endpoint supplied by the host.
          Configure the provider in Solstone's Thinking UI after setup. Hosted
          calls use the owner's provider key and send only each task's prompt plus
          relevant journal context directly to that provider.
  tasks:
    - import_tasks: tasks/compfuzor.includes
