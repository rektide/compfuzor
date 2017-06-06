---
# BROKEN - curl command not making it through clickwrap
- hosts: all
  vars:
    TYPE: jlink
    INSTANCE: 6.16
    SRC_FILE:
    - name: "{{url|basename}}.url
      content: "{{url}}"
    url: "https://www.segger.com/downloads/jlink/JLink_Linux_V{{INSTANCE|replace('.', '')}}_x86_64.deb"
    basename: "{{url|basename}}"
  tasks:
  - include: tasks/compfuzor.includes type=opt
  - command: 'curl -X POST -F "accept_license_agreement=accepted" --header "Content-Type: application/x-www-form-urlencode" "https://www.segger.com/downloads/jlink/JLink_Linux_V616_x86_64.deb" -o "{{basename}}"'
    chdir: "{{SRC}}"
  - command: "dpkg -i '{{SRC}}/{{basename}}'"
    become: True
