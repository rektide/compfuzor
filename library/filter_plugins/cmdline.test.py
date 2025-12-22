#!/usr/bin/env python3
"""Test script for ansible_cmdline filter"""

import sys
import os

# Add current directory to path to import the filter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cmdline import ansible_cmdline

def test_ansible_cmdline():
    """Test the ansible_cmdline filter"""
    
    print("Testing ansible_cmdline filter...")
    
    # Test 1: Basic pattern matching
    print("\nTest 1: Basic pattern matching")
    cmdline = '/usr/bin/python3 /usr/bin/ansible-playbook -vvvkK setup.bin.pb'
    result = ansible_cmdline(cmdline)
    print(f"cmdline: {cmdline}")
    print(f"Result: {result}")
    expected = {"type": "setup", "instance": "bin"}
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")
    
    # Test 2: Pattern in middle of cmdline
    print("\nTest 2: Pattern in middle of cmdline")
    cmdline = 'ansible-playbook --inventory hosts.ini deploy.web.pb --extra-vars "env=prod"'
    result = ansible_cmdline(cmdline)
    print(f"cmdline: {cmdline}")
    print(f"Result: {result}")
    expected = {"type": "deploy", "instance": "web"}
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")
    
    # Test 3: Pattern with different word characters
    print("\nTest 3: Pattern with different word characters")
    cmdline = 'ansible-playbook app_v2.production.pb --tags "deploy,config"'
    result = ansible_cmdline(cmdline)
    print(f"cmdline: {cmdline}")
    print(f"Result: {result}")
    expected = {"type": "app_v2", "instance": "production"}
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")
    
    # Test 4: Multiple .pb files, should find first match
    print("\nTest 4: Multiple .pb files, should find first match")
    cmdline = 'ansible-playbook first.one.pb second.two.pb third.three.pb'
    result = ansible_cmdline(cmdline)
    print(f"cmdline: {cmdline}")
    print(f"Result: {result}")
    expected = {"type": "first", "instance": "one"}
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")
    
    # Test 5: No .pb pattern found
    print("\nTest 5: No .pb pattern found")
    cmdline = 'ansible-playbook --inventory hosts.ini playbook.yml'
    result = ansible_cmdline(cmdline)
    print(f"cmdline: {cmdline}")
    print(f"Result: {result}")
    expected = {}
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")
    
    # Test 6: Empty cmdline
    print("\nTest 6: Empty cmdline")
    cmdline = ''
    result = ansible_cmdline(cmdline)
    print(f"cmdline: '{cmdline}'")
    print(f"Result: {result}")
    expected = {}
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")
    
    # Test 7: Pattern with quoted arguments
    print("\nTest 7: Pattern with quoted arguments")
    cmdline = 'ansible-playbook --extra-vars \'{"env":"prod"}\' config.db.pb --tags "setup"'
    result = ansible_cmdline(cmdline)
    print(f"cmdline: {cmdline}")
    print(f"Result: {result}")
    expected = {"type": "config", "instance": "db"}
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")
    
    # Test 8: Pattern with underscores and numbers
    print("\nTest 8: Pattern with underscores and numbers")
    cmdline = 'ansible-playbook api_v2.staging_2.pb --limit "web_servers"'
    result = ansible_cmdline(cmdline)
    print(f"cmdline: {cmdline}")
    print(f"Result: {result}")
    expected = {"type": "api_v2", "instance": "staging_2"}
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")
    
    # Test 9: Pattern at the beginning
    print("\nTest 9: Pattern at the beginning")
    cmdline = 'test.dev.pb --verbose --check'
    result = ansible_cmdline(cmdline)
    print(f"cmdline: {cmdline}")
    print(f"Result: {result}")
    expected = {"type": "test", "instance": "dev"}
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")
    
    # Test 10: Pattern at the end
    print("\nTest 10: Pattern at the end")
    cmdline = 'ansible-playbook --inventory hosts --extra-vars @vars.yml final.prod.pb'
    result = ansible_cmdline(cmdline)
    print(f"cmdline: {cmdline}")
    print(f"Result: {result}")
    expected = {"type": "final", "instance": "prod"}
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")

if __name__ == "__main__":
    test_ansible_cmdline()