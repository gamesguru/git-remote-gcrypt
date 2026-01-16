#!/bin/bash
set -u

# 1. Setup Sandbox
# 1. Setup Sandbox in project root to help kcov tracking
REPO_ROOT=$(pwd)
mkdir -p .tmp
SANDBOX=$(mktemp -d -p "$REPO_ROOT/.tmp" sandbox.XXXXXX)
# Use realpath for the sandbox to avoid any confusion
SANDBOX=$(realpath "$SANDBOX")
trap 'rm -rf "$SANDBOX"' EXIT

# Helpers
print_info() { printf "\033[1;36m[TEST] %s\033[0m\n" "$1"; }
print_success() { printf "\033[1;34m[TEST] ✓ %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m[TEST] FAIL: %s\033[0m\n" "$1"; }

print_info "Running install logic tests in $SANDBOX..."

# 2. Symlink/Copy artifacts
# Symlink core logic to help kcov find the source
ln -s "$REPO_ROOT/install.sh" "$SANDBOX/install.sh"
ln -s "$REPO_ROOT/git-remote-gcrypt" "$SANDBOX/git-remote-gcrypt"
ln -s "$REPO_ROOT/utils" "$SANDBOX/utils"
ln -s "$REPO_ROOT/completions" "$SANDBOX/completions"
# Copy README as it might be edited/checked
cp "$REPO_ROOT/README.rst" "$SANDBOX/"
cp "$REPO_ROOT/completions/templates/README.rst.in" "$SANDBOX/"

cd "$SANDBOX" || exit 2

# Ensure source binary has the placeholder for sed to work on
# If the local file already has a real version, inject the placeholder
if ! grep -q "@@DEV_VERSION@@" git-remote-gcrypt; then
	sed -i.bak 's/^VERSION=.*/VERSION="@@DEV_VERSION@@"/' git-remote-gcrypt 2>/dev/null \
		|| { sed 's/^VERSION=.*/VERSION="@@DEV_VERSION@@"/' git-remote-gcrypt >git-remote-gcrypt.tmp && mv git-remote-gcrypt.tmp git-remote-gcrypt; }
fi
chmod +x git-remote-gcrypt

INSTALLER="./install.sh"

