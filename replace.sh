#!/bin/bash

# Check if config.yaml exists
if [ ! -f "config.yaml" ]; then
    echo "Error: config.yaml not found"
    exit 1
fi

# Check if output.ini exists, create if it doesn't
if [ ! -f "output.ini" ]; then
    touch "output.ini"
fi

# Process each line in config.yaml
while IFS=':' read -r key value; do
    # Skip lines that start with # (comments)
    if [[ "$key" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Remove leading/trailing whitespace from key and value
    key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Skip empty lines or lines without proper key:value format
    if [ -z "$key" ] || [ -z "$value" ]; then
        continue
    fi
    
    # Check if the key already exists in output.ini
    if grep -q "^$key=" "output.ini"; then
        # Replace existing key=value line
        sed -i "s/^$key=.*/$key=$value/" "output.ini"
    else
        # Add new key=value line using sed append
        sed -i "\$a$key=$value" "output.ini"
    fi
done < "config.yaml"

echo "Configuration updated successfully"