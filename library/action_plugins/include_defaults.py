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
from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import os

from ansible.errors import AnsibleError
from ansible.module_utils.common.text.converters import to_text
from ansible.plugins.action import ActionBase

class ActionModule(ActionBase):
    def run(self, tmp=None, task_vars=None):
        if task_vars is None:
            task_vars = dict()


        result = super(ActionModule, self).run(tmp, task_vars)
        file = self._task.args.get('file')

        if self._task._role:
            filename = self._loader.path_dwim_relative(self._task._role._role_path, 'vars', file)
        else:
            filename = self._loader.path_dwim_relative(self._loader.get_basedir(), 'vars', file)

        if os.path.exists(filename):
            b_data, show_content = self._loader._get_file_contents(filename)
            data = to_text(b_data, errors='surrogate_or_strict')

            data = self._loader.load(data, file_name=filename, show_content=show_content)
            if data is None:
                data = {}
            if not isinstance(data, dict):
                raise AnsibleError("%s must be stored as a dictionary/hash" % filename)
            data = {k:v for (k,v) in data.items() if k not in task_vars }
            result['ansible_facts'] = data
            result['_ansible_no_log'] = not show_content
            self._task.action = "include_vars"
        else:
            result['failed'] = True
            result['msg'] = "Source file not found."
            result['file'] = filename or file
        return result