assert_version() {
	EXPECTED_SUBSTRING="$1"
	PREFIX="$SANDBOX/usr"
	export prefix="$PREFIX"
	unset DESTDIR

	# Run the installer and capture output
	cat </dev/null | "bash" "$INSTALLER" >.install_log 2>&1 || {
		print_err "Installer failed unexpectedly. Output:"
		cat .install_log
		exit 1
	}
	rm -f .install_log

	INSTALLED_BIN="$PREFIX/bin/git-remote-gcrypt"
	chmod +x "$INSTALLED_BIN"

	OUTPUT=$("$INSTALLED_BIN" --version 2>&1 </dev/null)

	# CRITICAL: Use quotes around the variable to handle parentheses correctly
	if [[ $OUTPUT != *"$EXPECTED_SUBSTRING"* ]]; then
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
if "bash" "$INSTALLER" >/dev/null 2>&1; then
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
EXPECTED_TAG="5.5.5-1 ($OS_IDENTIFIER)"

assert_version "$EXPECTED_TAG"

# --- TEST 3: Prefix Support (Mac-idiomatic) ---
echo "--- Test 3: Prefix Support ---"
rm -rf "${SANDBOX:?}/usr"
export prefix="$SANDBOX/usr"
unset DESTDIR

"bash" "$INSTALLER" >/dev/null 2>&1 || {
	print_err "Installer FAILED"
	exit 1
}

if [ -f "$SANDBOX/usr/bin/git-remote-gcrypt" ]; then
	printf "  ✓ %s\n" "Prefix honored"
else
	print_err "FAILED: Binary not found in expected prefix location"
	exit 1
fi

# --- TEST 4: DESTDIR Support (Linux-idiomatic) ---
echo "--- Test 4: DESTDIR Support ---"
rm -rf "${SANDBOX:?}/pkg_root"
export prefix="/usr"
export DESTDIR="$SANDBOX/pkg_root"

"bash" "$INSTALLER" >/dev/null 2>&1 || {
	print_err "Installer FAILED"
	exit 1
}

if [ -f "$SANDBOX/pkg_root/usr/bin/git-remote-gcrypt" ]; then
	printf "  ✓ %s\n" "DESTDIR honored"
else
	print_err "FAILED: Binary not found in DESTDIR"
	exit 1
fi

# --- TEST 5: Permission Failure (Simulated) ---
echo "--- Test 5: Permission Failure (Simulated) ---"
# We act as root in some containers, so chmod -w won't stop writes.
# Instead, we mock 'install' to fail, ensuring error paths are hit.
SHADOW_BIN_FAIL="$SANDBOX/shadow_bin_install_fail"
mkdir -p "$SHADOW_BIN_FAIL"
cat >"$SHADOW_BIN_FAIL/install" <<EOF
#!/bin/sh
echo "Mock failure" >&2
exit 1
EOF
chmod +x "$SHADOW_BIN_FAIL/install"

if PATH="$SHADOW_BIN_FAIL:$PATH" prefix="$SANDBOX/usr" DESTDIR="" bash "$INSTALLER" >.install_log 2>&1; then
	print_err "FAILED: Installer should have failed due to install command failure"
	cat .install_log
	rm -rf "$SHADOW_BIN_FAIL"
	exit 1
else
	printf "  ✓ %s\n" "Installer failed gracefully on install error"
fi
rm -rf "$SHADOW_BIN_FAIL"

# --- TEST 6: Missing rst2man ---
echo "--- Test 6: Missing rst2man ---"
# Shadow rst2man in PATH
SHADOW_BIN="$SANDBOX/shadow_bin"
mkdir -p "$SHADOW_BIN"
cat >"$SHADOW_BIN/rst2man" <<EOF
#!/bin/sh
exit 127
EOF
chmod +x "$SHADOW_BIN/rst2man"
ln -sf "$SHADOW_BIN/rst2man" "$SHADOW_BIN/rst2man.py"

if PATH="$SHADOW_BIN:$PATH" prefix="$SANDBOX/usr" DESTDIR="" bash "$INSTALLER" >.install_log 2>&1; then
	printf "  ✓ %s\n" "Installer handled missing rst2man"
else
	print_err "Installer FAILED unexpectedly with missing rst2man. Output:"
	cat .install_log
	exit 1
fi

# --- TEST 7: OS Detection Fallbacks ---
echo "--- Test 7: OS Detection Fallbacks ---"
# 7a: Hit 'uname' path by mocking absence of /etc/os-release via OS_RELEASE_FILE
if prefix="$SANDBOX/usr" DESTDIR="" OS_RELEASE_FILE="$SANDBOX/nonexistent" bash "$INSTALLER" >.install_log 2>&1; then
	printf "  ✓ %s\n" "OS Detection: uname path hit"
else
	print_err "Installer FAILED in OS fallback (uname) path"
	exit 1
fi

# 7b: Hit 'unknown_OS' path by mocking absence of both
# We need to shadow 'uname' too
SHADOW_BIN_OS="$SANDBOX/shadow_bin_os"
mkdir -p "$SHADOW_BIN_OS"
cat >"$SHADOW_BIN_OS/uname" <<EOF
#!/bin/sh
exit 127
EOF
chmod +x "$SHADOW_BIN_OS/uname"

if PATH="$SHADOW_BIN_OS:$PATH" prefix="$SANDBOX/usr" DESTDIR="" OS_RELEASE_FILE="$SANDBOX/unknown" bash "$INSTALLER" >.install_log 2>&1; then
	printf "  ✓ %s\n" "OS Detection: unknown_OS path hit"
else
	print_err "Installer FAILED in unknown_OS fallback path"
	exit 1
fi
rm -rf "$SHADOW_BIN_OS" "$SHADOW_BIN"

# --- TEST 8: Termux PREFIX Auto-Detection ---
echo "--- Test 8: Termux PREFIX Auto-Detection ---"
# 8a: When /usr/local doesn't exist but PREFIX is set, use PREFIX
TERMUX_PREFIX="$SANDBOX/termux_prefix"
mkdir -p "$TERMUX_PREFIX/bin"
mkdir -p "$TERMUX_PREFIX/share/bash-completion/completions"
mkdir -p "$TERMUX_PREFIX/share/zsh/site-functions"
mkdir -p "$TERMUX_PREFIX/share/fish/vendor_completions.d"
mkdir -p "$TERMUX_PREFIX/share/man/man1"

# Unset prefix so auto-detection kicks in
unset prefix
unset DESTDIR

# Mock /usr/local as nonexistent by using a wrapper that interprets [ -d /usr/local ]
# Since we can't truly hide /usr/local, we modify the installer call to point elsewhere
# We copy the installer (breaking symlink) and patch it to check a nonexistent path instead of /usr/local

rm -f "$INSTALLER"
sed 's|/usr/local|/non/existent/path|g' "$REPO_ROOT/install.sh" >"$INSTALLER"
chmod +x "$INSTALLER"

# Run with PREFIX set but explicit prefix unset
if PREFIX="$TERMUX_PREFIX" bash "$INSTALLER" >.install_log 2>&1; then
	if [ -f "$TERMUX_PREFIX/bin/git-remote-gcrypt" ]; then
		printf "  ✓ %s\n" "Termux PREFIX auto-detection works"
	else
		# On systems with /usr/local the default is still used
		if grep -q "Detected Termux" .install_log; then
			print_err "FAILED: Termux detected but binary not in PREFIX"
			cat .install_log
			exit 1
		else
			printf "  ✓ %s\n" "Non-Termux: default prefix used (expected on Linux)"
		fi
	fi
else
	print_err "Installer FAILED in Termux PREFIX test"
	cat .install_log
	exit 1
fi

# 8b: When prefix is explicitly set, it should override PREFIX
echo "--- Test 8b: Explicit prefix overrides PREFIX ---"
rm -rf "$SANDBOX/explicit_prefix"
mkdir -p "$SANDBOX/explicit_prefix"

if PREFIX="$TERMUX_PREFIX" prefix="$SANDBOX/explicit_prefix" DESTDIR="" bash "$INSTALLER" >.install_log 2>&1; then
	if [ -f "$SANDBOX/explicit_prefix/bin/git-remote-gcrypt" ]; then
		printf "  ✓ %s\n" "Explicit prefix overrides PREFIX"
	else
		print_err "FAILED: Explicit prefix not honored"
		cat .install_log
		exit 1
	fi
else
	print_err "Installer FAILED in explicit prefix test"
	cat .install_log
	exit 1
fi
rm -rf "$TERMUX_PREFIX" "$SANDBOX/explicit_prefix"

print_success "All install logic tests passed."
[ -n "${COV_DIR:-}" ] && print_success "OK. Report: file://${COV_DIR}/index.html"

exit 0
