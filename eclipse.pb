---
- hosts: all
  gather_facts: False
  vars:
    TYPE: eclipse
    INSTANCE: 4.4
    file: http://ftp.osuosl.org/pub/eclipse//technology/epp/downloads/release/luna/R/eclipse-standard-luna-R-linux-gtk-x86_64.tar.gz
    SRCS_NAME: "{{SRCS_DIR}}/{{NAME}}.tgz"
    OPT_DIR: "{{OPTS_DIR}}/{{NAME}}"
    iu:
    - repo: http://download.eclipse.org/technology/m2e/releases
      installIU: org.eclipse.m2e.feature.feature.group,org.eclipse.m2e.logback.feature.feature.group
    - repo: http://download.eclipse.org/tools/cdt/releases/kepler
      installIU: org.eclipse.cdt.feature.group
    - repo: http://download.eclipse.org/egit/updates
      installIU: org.eclipse.egit.feature.group,org.eclipse.jgit.java7.feature.group
    - repo: https://dl-ssl.google.com/android/eclipse/
      installIU: com.android.ide.eclipse.adt.feature.group,com.android.ide.eclipse.hierarchyviewer.feature.group,com.android.ide.eclipse.traceview.feature.group,com.android.ide.eclipse.gldebugger.feature.group,com.android.ide.eclipse.ddms.feature.group,com.android.ide.eclipse.ndk.feature.group
    - repo: http://eclipse-color-theme.github.io/update/
      installIU: com.github.eclipsecolortheme.feature.feature.group
    - repo: http://download.eclipse.org/releases/kepler
      installIU: org.eclipse.xtend.sdk.feature.group,org.eclipse.uml2.sdk.feature.group
    - repo: https://raw.github.com/jeeeyul/eclipse-themes/master/net.jeeeyul.eclipse.themes.updatesite
      installIU: net.jeeeyul.eclipse.themes.feature.feature.group
    content: "{{iu|to_nice_json}}"
    FILES:
    - name: iu.json
      src: "../trivial"
    BINS:
    - install-iu
    - install-vim
    BIN_RUN_BYPASS: True
  tasks:
  - include: tasks/compfuzor.includes type=opt
  - get_url: url="{{file}}" dest="{{SRCS_NAME}}"
  - shell: chdir="{{OPT}}" tar --strip-components 1 -xvzf "{{SRCS_NAME}}" -C "{{OPT}}"
  - file: src="{{OPT}}" dest="{{OPTS_DIR}}/eclipse" state=link
  - file: src="{{OPTS_DIR}}/eclipse/eclipse" dest="{{GLOBAL_BINS_DIR}}/eclipse" state=link
  - include: tasks/compfuzor/bins_run.tasks
  #- shell: chdir={{OPT}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository http://download.eclipse.org/technology/m2e/releases -installIU org.eclipse.m2e.feature.feature.group,org.eclipse.m2e.logback.feature.feature.group
  #- shell: chdir={{OPT}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository http://download.eclipse.org/tools/cdt/releases/kepler -installIU org.eclipse.cdt.feature.group
  #- shell: chdir={{OPT}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository http://download.eclipse.org/egit/updates -installIU org.eclipse.egit.feature.group,org.eclipse.jgit.java7.feature.group
  #- shell: chdir={{OPT}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository https://dl-ssl.google.com/android/eclipse/ -installIU com.android.ide.eclipse.adt.feature.group,com.android.ide.eclipse.hierarchyviewer.feature.group,com.android.ide.eclipse.traceview.feature.group,com.android.ide.eclipse.gldebugger.feature.group,com.android.ide.eclipse.ddms.feature.group,com.android.ide.eclipse.ndk.feature.group
  #- shell: chdir={{OPT}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository http://eclipse-color-theme.github.io/update/ -installIU com.github.eclipsecolortheme.feature.feature.group
  #- shell: chdir={{OPT}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository http://download.eclipse.org/releases/kepler -installIU org.eclipse.xtend.sdk.feature.group,org.eclipse.uml2.sdk.feature.group
  #- shell: chdir={{OPT}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository https://raw.github.com/jeeeyul/eclipse-themes/master/net.jeeeyul.eclipse.themes.updatesite -installIU net.jeeeyul.eclipse.themes.feature.feature.group
  #- get_url: url="http://downloads.sourceforge.net/project/eclim/eclim/2.3.2/eclim_2.3.2.jar?r=http%3A%2F%2Fsourceforge.net%2Fprojects%2Feclim%2Ffiles%2Feclim%2F2.3.2%2Feclim_2.3.2.jar%2Fdownload&ts=1392006484&use_mirror=softlayer-dal" dest="{{SRCS_DIR}}/eclim_2.3.2.jar"
  #- shell: java -Dvim.files=$HOME/.vim -Declipse.home="{{OPT_DIR}}" -jar "{{SRCS_DIR}}/eclim_2.3.2.jar" install
