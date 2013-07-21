---
- hosts: all
  gather_facts: False
  vars:
    fonts:
    - http://www.levien.com/type/myfonts/Inconsolata.otf
    - http://www.marksimonson.com/assets/content/fonts/AnonymousPro-1.002.zip
    - http://downloads.sourceforge.net/project/dejavu/dejavu/2.33/dejavu-fonts-ttf-2.33.zip?r=http%3A%2F%2Fdejavu-fonts.org%2Fwiki%2FDownload&ts=1374399246&use_mirror=iweb
    DIR: "{{SRCS_DIR}}/fonts"
  vars_files:
  - vars/common.vars
  tasks:
  - file: path={{DIR}} state=directory
  - get_url: url={{item}} dest={{DIR}}
    with_items: fonts
  # unzip .zip files
  - shell: chdir={{DIR}} ls *.zip
    register: zipfiles
  - shell: chdir={{DIR}} unzip -jf {{item}}
    with_items: ${zipfiles.stdout_lines}
  # install otf files
  - shell: chdir={{DIR}} find . -iname "*.otf"
    register: otffiles
  - file: src="{{DIR}}/{{item}}" dest="/usr/share/fonts/opentype/{{item}}" state=link
    with_items: otffiles.stdout_lines
   install ttf files
  - shell: chdir={{DIR}} find . -iname "*.ttf"
    register: ttffiles
  - file: src="{{DIR}}/{{item}}" dest="/usr/share/fonts/truetype/{{item}}" state=link
    with_items: ttffiles.stdout_lines
  # perhaps there'll be generator support some day
  #- file: src={{DIR}}/{{item}} dest=/usr/share/fonts/truetype
  #  with_items: [i for i in dirfiles.stdout if i.endswith(".ttf")]
