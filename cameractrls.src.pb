---
- hosts: all
  vars:
    TYPE: cameractrls
    INSTANCE: git
    REPO: https://github.com/soyersoyer/cameractrls
    PKGS:
      - gir1.2-gtk-3.0
      - gir1.2-gtk-4.0
      - libsdl2-2.0-0
      - libturbojpeg0
    DESKTOP:
      - desktop_file: pkg/hu.irl.cameractrls.desktop
        exec: cameractrlsgtk.py
        icon: pkg/hu.irl.cameractrls.svg
        path: true
    BINS:
      - name: build.sh
        exec: |
          echo "cameractrls is a no-build Python project"
      - name: install.sh
        exec: |
          ln -sfv $REPO_DIR/cameractrls.py $GLOBAL_BINS_DIR/cameractrls
          ln -sfv $REPO_DIR/cameractrlsd.py $GLOBAL_BINS_DIR/cameractrlsd
          ln -sfv $REPO_DIR/cameraview.py $GLOBAL_BINS_DIR/cameraview
          ln -sfv $REPO_DIR/cameractrlsgtk.py $GLOBAL_BINS_DIR/cameractrlsgtk
          ln -sfv $REPO_DIR/cameractrlsgtk4.py $GLOBAL_BINS_DIR/cameractrlsgtk4
  tasks:
    - import_tasks: tasks/compfuzor.includes
