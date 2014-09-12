---
- hosts: all
  gather_facts: False
  vars:
    TYPE: eclipse
    INSTANCE: 4.4

    eclipse_url: http://ftp.osuosl.org/pub/eclipse//technology/epp/downloads/release/luna/R/eclipse-standard-luna-R-linux-gtk-x86_64.tar.gz
    eclipse_file: "{{NAME}}.tgz"
    release: luna
    eclim_url: http://softlayer-dal.dl.sourceforge.net/project/eclim/eclim/2.4.0/eclim_2.4.0.jar
    iu:
    - repo: http://download.eclipse.org/egit/updates
      ius:
      - org.eclipse.egit.feature.group
      - org.eclipse.jgit.java7.feature.group
    - repo: https://dl-ssl.google.com/android/eclipse/
      ius:
      - com.android.ide.eclipse.ddms.feature.feature.group
      - com.android.ide.eclipse.adt.feature.feature.group
      - com.android.ide.eclipse.hierarchyviewer.feature.feature.group
      - com.android.ide.eclipse.ndk.feature.feature.group
      - com.android.ide.eclipse.traceview.feature.feature.group
      - com.android.ide.eclipse.gldebugger.feature.feature.group
    - repo: http://eclipse-color-theme.github.io/update/
      iu: com.github.eclipsecolortheme.feature.feature.group
    - repo: http://eclipse.jeeeyul.net/update/
      iu: net.jeeeyul.eclipse.themes.feature.feature.group
    #- repo: "http://download.eclipse.org/releases/{{release}}"
    #  ius: org.eclipse.xtend.sdk.feature.group,org.eclipse.uml2.sdk.feature.group
    #- repo: http://download.eclipse.org/technology/m2e/releases
    #  ius: org.eclipse.m2e.feature.feature.group,org.eclipse.m2e.logback.feature.feature.group
    #- repo: "http://download.eclipse.org/tools/cdt/releases/{{release}}"
    #  ius: org.eclipse.cdt.feature.group
    content: "{{iu}}"

    FILES:
    - name: iu.json
      src: "../content"
    BINS:
    - install-iu
    - install-eclim
    BIN_RUN_BYPASS: True
  tasks:
  - include: tasks/compfuzor.includes type=opt
  - get_url: url="{{eclipse_url}}" dest="{{SRCS_DIR}}/{{eclipse_file}}"
  - get_url: url="{{eclim_url}}" dest="{{SRCS_DIR}}/{{eclim_url|basename}}"
  - shell: tar --strip-components 1 -xvzf "{{SRCS_DIR}}/{{eclipse_file}}" -C "{{OPT}}"
  - file: src="{{OPT}}" dest="{{OPTS_DIR}}/eclipse" state=link
  - file: src="{{OPTS_DIR}}/eclipse/eclipse" dest="{{GLOBAL_BINS_DIR}}/eclipse" state=link
  - include: tasks/compfuzor/bins_run.tasks
