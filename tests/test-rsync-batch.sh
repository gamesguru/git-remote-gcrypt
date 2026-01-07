#!/bin/bash
set -e

# Mock rsync to verify batching
cat <<'EOF' >"$Tempdir/rsync"
#!/bin/bash
TRACELOG="${TRACELOG_PATH}"
echo "MOCK RSYNC CALLED with args: $*" >> "$TRACELOG"
# Simulate download if --files-from is used
if [[ "$*" == *"--files-from"* ]]; then
    # Parse --files-from argument value
    # simple parsing
    for arg in "$@"; do
        if [[ "$arg" == --files-from=* ]]; then
            listfile="${arg#*=}"
            # Create dummy batch files
            batch_dir="$BatchDir"
            chmod 700 "$batch_dir"
            while read -r file; do
                    mkdir -p "$batch_dir"
                    echo "dummy content for $file" > "$batch_dir/$file"
            done < "$listfile"
        fi
    done
fi
EOF
chmod +x "$Tempdir/rsync"
PATH="$Tempdir:$PATH"
export TRACELOG_PATH="$TRACELOG"
export BatchDir="$Tempdir/batch"

# Helper to source git-remote-gcrypt functions
source_script() {
	# Find the line number where the main logic starts
	# We look for the "if [ "$NAME" = "dummy-gcrypt-check" ]; then" line
	start_line=$(grep -n "dummy-gcrypt-check" ./git-remote-gcrypt | cut -d: -f1 || echo "")
	echo "DEBUG: start_line=$start_line"
	if [ -z "$start_line" ]; then
		echo "ERROR: Could not find start line for sourcing."
		grep "dummy-gcrypt-check" ./git-remote-gcrypt || echo "Grep failed to find pattern"
		exit 1
	fi
	# Extract everything up to that line (exclusive)
	head -n "$((start_line - 1))" ./git-remote-gcrypt >"$Tempdir/funcs.sh"
	source "$Tempdir/funcs.sh"
}

# Test Setup
Tempdir=$(mktemp -d)
Localdir="$Tempdir/local"
mkdir -p "$Localdir"
mkdir -p "$Localdir/objects/pack"
TRACELOG="$Tempdir/trace.log"
URL="rsync://example.com/repo"
GITCEPTION=""
Hex40="0000000000000000000000000000000000000000"

source_script

# Redefine other deps we don't want to run
gpg_hash() { echo "mockhash"; }
DECRYPT() { cat; }
check_safety() { :; }
# Mock get_verify_decrypt_pack to simplify (since we care about the rsync call)
get_verify_decrypt_pack() {
	# Just call GET to trigger our logic
	GET "$URL" "$2" "$Tempdir/packF"
}
# Mock git index-pack
git() { :; }

echo "Running Batch Test..."

# Create a mock Packlist with 3 packs
cat <<EOF >"$Tempdir/input_packs"
pack :SHA256:pack1 hash1
pack :SHA256:pack2 hash2
pack :SHA256:pack3 hash3
EOF

Packlist=$(cat "$Tempdir/input_packs")
echo "DEBUG input_packs content:"
cat "$Tempdir/input_packs"

echo "DEBUG Running get_pack_files..."
# Run get_pack_files with input from the "missing packs" (simulated)
# In real flow, this input comes from pneed_
cat "$Tempdir/input_packs" | get_pack_files

echo "DEBUG batch_list content:"
if [ -f "$Tempdir/batch/batch_list" ]; then
	cat "$Tempdir/batch/batch_list"
else
	# logic uses $Tempdir/batch_list not $Tempdir/batch/batch_list
	if [ -f "$Tempdir/batch_list" ]; then
		cat "$Tempdir/batch_list"
	else
		echo "batch_list not found!"
	fi
fi

# Verify trace
count=$(grep -c "MOCK RSYNC CALLED" "$TRACELOG")
echo "Rsync called $count times."

if [ "$count" -eq 1 ]; then
	echo "SUCCESS: Rsync called exactly once."
	cat "$TRACELOG"
else
	echo "FAILURE: Rsync called $count times (expected 1)."
	cat "$TRACELOG"
	exit 1
fi

# rm -rf "$Tempdir"
echo "Trace log at $TRACELOG"
