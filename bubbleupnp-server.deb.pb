---
- hosts: all
  vars:
    TYPE: bubbleupnp
    INSTANCE: 0.9-8
    GET_URLS: "https://bubblesoftapps.com/bubbleupnpserver/bubbleupnpserver_{{INSTANCE}}_all.deb"
  tasks:
    - include: tasks/compfuzor.includes type=opt
