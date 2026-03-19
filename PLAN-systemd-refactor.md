i'm trying to replace the rather wild tasks/compfuzor/systemd.tasks step, which does a lot of things, with tasks/compfuzor/vars_systemd_unit.tasks building scripts that do the work. i'm part way there i think: there are some install-unit.sh and a paramterized install-<unit-type>.sh script, which help symlink into place, and which will need to enable and start too.

we want to add unit creation into tasks/compfuzor/vars_systemd_unit.tasks, creating ETC_FILES entries for the units we want to create. look at other tasks/compfuzor/vars\*\* for examples of creating files. we have a generic install-unit.sh and install-service.sh etc, that should symlink, daemon-reload, and enable units. we can improve the .d handling in the install-unit.sh script in the future (something the old systemd.tasks subsystem did)

we also need to consolidate/simplify how we template the units. currently we sort of have two ways of templating systemd units: the old legacy way was very explicit long templates in files/ such as files/systemd.service.tasks. there is some logic in here that is generic, but there is also a very very explicit directive by directive version where we re-define every single parameter. that needs to go. the new path forwards is to let the defining playbook define top sections, then free-form directives underneath.

we also don't support enough systemd unit types at the moment. there's a SYSTEMD_UNITTYPES_ALL. but it is missing a number of types, such as timer, automount, socket, network, netdev. we also need a lookup var, that tells us what units go to what directories, be it /etc/systemd/system or /etc/systemd/network chiefly.

when templating, we'd like to be able to point the template at a top level variable, that everything else flows from. by default this should just be the vars object itself, all vars. but we want to be able to template a unit from, say, MOUNT and then SOCKET, with [Mount] and [Unit] and [Socket] appearing nested under there.

we have a PLAN.md that has an early plan for this.
