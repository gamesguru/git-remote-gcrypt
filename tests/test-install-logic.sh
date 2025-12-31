#!/bin/bash
set -u

# 1. Setup Sandbox
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# Helpers
print_info() { printf "\033[1;36m[TEST] %s\033[0m\n" "$1"; }
print_success() { printf "\033[1;34m[TEST] ✓ %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m[TEST] FAIL: %s\033[0m\n" "$1"; }

print_info "Running install logic tests in $SANDBOX..."

# 2. Copy artifacts
cp git-remote-gcrypt "$SANDBOX"
cp README.rst "$SANDBOX" 2>/dev/null || touch "$SANDBOX/README.rst"
cp install.sh "$SANDBOX"
cd "$SANDBOX" || exit 2

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
		print_err "FAILED: Expected '$EXPECTED_SUBSTRING' in output."
		print_err "        Got: '$OUTPUT'"
		exit 1
	else
		printf "  ✓ %s\n" "Found version '$EXPECTED_SUBSTRING'"
	fi
}

# --- TEST 1: Strict Metadata Requirement ---
echo "--- Test 1: Fail without Metadata ---"
rm -rf debian redhat
if "$INSTALLER" >/dev/null 2>&1; then
	print_err "FAILED: Installer should have exited 1 without debian/changelog"
	exit 1
else
	printf "  ✓ %s\n" "Installer strictly requires metadata"
fi

# --- TEST 2: Debian-sourced Versioning ---
echo "--- Test 2: Versioning from Changelog ---"
mkdir -p debian
echo "git-remote-gcrypt (5.5.5-1) unstable; urgency=low" >debian/changelog

# Determine the OS identifier for the test expectation
if [ -f /etc/os-release ]; then
	# shellcheck source=/dev/null
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
rm -rf "${SANDBOX:?}/usr"
export DESTDIR="$SANDBOX/pkg_root"
export prefix="/usr"

"$INSTALLER" >/dev/null 2>&1

if [ -f "$SANDBOX/pkg_root/usr/bin/git-remote-gcrypt" ]; then
	printf "  ✓ %s\n" "DESTDIR honored"
else
	print_err "FAILED: Binary not found in DESTDIR"
	exit 1
fi

print_success "All install logic tests passed."
[ -n "${COV_DIR:-}" ] && print_success "OK. Report: file://${COV_DIR}/index.html"

exit 0
