---
- hosts: all
  gather_facts: False
  vars:
    TYPE: eclipse
    INSTANCE: mars
    TGZ: http://download.eclipse.org/technology/epp/downloads/release/neon/R/eclipse-jee-neon-R-linux-gtk-x86_64.tar.gz
    eclipse_file: "{{NAME}}.tgz"
    release: mars
    eclim_url: https://github.com/ervandew/eclim/releases/download/2.6.0/eclim_2.6.0.jar
    iu:
    - repo: "http://download.eclipse.org/releases/{{release}}/"
      ius: 
      - org.eclipse.dltk.core.feature.group
      - org.eclipse.dltk.mylyn.feature.group
      - org.eclipse.dltk.rse.feature.group
      - org.eclipse.dltk.ruby.feature.group
      - org.eclipse.dltk.sh.feature.group
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
      #- org.eclipse.persistence.sdk.feature.group
      - org.eclipse.cdt.build.crossgcc.feature.group
      - org.eclipse.cdt.debug.gdbjtag.feature.group
      - org.eclipse.cdt.launch.remote.feature.group
      - org.eclipse.papyrus.sdk.feature.feature.group
      - org.eclipse.cdt.autotools.feature.group
      - org.eclipse.linuxtools.callgraph.feature.feature.group
      - org.eclipse.linuxtools.cdt.libhover.feature.feature.group
      - org.eclipse.cdt.managedbuilder.llvm.feature.group
      - org.eclipse.wst.jsdt.feature.feature.group
      - org.eclipse.jpt.jaxb.feature.feature.group
      - org.eclipse.jpt.jpadiagrameditor.feature.feature.group
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
      - org.eclipse.pde.api.tools.ee.feature.feature.group
      - org.eclipse.bpel.common.feature.feature.group
      - org.eclipse.bpel.apache.ode.runtime.feature.feature.group
      - org.eclipse.bpel.feature.feature.group
      - org.eclipse.bpmn2.feature.feature.group
      - org.eclipse.bpmn2.modeler.feature.group
      - org.eclipse.bpmn2.modeler.examples.feature.group
      - org.eclipse.bpmn2.modeler.runtime.jboss.feature.group
      - org.eclipse.bpmn2.modeler.wsil.feature.group
      - org.eclipse.buildship.feature.group
      - org.eclipse.cdt.docker.launcher.feature.group
      - org.eclipse.egit.gitflow.feature.feature.group
      - org.eclipse.stardust.modeling.core-feature.feature.group
      - org.eclipse.stardust.documentation.documentation-feature.feature.group
      - org.eclipse.stardust.modeling.simulation-feature.feature.group
      - org.eclipse.stardust.modeling.wst-feature.feature.group
      - org.eclipse.tracecompass.gdbtrace.feature.group
      - org.eclipse.linuxtools.gprof.feature.feature.group
      - org.eclipse.thym.feature.feature.group
      - org.eclipse.jwt.feature.feature.group
      - org.eclipse.tracecompass.lttng2.kernel.feature.group
      - org.eclipse.tracecompass.lttng2.ust.feature.group
      - org.eclipse.ldt.feature.group
      - org.eclipse.ldt.remote.feature.group
      - org.eclipse.mat.feature.feature.group
      - org.eclipse.mat.chart.feature.feature.group
      - org.eclipse.mylyn.pde_feature.feature.group
      - org.eclipse.mylyn.gerrit.feature.feature.group
      - org.eclipse.mylyn.gerrit.dashboard.feature.feature.group
      - org.eclipse.mylyn.git.feature.group
      - org.eclipse.linuxtools.oprofile.feature.feature.group
      - org.eclipse.tracecompass.tmf.pcap.feature.group
      - org.eclipse.linuxtools.perf.feature.feature.group
      - org.eclipse.remote.console.feature.group
      - org.eclipse.remote.feature.group
      - org.eclipse.linuxtools.systemtap.feature.group
      - org.eclipse.tcf.cdt.feature.feature.group
      - org.eclipse.tcf.rse.feature.feature.group
      - org.eclipse.tcf.te.tcf.feature.feature.group
      - org.eclipse.tm.terminal.connector.remote.feature.feature.group
      - org.eclipse.tm.terminal.view.rse.feature.feature.group
      - org.eclipse.linuxtools.valgrind.feature.group
      - org.eclipse.mylyn.hudson.feature.group
      - org.eclipse.mylyn.commons.feature.group
      - org.eclipse.mylyn.commons.identity.feature.group
      - org.eclipse.mylyn.commons.notifications.feature.group
      - org.eclipse.mylyn.commons.repositories.feature.group
      - org.eclipse.mylyn.commons.repositories.http.feature.group
      - org.eclipse.mylyn.docs.epub.feature.group
      - org.eclipse.mylyn.htmltext.feature.group
      - org.eclipse.mylyn.reviews.feature.feature.group
      - org.eclipse.mylyn_feature.feature.group
      - org.eclipse.mylyn.context_feature.feature.group
      - org.eclipse.mylyn.tasks.ide.feature.group
      #- org.eclipse.mylyn.sdk_feature.feature.group
      #- org.eclipse.mylyn.test_feature.feature.group
      - org.eclipse.mylyn.versions.feature.group
      - org.eclipse.mylyn.wikitext_feature.feature.group

    - repo: https://dl-ssl.google.com/android/eclipse/
      ius:
      - com.android.ide.eclipse.ddms.feature.feature.group
      - com.android.ide.eclipse.adt.feature.feature.group
      - com.android.ide.eclipse.hierarchyviewer.feature.feature.group
      - com.android.ide.eclipse.ndk.feature.feature.group
      - com.android.ide.eclipse.traceview.feature.feature.group
      - com.android.ide.eclipse.gldebugger.feature.feature.group
    - repo: http://eclipse-color-theme.github.io/update/
      iu:
      - com.github.eclipsecolortheme.feature.feature.group
      #- com.github.eclipseuitheme.themes.feature.feature.group
    - repo: http://download.eclipse.org/technology/m2e/releases
      ius:
      - org.eclipse.m2e.feature.feature.group
      - org.eclipse.m2e.logback.feature.feature.group
    - repo: "http://download.eclipse.org/eclipse/updates/4.5-P-builds/"
      iu: org.eclipse.jdt.java9patch.feature.group

    #- repo: http://eclipse.jeeeyul.net/update/
    #  ius:
    #  - net.jeeeyul.eclipse.themes.feature.feature.group
    #- repo: http://chromedevtools.googlecode.com/svn/update/dev/
    #  ius:
    #  - org.chromium.debug.feature.group
    #  - org.chromium.debug.jsdtbridge.feature.group
    #  - org.chromium.sdk.wipbackends.feature.group

    - repo: "http://www.nodeclipse.org/updates/"
      #repo: "http://dl.bintray.com/nodeclipse/nodeclipse/1.0.2f"
      ius:
      - org.nodeclipse.enide.nodejs.feature.feature.group
      #- com.eclipsesource.jshint.feature.feature.group
      - org.nodeclipse.enide.editors.jade.feature.feature.group
      - org.chromium.sdk.feature.group
      - org.chromium.debug.feature.group
      - org.nodeclipse.feature.group
      - org.nodeclipse.jjs.feature.feature.group
      - org.nodeclipse.mongodb.feature.feature.group
      - org.nodeclipse.enide.nodejs.feature.feature.group
      - org.nodeclipse.phantomjs.feature.feature.group
      - org.nodeclipse.vertx.feature.feature.group
      - jsonedit-feature.feature.group
      - org.sweetlemonade.eclipse.json.feature.feature.group
      - markdown.editor.feature.feature.group
      - code.google.restclient.tool.feature.feature.group
      - net.sourceforge.shelled.feature.group
      - com.xored.glance.feature.group
      #- net.jeeeyul.pdetools.feature.feature.group
      #- net.jeeeyul.eclipse.themes.feature.feature.group
      #- net.vtst.ow.eclipse.less.feature.feature.group
      - EclipseRunnerFeature.feature.group
      - SelectionExplorerFeature.feature.group
      - OpenClosedProjectsFeature.feature.group
      - org.eclipse.rse.feature.group
      - org.eclipse.rse.useractions.feature.group
      #- org.eclipse.rse.scp.feature.group
      - org.eclipse.tcf.te.terminals.feature.feature.group
      - tern-feature.feature.group
      - tern-jsdt-feature.feature.group
      - tern-linters-feature.feature.group
      - tern-server-nodejs-feature.feature.group
    content: "{{iu|to_json}}"

    FILES:
    - name: iu.json
      src: "../content"
    BINS:
    - install-iu
    - install-eclim
    BIN_RUN_BYPASS: True
  tasks:
  - include: tasks/compfuzor.includes type=opt
  - get_url: url="{{eclim_url}}" dest="{{SRCS_DIR}}/{{eclim_url|basename}}"
#  - shell: tar --strip-components 1 -xvzf "{{SRCS_DIR}}/{{eclipse_file}}" -C "{{OPT}}"
  - file: src="{{OPT}}" dest="{{OPTS_DIR}}/eclipse" state=link
  - file: src="{{DIR}}/eclipse" dest="{{GLOBAL_BINS_DIR}}/eclipse" state=link
#  - include: tasks/compfuzor/bins_run.tasks
