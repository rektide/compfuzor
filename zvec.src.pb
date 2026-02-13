---
- hosts: all
  vars:
    REPO: https://github.com/alibaba/zvec
    BINS:
    CMAKE: True
    CMAKE_ARGS: "-DCMAKE_POLICY_VERSION_MINIMUM=3.10"
    VAR_FILES:
      - name: fix.patch
    BINS:
      - name: build.sh
        content: |
          git apply fix.patch 
  tasks:
    - import_tasks: tasks/compfuzor.includes

