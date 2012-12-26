= CompFuzor = 

CF is a repository of systems configuration scripts for onlining new nodes with a variety of services.

It is written primarily as Ansible scripts, dubbed "playbooks" in their parlance.

= Conventions =

== Directories ==
+ `/` is the main repository of playbooks.
+ `tasks/` are subtasks used by playbooks.
+ `vars/` hold broad configuration data.
+ `files/` holds files which will be sourced when running a playbook.
+ `private/` holds sensitive data configs.
+ `example-private/` holds dummy data to mock out it's private/ counterpart.

== Playbook Types ==
+ `.srv.pb` are _instances_ of services, typically deploying into /srv/$SERVICE_TYPE-$INSTANCE. $INSTANCE defaults to main in common.vars.
+ `.opt.pb` is there to install a software package, usually into /opt. configuration, if possible, ought be split into a `.srv.pb` playbook.
+ `.user.pb` are intended to install into a user's own directory.

== Configuration ==
+ `vars/`, `private/`, and `example-private/` hold non-installation specific, installation specific, and examples of installation specific configuraiton data.
+ `vars/common.vars` is a generic set of variables, for example defining paths such as opt, srv.
+ `vars/common.user.vars` supplements/overrides `common.vars` with user-targetted script configuration: OPT_DIR becomes ~/.local/opt, for instance.
