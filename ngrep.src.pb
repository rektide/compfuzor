
---
- hosts: all
  vars:
    REPO: https://github.com/0xNaN/ngrep
    GET_URLS:
      - https://dl.fbaipublicfiles.com/fasttext/vectors-crawl/cc.en.300.vec.gz 
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
