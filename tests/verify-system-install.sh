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

# 4. Determine expected ID for comparison to actual
if [ -f /etc/os-release ]; then
	source /etc/os-release
	EXPECTED_ID=$ID
elif command -v uname >/dev/null; then
	EXPECTED_ID=$(uname -s | tr '[:upper:]' '[:lower:]')
else
	EXPECTED_ID="unknown_OS"
fi

if [[ "$OUTPUT" != *"(deb running on $EXPECTED_ID)"* ]]; then
	echo "❌ ERROR: Distro ID '$EXPECTED_ID' missing from version string! (Got: $OUTPUT)"
	exit 1
fi

# LEAD with the version success
echo "✅ VERSION OK: $OUTPUT"

# 5. Verify the man page
if man -w git-remote-gcrypt >/dev/null 2>&1; then
	echo "✅ DOCS OK: Man page is installed and indexed."
else
	echo "❌ ERROR: Man page not found in system paths."
	exit 1
fi

echo "🚀 INSTALLATION VERIFIED"
