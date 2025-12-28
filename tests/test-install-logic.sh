#!/bin/bash
set -u

# 1. Setup Sandbox
SANDBOX=$(mktemp -d)
REPO_ROOT=$(pwd)
trap 'rm -rf "$SANDBOX"' EXIT

echo "Running install logic tests in $SANDBOX..."

# 2. Copy artifacts AND the installer to the sandbox
# We copy install.sh so it sees the "mock" debian/redhat folders we create in the sandbox
cp git-remote-gcrypt "$SANDBOX"
cp README.rst "$SANDBOX" 2>/dev/null || touch "$SANDBOX/README.rst"
cp install.sh "$SANDBOX"

cd "$SANDBOX"

# Ensure the mock binary is executable (so the --version call works later)
chmod +x git-remote-gcrypt

# 3. Define the path to the SANDBOX installer
INSTALLER="./install.sh"

# Function to assert version output
assert_version() {
	EXPECTED_SUBSTRING="$1"

	# Reset environment for standard install
	PREFIX="$SANDBOX/usr"
	export prefix="$PREFIX"
	unset DESTDIR

	# Run the installer
	"$INSTALLER" >/dev/null 2>&1

	INSTALLED_BIN="$PREFIX/bin/git-remote-gcrypt"
	chmod +x "$INSTALLED_BIN"

	# CAPTURE FIX: Redirect 2>&1 and feed /dev/null to prevent hangs
	OUTPUT=$("$INSTALLED_BIN" --version 2>&1 </dev/null)

	if [[ "$OUTPUT" != *"$EXPECTED_SUBSTRING"* ]]; then
		echo "❌ FAILED: Expected '$EXPECTED_SUBSTRING' in output."
		echo "           Got: '$OUTPUT'"
		exit 1
	else
		echo "✅ PASS: Found version '$EXPECTED_SUBSTRING'"
	fi
}

# --- TEST 1: Fallback (No metadata files) ---
echo "--- Test 1: Fallback (Custom) ---"
rm -rf debian redhat
assert_version "unknown (custom)"

# --- TEST 2: RedHat Logic ---
echo "--- Test 2: RedHat Detection ---"
mkdir -p redhat
echo "Version: 9.9.9" >redhat/git-remote-gcrypt.spec
rm -rf debian
assert_version "9.9.9 (redhat)"

# --- TEST 3: Debian Logic ---
echo "--- Test 3: Debian Detection ---"
mkdir -p debian
echo "git-remote-gcrypt (5.5.5-1) unstable; urgency=low" >debian/changelog
assert_version "5.5.5-1 (debian)"

# --- TEST 4: DESTDIR Support ---
echo "--- Test 4: DESTDIR Support ---"
# Clear previous installs to ensure we catch DESTDIR failure
rm -rf "$SANDBOX/usr"

export DESTDIR="$SANDBOX/pkg_root"
export prefix="/usr"

"$INSTALLER" >/dev/null 2>&1

if [ -f "$SANDBOX/pkg_root/usr/bin/git-remote-gcrypt" ]; then
	echo "✅ PASS: DESTDIR honored"
else
	echo "❌ FAILED: Binary not found in DESTDIR ($SANDBOX/pkg_root/usr/bin)"
	exit 1
fi

echo "All install logic tests passed."
