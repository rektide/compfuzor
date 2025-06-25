
# Copyright: (c) 2012, Michael DeHaan <michael.dehaan@gmail.com>
# Copyright: (c) 2012-17, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

DOCUMENTATION = """
    name: templateVar
    author: Matthew Fowle
    version_added: "666"
    short_description: retrieve contents of variable after templating with Jinja2
    description:
      - Returns a list of strings; for each template in the list of templates you pass in, returns a string containing the results of processing that template.
    options:
      _terms:
        description: list of files to template
      convert_data:
        type: bool
        description:
            - Whether to convert YAML into data. If False, strings that are YAML will be left untouched.
            - Mutually exclusive with the jinja2_native option.
        default: true
      variable_start_string:
        description: The string marking the beginning of a print statement.
        default: '{{'
        version_added: '2.8'
        type: str
      variable_end_string:
        description: The string marking the end of a print statement.
        default: '}}'
        version_added: '2.8'
        type: str
      jinja2_native:
        description:
            - Controls whether to use Jinja2 native types.
            - It is off by default even if global jinja2_native is True.
            - Has no effect if global jinja2_native is False.
            - This offers more flexibility than the template module which does not use Jinja2 native types at all.
            - Mutually exclusive with the convert_data option.
        default: False
        version_added: '2.11'
        type: bool
      template_vars:
        description: A dictionary, the keys become additional variables available for templating.
        default: {}
        version_added: '2.3'
        type: dict
      comment_start_string:
        description: The string marking the beginning of a comment statement.
        version_added: '2.12'
        type: str
      comment_end_string:
        description: The string marking the end of a comment statement.
        version_added: '2.12'
        type: str
"""

EXAMPLES = """
- name: show templating results
  debug:
    msg: "{{ lookup('templateVar', '{{40+2}}') }}"

- name: show templating results with different variable start and end string
  debug:
    msg: "{{ lookup('templateVar', '{{2+2}}', variable_start_string='[%', variable_end_string='%]') }}"
"""

RETURN = """
_raw:
   description: evaluated expression(s) after templating
   type: list
   elements: raw
"""

from copy import deepcopy
import os
from types import MethodType
import pprint
#from remote_pdb import set_trace, RemotePdb

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase
from ansible.module_utils._text import to_bytes, to_text
#from ansible.template import generate_ansible_template_vars, AnsibleEnvironment # , USE_JINJA2_NATIVE
from jinja2 import Environment, Template
from ansible.template import generate_ansible_template_vars
from ansible.template import Templar
from ansible.utils.display import Display

display = Display()

class LookupModule(LookupBase):

    def run(self, terms, variables, **kwargs):

        ret = []

        self.set_options(var_options=variables, direct=kwargs)

        # capture options
        convert_data_p = self.get_option('convert_data')
        lookup_template_vars = self.get_option('template_vars')
        jinja2_native = self.get_option('jinja2_native')
        variable_start_string = self.get_option('variable_start_string')
        variable_end_string = self.get_option('variable_end_string')
        comment_start_string = self.get_option('comment_start_string')
        comment_end_string = self.get_option('comment_end_string')

        templar = self._templar

        for template_data in terms:
            # Convert template_data to string if needed
            template_data = str(template_data)

            # Set up Jinja2 environment
            env = Environment(
                variable_start_string=variable_start_string,
                variable_end_string=variable_end_string,
                comment_start_string=comment_start_string,
                comment_end_string=comment_end_string,
                undefined=StrictUndefined if self._templar.environment.undefined == StrictUndefined else Undefined
            )

            # Set up search paths for includes
            searchpath = variables.get('ansible_search_path', [])
            if searchpath:
                newsearchpath = []
                for p in searchpath:
                    newsearchpath.append(os.path.join(p, 'templates'))
                    newsearchpath.append(p)
                searchpath = newsearchpath
            env.loader = FileSystemLoader(searchpath)

            # Prepare variables
            vars = deepcopy(variables)
            vars.update(lookup_template_vars)

            # Create and render template
            template = env.from_string(template_data)
            try:
                res = template.render(vars)
                ret.append(res)
            except Exception as e:
                raise AnsibleError(f"Failed to template variable: {str(e)}")

        return ret
