#!/bin/bash
set -e
mkdir -p .tmp/simple_src .tmp/simple_dst/subdir
touch .tmp/simple_dst/subdir/badfile
touch .tmp/simple_dst/subdir/goodfile

files_to_remove="subdir/badfile"
Localdir=".tmp/simple_src"

# 1. Recreate directory structure in source
echo "$files_to_remove" | xargs -n1 dirname | sort -u | while read -r d; do
	mkdir -p "$Localdir/$d"
done

# 2. Run rsync with --include='*/' to traverse all dirs, but specific file includes
# Note: --include='*/' must come BEFORE --exclude='*'
# And we also need to include our specific files.
# Order:
# Include specific files
# Include all directories (so we traverse)
# Exclude everything else

echo "Running rsync..."
rsync -I -W -v -r --delete --include-from=- --include='*/' --exclude='*' "$Localdir"/ .tmp/simple_dst/ <<EOF
$files_to_remove
EOF

echo "Checking results..."
if [ -e .tmp/simple_dst/subdir/badfile ]; then
	echo "FAIL: badfile NOT removed"
	exit 1
else
	echo "SUCCESS: badfile removed"
fi

if [ ! -e .tmp/simple_dst/subdir/goodfile ]; then
	echo "FAIL: goodfile was INCORRECTLY removed"
	exit 1
else
	echo "SUCCESS: goodfile preserved"
fi
