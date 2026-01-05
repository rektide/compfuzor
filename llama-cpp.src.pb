---
- hosts: all
  vars:
    REPO: https://github.com/ggml-org/llama.cpp
    PKGS:
      - libvulkan-dev
      - glslc
    BINS:
      - name: build.sh
        content: |
          cmake -B build -DGGML_VULKAN=1
          cmake --build build --config Release
          #./build/bin/llama-cli -m "PATH_TO_MODEL" -p "Hi you how are you" -ngl 99
  tasks:
    - import_tasks: tasks/compfuzor.includes

