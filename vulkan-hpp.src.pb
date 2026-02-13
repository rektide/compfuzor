---
- hosts: all
  vars:
    TYPE: vulkan-hpp
    INSTANCE: git
    REPO: https://github.com/KhronosGroup/Vulkan-Hpp
    BINS:
      - name: build.sh
        content: |
          mkdir -p build
          cd build
          cmake .. -GNinja
          ninja
  tasks:
    - import_tasks: tasks/compfuzor.includes
