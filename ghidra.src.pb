---
- hosts: all
  vars:
    REPO: https://github.com/NationalSecurityAgency/ghidra
    PKGS:
      - default-jdk
    BINS:
      - name: build.sh
        basedir: repo
        content: |
          ./gradlew -I gradle/support/fetchDependencies.gradle && ./gradlew assembleAll -x ip
      - name: ghidraRun
        global: True
        content: |
          exec "$(ls -d "$DIR/repo/build/dist/ghidra_*/" | head -1)ghidraRun" "$@"
      - name: analyzeHeadless
        global: True
        content: |
          exec "$(ls -d "$DIR/repo/build/dist/ghidra_*/" | head -1)support/analyzeHeadless" "$@"
  tasks:
    - import_tasks: tasks/compfuzor.includes
