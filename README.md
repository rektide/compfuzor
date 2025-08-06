# CompFuzor #

CF is a repository of systems configuration scripts for onlining new nodes with a variety of services.

As opposed to normal Ansible where one is writing tasks, Compfuzor tries to codify many practices and tasks such that the author declares what they want (as variables). General routines handle all Compfuzor playbooks, enacting the variables for the playbook that have been defined. Thus most good Compfuzor playbooks have only a single task: `include: tasks/compfuzor.includes`.

In addition, CF creates conventions for how and where files should go, with playbooks indirectly asking to place things in an extended Unix Filesystem Hierarchy like place with [common system locations](https://github.com/rektide/compfuzor/blob/master/vars/common.yaml#L5-L15) and [common user locations](https://github.com/rektide/compfuzor/blob/master/vars/common.user.yaml#L6-L15) overridable but used by default. These locations are tied to specific instances of a playbook, such that one can maintain multiple separate runs of a playbook on one machine. For instance, I use this for setting up a "3 node" etcd cluster on a laptop with no VM's or containers, but more generally this is also useful for testing things out on an alternate instance before running them on the main instance.

Added latter, there are a host of other conventions: environment variables are a core concept, and will automatically be used by Systemd services, another core of Compfuzor. Checking out sources a core capability. Extra contextual vars like XDG, a random PASSWORD and UUID are injected into runs.

It is written primarily as Ansible scripts, dubbed "playbooks" in their parlance. It provides a rich set of default directives which use a construct of context sensitivie settings to create ea consistend framework for emplacing software and processes.

# Conventions #

## Base System ##
+ systemd is the init process.
+ dpkg/apt for package management.

## Directories ##
+ `/` is the main repository of playbooks.
+ `tasks/` are subtasks used by playbooks.
+ `tasks/compfuzor` is the main-body of compfuzor execution, run by the task `include: tasks/compfuzor.includes`
+ `vars/` hold broad configuration data.
+ `files/` holds files which will be sourced when running a playbook.
+ `private/` holds sensitive data configs.
+ `example-private/` holds dummy data to mock out it's private/ counterpart.

## Playbook Types ##
+ `.srv.pb` are _instances_ of services, typically deploying into /srv/$TYPE-$INSTANCE. $INSTANCE defaults to main in common.vars.
+ `.opt.pb` is there to install a software package, usually into /opt. configuration, if possible, ought be split into a `.srv.pb` playbook.
+ `.user.pb` are intended to install into a user's own directory.
+ `.src.pb` are compiled (generally) source packages, often outputing an associated .opt package

## Configuration ##
+ `vars/`, `private/`, and `example-private/` hold non-installation specific, installation specific, and examples of installation specific configuraiton data.
+ `vars/common.vars` is a generic set of variables, for example defining paths such as opt, srv.
+ `vars/common.user.vars` supplements/overrides `common.vars` with user-targetted script configuration: OPTS_DIR becomes ~/.local/opt, for instance.

## Services ##
+ ought be based around these variables:
    + $TYPE, a name prefix identifying what type of service this is.
    + $SRVS_DIR, where all services are kept, which common.vars will default to /srv
    + $INSTANCE, defaulted to main, but overridable to create a new instance of the service.
    + $NAME, conventionally set to $TYPE-$INSTANCE by tasks/srv.vars.tasks if none is provided (this ought be included early in most all srv scripts).
    + $DIR, conventionally set to {{SRVS_DIR}}/{{NAME}} if none is provided, where the service instance is installed
+ in practices, services need to declare a $TYPE and then run tasks/srv.vars.tasks, leaving most of these var configurations to be done externally.
+ write a `systemd.unit(5)` file into $SYSTEMD_UNITS.
+ ideally all services can be installed multiple times! make it so!
+ `handlers.yml` ought provide a `restart $TYPE` directive that ought expect the above vars be defined.
+ services ought have their own user & group, typically {{NAME}}. A common tasks is in the works.
    + lordy be, here me now: all "services" are to be templates with their sudo_user injected at execution time.
    + i have no idea right now how to pull off this execution framework.
    + similarly, having INSTANCE baked in, not having defaults, these are major ansible warts I don't know how to factor out yet. ideas welcome.

# Miscellenary #
+ Some vars are listed as $FOO.stdout. This ought go away pending some assistance in ansible#1730.
+ Deal better with permissions- most scripts ought be made to operate without sudo, but do need some initialization routines to be run on their behalf. Device a clean way to separate user from server side.

## BEASTIARY ##

### DIR

Your maindir

### Lesser Dirs

SRV, OPT, ETC, VAR, LOG, SPOOL, CACHE, PID, RUN, SRC, PKGS

SRV, services dir, /srvs
OPT, optional software packages, /opt
ETC, configuration settings, /etc (but like the above per instance, not global)
VAR, various settings, /var
SRC, package for sources, /usr/local/src

### VARiants

LOG, log directory, /var/log
SPOOL, transient message queue dir, /var/spool
CACHE, expiring cache files, /var/cache
PID, process ids, /var/pid
RUN, process's runtime data, /var/run

## `Common` Mode Bits ##

`var/common.var` and `var/common.user.var` hold the main system configuration data which will guide (provide all base context for) all CompFuzor runs.

### APT_INSTALL

install apt packages with this state (`latest`, `installed`, &c)
