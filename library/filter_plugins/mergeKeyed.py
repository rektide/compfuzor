def mergeKeyed(list1, list2, key="key"):
    """
    Merge two lists of objects by a key field.
    
    Concatenates the two lists together, but if any objects in both lists 
    have a field named `key` whose value is the same, those two objects 
    should be combined into a new merged object that is used in the list.
    
    Args:
        list1: First list
        list2: Second list  
        key: The field name to use for matching (default: "key")
    
    Returns:
        A merged list where objects with matching key values are combined
    """
    if not isinstance(list1, list):
        list1 = []
    if not isinstance(list2, list):
        list2 = []
    
    # Create a dictionary to track objects by their key value
    merged_dict = {}
    # Track non-dictionary items for equality matching
    non_dict_items = []
    
    # Process first list
    for item in list1:
        if isinstance(item, dict) and key in item:
            merged_dict[item[key]] = item.copy()
        else:
            # Track non-dictionary items for equality matching
            non_dict_items.append(item)
    
    # Process second list, merging with existing items
    for item in list2:
        if isinstance(item, dict) and key in item:
            key_value = item[key]
            if key_value in merged_dict:
                # Merge dictionaries, with second list values taking precedence
                merged_dict[key_value].update(item)
            else:
                merged_dict[key_value] = item.copy()
        else:
            # Check if this non-dictionary item exists in first list
            if item in non_dict_items:
                # Remove from non_dict_items since we're handling it
                non_dict_items.remove(item)
            # Add to result (will be appended at the end)
            non_dict_items.append(item)
    
    # Convert dictionary values to list and append non-dictionary items
    result = list(merged_dict.values()) + non_dict_items
    
    return result


class FilterModule(object):
    def filters(self):
        return {
            "mergeKeyed": mergeKeyed
        }