---
- hosts: all
  gather_facts: False
  vars:
    fonts:
      inconsolata: http://www.levien.com/type/myfonts/Inconsolata.otf
      anonymous_pro: http://www.marksimonson.com/assets/content/fonts/AnonymousPro-1.002.zip
      http://sourceforge.net/projects/dejavu/files/dejavu/2.33/dejavu-fonts-ttf-2.33.zip
    DIR: {{SRCS_DIR}}/fonts
  vars_files:
  - vars/common.vars
  tasks:
  - file: path={{DIR}} state=directory
  - get_url: url={{fonts[item]}} dest={{DIR}}/{{item}}
    with_items: fonts.keys()
  - shell: chdir={{DIR} unzip {{item}}
    with_items: [i for i in fonts.keys() if i.endswith(".zip")]
  - shell: chdir={{DIR}} ls
    register: dirfiles
  - file: src={{DIR}}/{{item}} dest=/usr/share/fonts/opentype
    with_items: [i for i in dirfiles.stdout if i.endswith(".otf")]
  - file: src={{DIR}}/{{item}} dest=/usr/share/fonts/truetype
    with_items: [i for i in dirfiles.stdout if i.endswith(".ttf")]
