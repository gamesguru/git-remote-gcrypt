#!/bin/bash
set -u

# Setup a sandbox directory for our fake environment
SANDBOX=$(mktemp -d)
ORIGINAL_DIR=$(pwd)
trap 'rm -rf "$SANDBOX"' EXIT

echo "Running install logic tests in $SANDBOX..."

# Copy necessary files to sandbox (exclude .git to simulate a clean tarball if needed)
cp -r install.sh git-remote-gcrypt "$SANDBOX"
cd "$SANDBOX"

# Function to assert version output
assert_version() {
	EXPECTED_SUBSTRING="$1"
	./install.sh
	# Execute the *installed* binary to check its version
	# Note: install.sh defaults to /usr/local, so we need to override prefix
	# to install it somewhere we can run it without sudo.
	PREFIX="$SANDBOX/usr"
	export prefix="$PREFIX"

	# Run install
	# Mute output for cleanliness
	./install.sh >/dev/null 2>&1

	INSTALLED_BIN="$PREFIX/bin/git-remote-gcrypt"

	if [ ! -f "$INSTALLED_BIN" ]; then
		echo "❌ FAILED: Binary not installed at $INSTALLED_BIN"
		exit 1
	fi

	OUTPUT=$($INSTALLED_BIN --version)
	if [[ "$OUTPUT" != *"$EXPECTED_SUBSTRING"* ]]; then
		echo "❌ FAILED: Expected '$EXPECTED_SUBSTRING' in output, got: '$OUTPUT'"
		exit 1
	else
		echo "✅ PASS: Found version '$EXPECTED_SUBSTRING'"
	fi
}

# --- TEST 1: Fallback (No metadata files) ---
echo "--- Test 1: Fallback (Custom) ---"
# Ensure no metadata exists
rm -rf debian redhat
assert_version "unknown (custom)"

# --- TEST 2: RedHat Logic ---
echo "--- Test 2: RedHat Detection ---"
mkdir redhat
echo "Version: 9.9.9" > redhat/git-remote-gcrypt.spec
# Ensure debian doesn't exist so it falls through to RH
rm -rf debian
assert_version "9.9.9 (redhat)"

# --- TEST 3: Debian Logic ---
echo "--- Test 3: Debian Detection ---"
mkdir debian
# Create a dummy changelog
echo "git-remote-gcrypt (5.5.5-1) unstable; urgency=low" > debian/changelog
assert_version "5.5.5-1 (debian)"

# --- TEST 4: DESTDIR Support (Crucial for packaging) ---
echo "--- Test 4: DESTDIR Support ---"
export DESTDIR="$SANDBOX/pkg_root"
export prefix="/usr"
./install.sh >/dev/null 2>&1

if [ -f "$SANDBOX/pkg_root/usr/bin/git-remote-gcrypt" ]; then
	echo "✅ PASS: DESTDIR honored"
else
	echo "❌ FAILED: Binary not found in DESTDIR ($SANDBOX/pkg_root/usr/bin)"
	exit 1
fi

echo "All install logic tests passed."
