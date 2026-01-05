---
- hosts: all
  vars:
    GET_URLS:
      - dest: cursor_2.2_amd64.deb
        url: https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/2.2
        #https://downloads.cursor.com/production/20adc1003928b0f1b99305dbaf845656ff81f5d4/linux/x64/deb/amd64/deb/cursor_2.2.44_amd64.deb
  tasks:
    - import_tasks: tasks/compfuzor.includes
