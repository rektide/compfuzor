= CompFuzor = 

CF is a repository of systems configuration scripts for onlining new nodes with a variety of services.

It is written primarily as Ansible scripts, dubbed "playbooks" in their parlance.

= Conventions =

== Base System ==
+ systemd is the init process.
+ dpkg/apt for package management.

== Directories ==
+ `/` is the main repository of playbooks.
+ `tasks/` are subtasks used by playbooks.
+ `vars/` hold broad configuration data.
+ `files/` holds files which will be sourced when running a playbook.
+ `private/` holds sensitive data configs.
+ `example-private/` holds dummy data to mock out it's private/ counterpart.

== Playbook Types ==
+ `.srv.pb` are _instances_ of services, typically deploying into /srv/$SRV_TYPE-$SRV_INSTANCE. $SRV_INSTANCE defaults to main in common.vars.
+ `.opt.pb` is there to install a software package, usually into /opt. configuration, if possible, ought be split into a `.srv.pb` playbook.
+ `.user.pb` are intended to install into a user's own directory.

== Configuration ==
+ `vars/`, `private/`, and `example-private/` hold non-installation specific, installation specific, and examples of installation specific configuraiton data.
+ `vars/common.vars` is a generic set of variables, for example defining paths such as opt, srv.
+ `vars/common.user.vars` supplements/overrides `common.vars` with user-targetted script configuration: OPTS_DIR becomes ~/.local/opt, for instance.

== Services ==
+ ought be based around these variables:
++ $SRV_TYPE, a name prefix identifying what type of service this is.
++ $SRVS_DIR, where all services are kept, which common.vars will default to /srv
++ $SRV_INSTANCE, defaulted to main, but overridable to create a new instance of the service.
++ $SRV_NAME.stdout, conventionally set to $SRV_TYPE-$SRV_INSTANCE by tasks/srv.vars.tasks if none is provided (this ought be included early in most all srv scripts). The stdout will go away when ansible#1730 resolves.
++ $SRV_DIR.stdout, conventionally set to $SRVS_DIR/${SRV_NAME.stdout} if none is provided, where the service instance is installed
+ in practices, services need to declare a SRV_TYPE and then run tasks/srv.vars.tasks, leaving most of these var configurations to be done externally.
+ write a `systemd.unit(5)` file into $SYSTEMD_UNITS.
+ ideally all services can be installed multiple times! make it so!
+ `handlers.yml` ought provide a `restart $SRV_TYPE` directive that ought expect the above vars be defined.
+ services ought have their own user & group, typically ${SRV_NAME.stdout}. A common tasks is in the works.

= Miscellenary =
+ Some vars are listed as $FOO.stdout. This ought go away pending some assistance in ansible#1730.
