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
from ansible.plugins.action import ActionBase

class ActionModule(IncludeVars):

    #TRANSFERS_FILES = False

    def run(self, tmp=None, task_vars=None):
        if task_vars.has_key("INCLUDE_VARS_RAW_PARAM"):
            self._task.args['_raw_params']= self._task.args.get('file')
        result = super(ActionModule, self).run(tmp, task_vars)

        facts = result['ansible_facts']
        if facts:
            copy = facts.copy()
            for key in copy:
                if task_vars.has_key(key):
                    del facts[key]
        return result
