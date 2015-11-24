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


#from __future__ import (absolute_import, division, print_function)
#__metaclass__ = type

import os

try:
    # Ansible 2
    from ansible.plugins.action import ActionBase
    from ansible.errors import AnsibleError

    class ActionModule(ActionBase):
    
        TRANSFERS_FILES = False
    
        def run(self, tmp=None, task_vars=None):
            if task_vars is None:
                task_vars = dict()

            result = super(ActionModule, self).run(tmp, task_vars)

            source = self._task.args.get('source')

            if self._task._role:
                source = self._loader.path_dwim_relative(self._task._role._role_path, 'vars', source)
            else:
                source = self._loader.path_dwim_relative(self._loader.get_basedir(), 'vars', source)

            if os.path.exists(source):
                (data, show_content) = self._loader._get_file_contents(source)
                data = self._loader.load(data, show_content)
                if data is None:
                    data = {}
                if not isinstance(data, dict):
                    raise AnsibleError("%s must be stored as a dictionary/hash" % source)
                data = {k:v for (k,v) in data.iteritems() if k not in task_vars }
                result['ansible_facts'] = data
                result['_ansible_no_log'] = not show_content
                self._task.action = "include_vars"
            else:
                result['failed'] = True
                result['msg'] = "Source file not found."
                result['file'] = source
            return result

except ImportError:
    # Ansible 1
    from ansible.utils import template
    from ansible import utils
    from ansible import errors
    from ansible.runner.return_data import ReturnData

    class ActionModule(object):

        def __init__(self, runner):
            self.runner = runner

        def run(self, conn, tmp, module_name, module_args, inject, complex_args=None, **kwargs):

            args = parse_kv(self.runner.module_args)
            if not 'source' in args:
                result = dict(failed=True, msg="No source file given")
                return ReturnData(conn=conn, comm_ok=True, result=result)
            source = args.source
            source = template.template(self.runner.basedir, source, inject)

            if '_original_file' in inject:
                source = utils.path_dwim_relative(inject['_original_file'], 'vars', source, self.runner.basedir)
            else:
                source = utils.path_dwim(self.runner.basedir, source)

            if os.path.exists(source):
                data = utils.parse_yaml_from_file(source, vault_password=self.runner.vault_pass)
                if data and type(data) != dict:
                    raise errors.AnsibleError("%s must be stored as a dictionary/hash" % source)
                elif data is None:
                    data = {}
                data = {k:v for (k,v) in data.iteritems() if k not in inject['vars'] and k not in inject['hostvars']}
                result = dict(ansible_facts=data)
                return ReturnData(conn=conn, comm_ok=True, result=result)
            else:
                result = dict(failed=True, msg="Source file not found.", file=source)
                return ReturnData(conn=conn, comm_ok=True, result=result)

