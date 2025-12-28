#!/bin/bash
set -u

# 1. Check if the command exists in the path
if ! command -v git-remote-gcrypt >/dev/null; then
	echo "❌ ERROR: git-remote-gcrypt is not in the PATH."
	exit 1
fi

# 2. Run the version check
OUTPUT=$(git-remote-gcrypt -v)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
	echo "❌ ERROR: Command exited with code $EXIT_CODE"
	exit 1
fi

# 3. Verify the placeholder was replaced
if [[ "$OUTPUT" == *"@@DEV_VERSION@@"* ]]; then
	echo "❌ ERROR: Version placeholder @@DEV_VERSION@@ was not replaced!"
	exit 1
fi

echo "✅ SUCCESS: Installed version is: $OUTPUT"
