# (c) 2012, Daniel Hokka Zakrisson <daniel@hozac.com>
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
from ansible.errors import AnsibleError, AnsibleParserError
from ansible.plugins.lookup import LookupBase

try:
	from __main__ import display
except ImportError:
	from ansible.utils.display import Display
	display = Display()

class LookupModule(LookupBase):
	def run(self, terms, variables=None, **kwargs):
		for term in terms:
			display.debug("Fileexists lookup term: %s" % term)
				if os.path.exists(term):
					return True
			## latter ansibles
			#try:
			#	lookupfile = self.find_file_in_search_path(variables, 'files', term)
			#	display.vvvv(u"Fileexists lookup using %s as file" % lookupfile)
			#	return True
			#except AnsibleError:
			#	
		return False
