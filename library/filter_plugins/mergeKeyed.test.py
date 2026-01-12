#!/usr/bin/env python3
"""Test script for mergeKeyed filter"""

import sys
import os

# Add current directory to path to import the filter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mergeKeyed import mergeKeyed

def test_mergeKeyed():
    """Test the mergeKeyed filter"""
    
    print("Testing mergeKeyed filter...")
    
    # Test 1: Basic dictionary merging
    print("\nTest 1: Basic dictionary merging")
    list1 = [{"key": "a", "value": 1}, {"key": "b", "value": 2}]
    list2 = [{"key": "a", "value": 3, "extra": "x"}, {"key": "c", "value": 4}]
    result = mergeKeyed(list1, list2, key="key")
    print(f"list1: {list1}")
    print(f"list2: {list2}")
    print(f"Result: {result}")
    expected = [
        {"key": "a", "value": 3, "extra": "x"},  # Merged with list2 taking precedence
        {"key": "b", "value": 2},
        {"key": "c", "value": 4}
    ]
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")
    
    # Test 2: Non-dictionary items with equality
    print("\nTest 2: Non-dictionary items with equality")
    list1 = ["apple", "banana", {"key": "x", "val": 1}]
    list2 = ["banana", "cherry", {"key": "x", "val": 2, "extra": "y"}]
    result = mergeKeyed(list1, list2, key="key")
    print(f"list1: {list1}")
    print(f"list2: {list2}")
    print(f"Result: {result}")
    # "banana" should appear only once, dictionaries should merge
    expected = [
        {"key": "x", "val": 2, "extra": "y"},
        "apple",
        "banana",
        "cherry"
    ]
    print(f"Expected: {expected}")
    print(f"Pass: {sorted(str(r) for r in result) == sorted(str(e) for e in expected)}")
    
    # Test 3: Mixed types
    print("\nTest 3: Mixed types")
    list1 = [1, 2, {"key": "id1", "name": "Alice"}]
    list2 = [2, 3, {"key": "id1", "age": 30}]
    result = mergeKeyed(list1, list2, key="key")
    print(f"list1: {list1}")
    print(f"list2: {list2}")
    print(f"Result: {result}")
    # 2 should appear only once, dictionaries should merge
    expected = [
        {"key": "id1", "name": "Alice", "age": 30},
        1, 2, 3
    ]
    print(f"Expected: {expected}")
    print(f"Pass: {sorted(str(r) for r in result) == sorted(str(e) for e in expected)}")
    
    # Test 4: Empty lists
    print("\nTest 4: Empty lists")
    result = mergeKeyed([], [], key="key")
    print(f"Result: {result}")
    print(f"Pass: {result == []}")
    
    # Test 5: Non-list inputs
    print("\nTest 5: Non-list inputs")
    result = mergeKeyed("not a list", {"key": "x"}, key="key")
    print(f"Result: {result}")
    print(f"Pass: {result == []}")
    
    # Test 6: Custom key name
    print("\nTest 6: Custom key name")
    list1 = [{"id": "a", "val": 1}, {"id": "b", "val": 2}]
    list2 = [{"id": "a", "val": 3}, {"id": "c", "val": 4}]
    result = mergeKeyed(list1, list2, key="id")
    print(f"list1: {list1}")
    print(f"list2: {list2}")
    print(f"Result: {result}")
    expected = [
        {"id": "a", "val": 3},
        {"id": "b", "val": 2},
        {"id": "c", "val": 4}
    ]
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")
    
    # Test 7: Dictionary without key field
    print("\nTest 7: Dictionary without key field")
    list1 = [{"name": "Alice"}, {"key": "x", "val": 1}]
    list2 = [{"name": "Bob"}, {"key": "x", "val": 2}]
    result = mergeKeyed(list1, list2, key="key")
    print(f"list1: {list1}")
    print(f"list2: {list2}")
    print(f"Result: {result}")
    # Dictionaries without 'key' field should be treated as non-dictionary items
    expected = [
        {"key": "x", "val": 2},
        {"name": "Alice"},
        {"name": "Bob"}
    ]
    print(f"Expected: {expected}")
    print(f"Pass: {sorted(str(r) for r in result) == sorted(str(e) for e in expected)}")

    # Test 8: concat_fields with strings
    print("\nTest 8: concat_fields with strings")
    list1 = [{"name": "build", "generated": "go build"}]
    list2 = [{"name": "build", "generated": "make install"}]
    result = mergeKeyed(list1, list2, key="name", concat_fields=["generated"])
    print(f"list1: {list1}")
    print(f"list2: {list2}")
    print(f"Result: {result}")
    expected = [{"name": "build", "generated": "go build\nmake install"}]
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")

    # Test 9: concat_fields with lists
    print("\nTest 9: concat_fields with lists")
    list1 = [{"name": "build", "generated": ["go build", "go test"]}]
    list2 = [{"name": "build", "generated": ["make install"]}]
    result = mergeKeyed(list1, list2, key="name", concat_fields=["generated"])
    print(f"list1: {list1}")
    print(f"list2: {list2}")
    print(f"Result: {result}")
    expected = [{"name": "build", "generated": ["go build", "go test", "make install"]}]
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")

    # Test 10: concat_fields with mismatched types
    print("\nTest 10: concat_fields with mismatched types")
    list1 = [{"name": "build", "generated": "go build", "other": 1}]
    list2 = [{"name": "build", "generated": ["make install"], "other": 2}]
    result = mergeKeyed(list1, list2, key="name", concat_fields=["generated"])
    print(f"list1: {list1}")
    print(f"list2: {list2}")
    print(f"Result: {result}")
    # Mismatched types fall back to replacement
    expected = [{"name": "build", "generated": ["make install"], "other": 2}]
    print(f"Expected: {expected}")
    print(f"Pass: {result == expected}")

    # Test 11: concat_fields with non-matching keys
    print("\nTest 11: concat_fields with non-matching keys")
    list1 = [{"name": "build", "generated": "go build"}, {"name": "test", "generated": "go test"}]
    list2 = [{"name": "deploy", "generated": "make deploy"}]
    result = mergeKeyed(list1, list2, key="name", concat_fields=["generated"])
    print(f"list1: {list1}")
    print(f"list2: {list2}")
    print(f"Result: {result}")
    # No merging, all items included
    expected = [
        {"name": "build", "generated": "go build"},
        {"name": "test", "generated": "go test"},
        {"name": "deploy", "generated": "make deploy"}
    ]
    print(f"Expected: {expected}")
    print(f"Pass: {sorted(str(r) for r in result) == sorted(str(e) for e in expected)}")

if __name__ == "__main__":
    test_mergeKeyed()