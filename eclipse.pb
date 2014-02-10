---
- hosts: all
  gather_facts: False
  vars:
    TYPE: eclipse
    INSTANCE: 4.3.1
    file: http://ftp.osuosl.org/pub/eclipse/technology/epp/downloads/release/kepler/SR1/eclipse-jee-kepler-SR1-linux-gtk-x86_64.tar.gz
    SRCS_NAME: "{{SRCS_DIR}}/{{NAME}}.tgz"
    OPT_DIR: "{{OPTS_DIR}}/{{NAME}}"
    androidIU:
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - get_url: url={{file}} dest={{SRCS_NAME}}
  - shell: chdir={{OPTS_DIR}} tar -xvzf {{SRCS_NAME}}
  - file: path={{OPT_DIR}} state=absent
  - shell: chdir={{OPTS_DIR}} mv eclipse {{NAME}}
  - file: src={{OPT_DIR}}/eclipse dest={{BINS_DIR}}/eclipse state=link
  - shell: chdir={{OPT_DIR}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository http://download.eclipse.org/technology/m2e/releases -installIU org.eclipse.m2e.feature.feature.group,org.eclipse.m2e.logback.feature.feature.group
  - shell: chdir={{OPT_DIR}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository http://download.eclipse.org/tools/cdt/releases/kepler -installIU org.eclipse.cdt.feature.group
  - shell: chdir={{OPT_DIR}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository http://download.eclipse.org/egit/updates -installIU org.eclipse.egit.feature.group,org.eclipse.jgit.java7.feature.group
  - shell: chdir={{OPT_DIR}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository https://dl-ssl.google.com/android/eclipse/ -installIU com.android.ide.eclipse.adt.feature.group,com.android.ide.eclipse.hierarchyviewer.feature.group,com.android.ide.eclipse.traceview.feature.group,com.android.ide.eclipse.gldebugger.feature.group,com.android.ide.eclipse.ddms.feature.group,com.android.ide.eclipse.ndk.feature.group
  - shell: chdir={{OPT_DIR}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository http://eclipse-color-theme.github.io/update/ -installIU com.github.eclipsecolortheme.feature.feature.group
  - shell: chdir={{OPT_DIR}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository http://download.eclipse.org/releases/kepler -installIU org.eclipse.xtend.sdk.feature.group,org.eclipse.uml2.sdk.feature.group
  - shell: chdir={{OPT_DIR}} ./eclipse -nosplash -application org.eclipse.equinox.p2.director -repository https://raw.github.com/jeeeyul/eclipse-themes/master/net.jeeeyul.eclipse.themes.updatesite -installIU net.jeeeyul.eclipse.themes.feature.feature.group
  - get_url: url="http://downloads.sourceforge.net/project/eclim/eclim/2.3.2/eclim_2.3.2.jar?r=http%3A%2F%2Fsourceforge.net%2Fprojects%2Feclim%2Ffiles%2Feclim%2F2.3.2%2Feclim_2.3.2.jar%2Fdownload&ts=1392006484&use_mirror=softlayer-dal" dest="{{SRCS_DIR}}/eclim_2.3.2.jar"
  - shell: java -Dvim.files=$HOME/.vim -Declipse.home="{{OPT_DIR}}" -jar "{{SRCS_DIR}}/eclim_2.3.2.jar" install
