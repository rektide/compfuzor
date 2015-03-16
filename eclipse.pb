---
- hosts: all
  gather_facts: False
  vars:
    TYPE: eclipse
    INSTANCE: luna
    TGZ: http://mirror.cc.columbia.edu/pub/software/eclipse/technology/epp/downloads/release/luna/SR2/eclipse-jee-luna-SR2-linux-gtk-x86_64.tar.gz
    eclipse_url: http://mirror.cc.columbia.edu/pub/software/eclipse/technology/epp/downloads/release/luna/SR2/eclipse-jee-luna-SR2-linux-gtk-x86_64.tar.gz
    # http://www.gtlib.gatech.edu/pub/eclipse/technology/epp/downloads/release/luna/SR2/eclipse-jee-luna-SR2-linux-gtk-x86_64.tar.gz  
    eclipse_file: "{{NAME}}.tgz"
    release: luna
    eclim_url: http://softlayer-dal.dl.sourceforge.net/project/eclim/eclim/2.4.1/eclim_2.4.1.jar
    iu:
    - repo: "http://download.eclipse.org/releases/{{release}}/"
      ius: 
      - org.eclipse.dltk.core.feature.group
      - org.eclipse.wst.web_ui.feature.feature.group
      - org.eclipse.egit.feature.group
      - org.eclipse.jgit.feature.group
      - org.eclipse.mylyn.github.feature.feature.group
      - org.eclipse.m2e.sdk.feature.feature.group
      - org.eclipse.m2e.feature.feature.group
      - org.eclipse.m2e.logback.feature.feature.group
      - org.eclipse.mylyn.hudson.feature.group
      - org.eclipse.cdt.feature.group
      - org.eclipse.cdt.mylyn.feature.group
      - org.eclipse.mylyn.ide_feature.feature.group
      - org.eclipse.mylyn.java_feature.feature.group
      - org.eclipse.mylyn.git.feature.group
      - org.eclipse.egit.mylyn.feature.group
      - org.eclipse.persistence.sdk.feature.group
      - org.eclipse.cdt.build.crossgcc.feature.group
      - org.eclipse.cdt.debug.gdbjtag.feature.group
      - org.eclipse.cdt.launch.remote.feature.group
      - org.eclipse.papyrus.sdk.feature.feature.group
      - org.eclipse.cdt.autotools.feature.group
      - org.eclipse.linuxtools.callgraph.feature.feature.group
      - org.eclipse.linuxtools.cdt.libhover.feature.feature.group
      - org.eclipse.cdt.managedbuilder.llvm.feature.group
      - org.eclipse.wst.jsdt.feature.feature.group
      - org.eclipse.koneki.ldt.feature.group
      - org.eclipse.jpt.jaxb.feature.feature.group
      - org.eclipse.wst.common.fproj.feature.group
      - org.eclipse.jst.enterprise_ui.feature.feature.group
      - org.eclipse.jst.web_ui.feature.feature.group
      - org.eclipse.jst.server_adapters.feature.feature.group
      - org.eclipse.jst.server_adapters.ext.feature.feature.group
      - org.eclipse.jst.server_ui.feature.feature.group
      - org.eclipse.wst.web_ui.feature.feature.group
      - org.eclipse.wst.xml_ui.feature.feature.group
      - org.eclipse.wst.xsl.feature.feature.group
      - org.eclipse.m2e.wtp.jaxrs.feature.feature.group
      - org.eclipse.m2e.wtp.jpa.feature.feature.group
      - org.eclipse.m2e.wtp.feature.feature.group
      - org.eclipse.libra.facet.feature.feature.group
      - org.eclipse.libra.framework.editor.feature.feature.group
      - org.eclipse.libra.framework.feature.feature.group
      - org.eclipse.libra.warproducts.feature.feature.group
      - org.eclipse.wst.server_adapters.feature.feature.group
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
    - repo: http://download.eclipse.org/technology/m2e/releases
      ius: org.eclipse.m2e.feature.feature.group,org.eclipse.m2e.logback.feature.feature.group
    - repo: "http://download.eclipse.org/tools/cdt/releases/{{release}}"
      ius: org.eclipse.cdt.feature.group
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
#  - get_url: url="{{eclipse_url}}" dest="{{SRCS_DIR}}/{{eclipse_file}}"
  - get_url: url="{{eclim_url}}" dest="{{SRCS_DIR}}/{{eclim_url|basename}}"
#  - shell: tar --strip-components 1 -xvzf "{{SRCS_DIR}}/{{eclipse_file}}" -C "{{OPT}}"
  - file: src="{{OPT}}" dest="{{OPTS_DIR}}/eclipse" state=link
  - file: src="{{DIR}}/eclipse" dest="{{GLOBAL_BINS_DIR}}/eclipse" state=link
#  - include: tasks/compfuzor/bins_run.tasks
