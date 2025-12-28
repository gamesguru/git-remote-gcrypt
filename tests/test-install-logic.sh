#!/bin/bash
set -u

# 1. Setup Sandbox
SANDBOX=$(mktemp -d)
REPO_ROOT=$(pwd)
trap 'rm -rf "$SANDBOX"' EXIT

echo "Running install logic tests in $SANDBOX..."

# 2. Copy artifacts
cp git-remote-gcrypt "$SANDBOX"
cp README.rst "$SANDBOX" 2>/dev/null || touch "$SANDBOX/README.rst"
cp install.sh "$SANDBOX"
cd "$SANDBOX"

# Ensure source binary has the placeholder for sed to work on
# If your local git-remote-gcrypt already has a real version, sed won't find the tag
if ! grep -q "@@DEV_VERSION@@" git-remote-gcrypt; then
	echo 'VERSION="@@DEV_VERSION@@"' >git-remote-gcrypt
fi
chmod +x git-remote-gcrypt

INSTALLER="./install.sh"

assert_version() {
	EXPECTED_SUBSTRING="$1"
	PREFIX="$SANDBOX/usr"
	export prefix="$PREFIX"
	unset DESTDIR

	# Run the installer
	"$INSTALLER" >/dev/null 2>&1 || {
		echo "Installer failed unexpectedly"
		return 1
	}

	INSTALLED_BIN="$PREFIX/bin/git-remote-gcrypt"
	chmod +x "$INSTALLED_BIN"

	OUTPUT=$("$INSTALLED_BIN" --version 2>&1 </dev/null)

	# CRITICAL: Use quotes around the variable to handle parentheses correctly
	if [[ "$OUTPUT" != *"$EXPECTED_SUBSTRING"* ]]; then
		echo "❌ FAILED: Expected '$EXPECTED_SUBSTRING' in output."
		echo "           Got: '$OUTPUT'"
		exit 1
	else
		echo "✅ PASS: Found version '$EXPECTED_SUBSTRING'"
	fi
}

# --- TEST 1: Strict Metadata Requirement ---
echo "--- Test 1: Fail without Metadata ---"
rm -rf debian redhat
if "$INSTALLER" >/dev/null 2>&1; then
	echo "❌ FAILED: Installer should have exited 1 without debian/changelog"
	exit 1
else
	echo "✅ PASS: Installer strictly requires metadata"
fi

# --- TEST 2: Debian-sourced Versioning ---
echo "--- Test 2: Versioning from Changelog ---"
mkdir -p debian
echo "git-remote-gcrypt (5.5.5-1) unstable; urgency=low" >debian/changelog

# Determine the OS identifier for the test expectation
if [ -f /etc/os-release ]; then
	source /etc/os-release
	OS_IDENTIFIER="$ID"
elif command -v uname >/dev/null; then
	OS_IDENTIFIER=$(uname -s | tr '[:upper:]' '[:lower:]')
else
	OS_IDENTIFIER="unknown_os"
fi

# Use the identified OS for the expected string
EXPECTED_TAG="5.5.5-1 (deb running on $OS_IDENTIFIER)"

assert_version "$EXPECTED_TAG"

# --- TEST 3: DESTDIR Support ---
echo "--- Test 3: DESTDIR Support ---"
rm -rf "$SANDBOX/usr"
export DESTDIR="$SANDBOX/pkg_root"
export prefix="/usr"

"$INSTALLER" >/dev/null 2>&1

if [ -f "$SANDBOX/pkg_root/usr/bin/git-remote-gcrypt" ]; then
	echo "✅ PASS: DESTDIR honored"
else
	echo "❌ FAILED: Binary not found in DESTDIR"
	exit 1
fi

echo "All install logic tests passed."
