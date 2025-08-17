---
- hosts: all
  vars:
    TYPE: ryujinx
    INSTANCE: git
    REPO: https://git.ryujinx.app/ryubing/ryujinx.git
    ETC_FILES:
      - name: tool-versions
        content: |
          dotnet 9
    BINS:
      - name: build.sh
        content: |
          [ -e .tool-versions ] || ln -s etc/tool-versions .tool-versions
          dotnet build -c Release -o build
  tasks:
    - import_tasks: tasks/compfuzor.includes
