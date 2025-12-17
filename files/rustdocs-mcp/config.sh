#!/bin/bash

# Script to generate files from either command-line arguments or crates.txt
# Usage with arguments: ./config.sh <crate> [features]
# Usage with crates.txt: ./config.sh
# Example: ./config.sh serde derive
# Example: ./config.sh tokio runtime,fs
# Example: ./config.sh  (reads from crates.txt)

set -e

# Set default template file
[ -n "$TEMPLATE_FILE" ] || TEMPLATE_FILE="etc/opencode-rustdocs-mcp.json.template"
[ -n "$CRATES" ] || CRATES=etc/crates.txt

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file '$TEMPLATE_FILE' not found"
    echo "Please create $TEMPLATE_FILE with $CRATE placeholders"
    exit 1
fi

# Read template content
TEMPLATE_CONTENT=$(cat "$TEMPLATE_FILE")

# Function to process a single crate
process_crate() {
    local crate="$1"
    local features="$2"

    # Generate filename based on crate name
    filename="${crate}.pb"

    # First replace $CRATE in the template
    TEMP_CONTENT="${TEMPLATE_CONTENT//\$CRATE/$crate}"

    # If features are specified, modify the command array with jq
    if [ -n "$features" ]; then
        # Use jq to add --features and the feature value to the command array
        OUTPUT_CONTENT=$(echo "$TEMP_CONTENT" | jq --arg features "$features" '
            ."mcp.rustdocs-\($crate)".command |= . + ["--features", $features]
        ')
    else
        OUTPUT_CONTENT="$TEMP_CONTENT"
    fi

    # Write to file
    echo "$OUTPUT_CONTENT" >"$filename"

    echo "Created: $filename (features: ${features:-none})"
}

# Check how script is being called
if [ $# -eq 0 ]; then
    # No arguments: read from CRATES
    if [ ! -f "$CRATES" ]; then
        echo "Error: $CRATES not found and no arguments provided"
        echo "Usage: $0 <crate> [features]"
        echo "Or create $CRATES with crate names (one per line)"
        echo "Optional second column for features"
        exit 1
    fi

    echo "Reading from $CRATES..."
    count=0
    while IFS= read -r line; do
        # Skip empty lines and comments
        [ -z "$line" ] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Parse crate name (first column) and optional features (second column)
        crate=$(echo "$line" | awk '{print $1}')
        features=$(echo "$line" | awk '{$1=""; print $0}' | xargs)

        # Remove leading/trailing whitespace from crate
        crate=$(echo "$crate" | xargs)

        process_crate "$crate" "$features"
        count=$((count + 1))
    done <"$CRATES"

    echo "Done! Generated $count files from crates.txt."

elif [ $# -eq 1 ]; then
    # Single argument: crate name only
    crate="$1"
    process_crate "$crate" ""
    echo "Done! Generated 1 file."

elif [ $# -eq 2 ]; then
    # Two arguments: crate name and features
    crate="$1"
    features="$2"
    process_crate "$crate" "$features"
    echo "Done! Generated 1 file."

else
    # Too many arguments
    echo "Error: Too many arguments"
    echo "Usage: $0 <crate> [features]"
    echo "Example: $0 serde derive"
    echo "Example: $0 tokio runtime,fs"
    echo "Or run without arguments to read from crates.txt"
    exit 1
fi
