#!/bin/bash
# filepath: /home/jihwankim/e2e/tests/lxly/assets/convert_acts_to_json.sh

input_file="${1:-output.txt}"
output_file="${2:-bridge-tests-suite-acts.json}"

# Check if input file exists
if [[ ! -f "$input_file" ]]; then
    echo "Error: Input file '$input_file' not found"
    exit 1
fi

# Start JSON array
echo "[" > "$output_file"

# Process the ACTS output
awk '
BEGIN {
    in_config = 0
    config_count = 0
    
    # Initialize variables
    dest_addr = ""
    bridge_type = ""
    token = ""
    metadata = ""
    force_update = ""
    amount = ""
    expected_process = ""
    expected_claim = ""
}

# Start of a configuration block
/^Configuration #[0-9]+:/ {
    in_config = 1
    
    # Reset variables for new configuration
    dest_addr = ""
    bridge_type = ""
    token = ""
    metadata = ""
    force_update = ""
    amount = ""
    expected_process = ""
    expected_claim = ""
    next
}

# End of configuration block (separator line)
/^-------------------------------------$/ {
    if (in_config && dest_addr != "") {
        # Add comma if not first entry
        if (config_count > 0) {
            print ","
        }
        
        # Print JSON object
        print "    {"
        print "        \"DestinationAddress\": \"" dest_addr "\","
        print "        \"BridgeType\": \"" bridge_type "\","
        print "        \"Token\": \"" token "\","
        print "        \"MetaData\": \"" metadata "\","
        print "        \"ForceUpdate\": \"" force_update "\","
        print "        \"Amount\": \"" amount "\","
        print "        \"ExpectedResultProcess\": \"" expected_process "\","
        print "        \"ExpectedResultClaim\": \"" expected_claim "\""
        printf "    }"
        
        config_count++
    }
    in_config = 0
    next
}

# Parse configuration lines
in_config && /^[0-9]+ = / {
    # Remove leading number and " = "
    line = $0
    gsub(/^[0-9]+ = /, "", line)
    
    if (line ~ /^DestinationAddress=/) {
        gsub(/^DestinationAddress=/, "", line)
        dest_addr = line
    }
    else if (line ~ /^BridgeType=/) {
        gsub(/^BridgeType=/, "", line)
        bridge_type = line
    }
    else if (line ~ /^Token=/) {
        gsub(/^Token=/, "", line)
        token = line
    }
    else if (line ~ /^MetaData=/) {
        gsub(/^MetaData=/, "", line)
        metadata = line
    }
    else if (line ~ /^ForceUpdate=/) {
        gsub(/^ForceUpdate=/, "", line)
        force_update = line
    }
    else if (line ~ /^Amount=/) {
        gsub(/^Amount=/, "", line)
        amount = line
    }
    else if (line ~ /^ExpectedResultProcess=/) {
        gsub(/^ExpectedResultProcess=/, "", line)
        expected_process = line
    }
    else if (line ~ /^ExpectedResultClaim=/) {
        gsub(/^ExpectedResultClaim=/, "", line)
        expected_claim = line
    }
}

END {
    # Handle last configuration if file doesn'\''t end with separator
    if (in_config && dest_addr != "") {
        if (config_count > 0) {
            print ","
        }
        print "    {"
        print "        \"DestinationAddress\": \"" dest_addr "\","
        print "        \"BridgeType\": \"" bridge_type "\","
        print "        \"Token\": \"" token "\","
        print "        \"MetaData\": \"" metadata "\","
        print "        \"ForceUpdate\": \"" force_update "\","
        print "        \"Amount\": \"" amount "\","
        print "        \"ExpectedResultProcess\": \"" expected_process "\","
        print "        \"ExpectedResultClaim\": \"" expected_claim "\""
        printf "    }"
    }
    print ""
    print "]"
}
' "$input_file" >> "$output_file"

echo "Conversion complete! Generated $output_file with $(grep -c '"DestinationAddress"' "$output_file") test configurations."

# Validate JSON syntax
if command -v jq >/dev/null 2>&1; then
    if jq empty "$output_file" 2>/dev/null; then
        echo "✓ Generated JSON is valid"
    else
        echo "✗ Generated JSON has syntax errors"
        exit 1
    fi
else
    echo "Note: Install 'jq' to validate JSON syntax"
fi