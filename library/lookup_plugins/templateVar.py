
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
from ansible.template import generate_ansible_template_vars, AnsibleEnvironment# , USE_JINJA2_NATIVE
from ansible.template import Templar, AnsibleContext, AnsibleUndefined
from ansible.utils.display import Display
from ansible.utils.unsafe_proxy import to_unsafe_text


#USE_JINJA2_NATIVE = False
USE_JINJA2_NATIVE = True

if USE_JINJA2_NATIVE:
    from ansible.utils.native_jinja import NativeJinjaText

display = Display()

class FakeAnsibleContext(AnsibleContext):
    def __init__(self, *args, **kwargs):
        display.vvvv('Fake __init__')
        super(FakeAnsibleContext, self).__init__(*args, **kwargs)

    def _is_unsafe(self, val):
        display.vvvv('Fake _is_unsafe')
        return False

    def _update_unsafe(self, val):
        display.vvvv('Fake _update_unsafe')
        return None

def fakeIsUnsafe(self, val):
    display.vvvv('fake _is_unsafe')
    return False

def fakeUpdateUnsafe(self, val):
    display.vvvv('fake _is_unsafe')
    return False

def fakeLookup(self, name, *args, **kwargs):
    display.vvvv('fake _lookup')
    kwargs.set('allow_unsafe', True)
    return AnsibleTemplar._lookup(self, name, args, kwargs)

class FakeAnsibleEnvironment(AnsibleEnvironment):
    context_class = FakeAnsibleContext

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

        if USE_JINJA2_NATIVE and not jinja2_native:
            templar = self._templar.copy_with_new_env(environment_class=FakeAnsibleEnvironment)
        else:
            templar = self._templar


        for template_data in terms:

            # break AnsibleUnsafeText
            # failed attempts:
            #del template_data.__UNSAFE__
            #template_data = '%s' % template_data
            #template_data = ' %s' % template_data
            #template_data = (' %s' % template_data)[1:]
            #template_data = f'{template_data}'
            #template_data = '{}'.format(template_data)
            # ok:
            #template_data = template_data._strip_unsafe()
            #template_data = (' {}'.format(template_data))[1:]
            template_data = (f' {template_data}')[1:]

            if hasattr(template_data, '__UNSAFE__'):
                raise 'Failed to break AnsibleUnsafeText'

            #display.debug("File lookup term: %s" % term)
            #
            #lookupfile = self.find_file_in_search_path(variables, 'templates', term)
            #display.vvvv("File lookup using %s as file" % lookupfile)
            #if lookupfile:
            #    b_template_data, show_data = self._loader._get_file_contents(lookupfile)
            #    template_data = to_text(b_template_data, errors='surrogate_or_strict')

            # set jinja2 internal search path for includes
            searchpath = variables.get('ansible_search_path', [])
            if searchpath:
                # our search paths aren't actually the proper ones for jinja includes.
                # We want to search into the 'templates' subdir of each search path in
                # addition to our original search paths.
                newsearchpath = []
                for p in searchpath:
                    newsearchpath.append(os.path.join(p, 'templates'))
                    newsearchpath.append(p)
                searchpath = newsearchpath
            #searchpath.insert(0, os.path.dirname(lookupfile))

            # The template will have access to all existing variables,
            # plus some added by ansible (e.g., template_{path,mtime}),
            # plus anything passed to the lookup with the template_vars=
            # argument.
            vars = deepcopy(variables)
            #vars.update(generate_ansible_template_vars(term, lookupfile))
            vars.update(lookup_template_vars)

            #self.templar = Templar(None, variables=dict(content='yo'))
            #self.templar = Templar(None, variables=vars)
            #self._ansible_context = AnsibleContext(self.templar.environment, {}, {}, {})

            #res = self.templar.template(template_data)

            # save real context
            real_context_class = templar.environment.context_class
            real_context_class_nested = templar.environment.template_class.environment_class.context_class
            real_unsafe = templar.cur_context.unsafe
            #display.vvv(f'env cc {real_unsafe} {real_context_class} {real_context_class_nested} {real_context_class == real_context_class_nested}')
            #display.vvv(f'env cc {getattr(real_context_class, "unsafe", -1)} {getattr(real_context_class, "_is_unsafe", -1)}')

            # hack real context
            templar.environment.context_class = FakeAnsibleContext
            templar.environment.template_class.environment_class.context_class = FakeAnsibleContext
            templar.cur_context.unsafe = False
            templar.cur_context._is_unsafe = MethodType(fakeIsUnsafe, templar.cur_context)
            templar.cur_context._update_unsafe = MethodType(fakeUpdateUnsafe, templar.cur_context)

            # informational only: link to current contexts to compare if changed latter
            link_context = templar.environment.context_class
            link_context_nested = templar.environment.template_class.environment_class.context_class
            link_cur = templar.cur_context

            # enter temp context
            with templar.set_temporary_context(variable_start_string=variable_start_string,
                                               variable_end_string=variable_end_string,
                                               comment_start_string=comment_start_string,
                                               comment_end_string=comment_end_string,
                                               available_variables=vars, searchpath=searchpath):

                display.vvvvv(f'identity {link_context==templar.environment.context_class} {link_context_nested==templar.environment.template_class.environment_class.context_class} {link_context}:{link_context_nested}:{link_cur}')

                # save temporary context
                tmp_context_class = templar.environment.context_class
                tmp_context_class_nested = templar.environment.template_class.environment_class.context_class
                tmp_unsafe = templar.cur_context.unsafe
                display.vvvvv(f'env cc {real_unsafe}:{tmp_unsafe} {real_context_class}:{tmp_context_class}:{tmp_context_class_nested}')

                # hack temp context
                templar._lookup = MethodType(fakeLookup, templar)
                templar.environment.context_class = FakeAnsibleContext
                templar.environment.template_class.environment_class.context_class = FakeAnsibleContext
                templar.cur_context.unsafe = False
                templar.cur_context._is_unsafe = MethodType(fakeIsUnsafe, templar.cur_context)
                templar.cur_context._update_unsafe = MethodType(fakeUpdateUnsafe, templar.cur_context)

                # run
                #breakpoint();
                #set_trace()
                res = templar.template(template_data, preserve_trailing_newlines=True,
                                       convert_data=convert_data_p, escape_backslashes=False)

                # restore temp context
                templar.environment.context_class = tmp_context_class
                templar.environment.template_class.environment_class.context_class = tmp_context_class_nested
                templar.cur_context.unsafe = tmp_unsafe
                del templar.cur_context._is_unsafe
                del templar.cur_context._update_unsafe
                del templar._lookup

            if USE_JINJA2_NATIVE and not jinja2_native:
                # jinja2_native is true globally but off for the lookup, we need this text
                # not to be processed by literal_eval anywhere in Ansible
                res = NativeJinjaText(res)

            # restore real context
            templar.environment.context_class = real_context_class
            templar.environment.template_class.environment_class.context_class = real_context_class_nested
            templar.cur_context.unsafe = real_unsafe
            # gone
            #del templar.cur_context._is_unsafe
            #del templar.cur_context._update_unsafe

            ret.append(res)

        return ret
