#!/bin/bash
set -u

# Helpers
print_info() { printf "\033[1;36m%s\033[0m\n" "$1"; }
print_success() { printf "\033[1;34m✓ %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m%s\033[0m\n" "$1"; }

print_info "Verifying system install..."

# 1. Check if the command exists in the path
if ! command -v git-remote-gcrypt >/dev/null; then
	print_err "ERROR: git-remote-gcrypt is not in the PATH."
	exit 1
fi

# 2. Run the version check (Capture stderr too!)
OUTPUT=$(git-remote-gcrypt -v 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
	print_err "ERROR: Command exited with code $EXIT_CODE"
	exit 1
fi

# 3. Verify the placeholder was replaced
if [[ $OUTPUT == *"@@DEV_VERSION@@"* ]]; then
	print_err "ERROR: Version placeholder @@DEV_VERSION@@ was not replaced!"
	exit 1
fi

# 4. Determine expected ID for comparison to actual
if [ -f /etc/os-release ]; then
	# shellcheck source=/dev/null
	source /etc/os-release
	EXPECTED_ID=$ID
elif command -v uname >/dev/null; then
	EXPECTED_ID=$(uname -s | tr '[:upper:]' '[:lower:]')
else
	EXPECTED_ID="unknown_OS"
fi

if [[ $OUTPUT != *"($EXPECTED_ID)"* ]]; then
	print_err "ERROR: Distro ID '$EXPECTED_ID' missing from version string! (Got: $OUTPUT)"
	exit 1
fi

# LEAD with the version success
printf "  ✓ %s\n" "VERSION OK: $OUTPUT"

# 5. Verify the man page
if man -w git-remote-gcrypt >/dev/null 2>&1; then
	printf "  ✓ %s\n" "DOCS OK: Man page is installed and indexed."
else
	print_err "ERROR: Man page not found in system paths."
	exit 1
fi

print_success "INSTALLATION VERIFIED"
