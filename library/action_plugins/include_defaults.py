# (c) 2013-2014, Benno Joy <benno@ansible.com>
# (c) 2014, rektide
#
# This file is part of Ansible
#
# Ansible is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ansible is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible.  If not, see <http://www.gnu.org/licenses/>.

__metaclass__ = type

from ansible.plugins.action.include_vars import ActionModule as IncludeVars

class ActionModule(IncludeVars):

    def run(self, tmp=None, task_vars=None):
        results = super(ActionModule, self).run(tmp, task_vars)
        facts = results['ansible_facts']
        filtered = {k:v for (k,v) in facts.iteritems() if k not in task_vars }
        results['ansible_facts'] = filtered
        return results
