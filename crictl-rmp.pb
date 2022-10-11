---
- hosts: all
  tasks:
   - name: "get ready (running) pods"
     shell: "crictl pods --state ready | awk '{print $1}' | tail -n+2"
     become: true
     failed_when: pods_running.stderr_lines.length > 1
     register: pods_running
   - name: "stop ready pods"
     shell: "crictl stopp {{ pods_running.stdout_lines|join(' ') }}"
     when: pods_running.stdout_lines|length > 0
     become: true
   - name: "get all pods with 'crictl pods'"
     shell: "crictl pods --no-trunc | awk '{print $1}' | tail -n+2"
     failed_when: pods_all.stderr_lines.length > 1
     become: true
     register: pods_all
   - debug:
       msg: "hello {{pods_all}}"
   - name: "remove all pods"
     shell: "crictl rmp {{ pods_all.stdout_lines|join(' ') }}"
     when: pods_all.stdout_lines|length > 0
     become: true
