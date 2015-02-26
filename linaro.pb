---
- hosts: all
  vars:
    TYPE: linaro
    ARCH: gnueabihf
    RELEASE: 15.02
    GCC: 4.9
    INSTANCE: "{{ARCH}}-{{GCC}}-{{RELEASE}}"
    
    linaro: gcc-linaro-{{GCC}}-{{RELEASE}}"
    linaro_url: "https://releases.linaro.org/{{RELEASE}}/components/toolchain/gcc-linaro/{{GCC}}/{{linaro}}.tar.xz"
  tasks:
  - include: tasks/compfuzor.includes type="opt"
  # get linaro
  - get_url: url="{{linaro_url}}" dest="{{DIR}}/{{linaro}}.tar.xz"
  - shell: chdir={{DIR}} tar xaf "{{DIR}}/{{linaro}}.tar.xz" --strip-components=1


