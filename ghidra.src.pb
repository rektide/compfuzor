---
- hosts: all
  vars:
    REPO: https://github.com/NationalSecurityAgency/ghidra
    PKGS:
      - default-jdk
    BINS:
      - name: build.sh
        content: |
          ./gradlew -I gradle/support/fetchDependencies.gradle
          ./gradlew buildGhidra -x ip
      - name: install.sh
        content: |
          cd build/dist
          zip=$(ls ghidra_*_PUBLIC_*.zip)
          mkdir -p /opt/ghidra
          rm -rf /opt/ghidra/*
          unzip -oqd -q "${zip}" -d /opt/ghidra
          ln -sfnv /opt/ghidra/ghidra_*/ghidraRun /opt/ghidra/ghidraRun
          rm "${zip}"
      - name: ghidraRun
        global: True
        content: |
          exec /opt/ghidra/ghidraRun "$@"
      - name: analyzeHeadless
        global: True
        content: |
          exec /opt/ghidra/support/analyzeHeadless "$@"
  tasks:
    - import_tasks: tasks/compfuzor.includes
