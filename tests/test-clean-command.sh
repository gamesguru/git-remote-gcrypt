#!/bin/bash
# Test: --clean command removes unencrypted files
# This test verifies that git-remote-gcrypt --clean correctly identifies
# and removes unencrypted files from a remote.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_info() { echo -e "${CYAN}$*${NC}"; }
print_success() { echo -e "${GREEN}✓ $*${NC}"; }
print_err() { echo -e "${RED}✗ $*${NC}"; }

# Ensure we use the local git-remote-gcrypt
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR:$PATH"

# Suppress git advice messages
GIT="git -c advice.defaultBranchName=false"

# Create temp directory
tempdir=$(mktemp -d)
trap 'rm -rf "$tempdir"' EXIT

print_info "Setting up test environment..."

# Create a bare repo with dirty files
$GIT init --bare "$tempdir/remote.git" >/dev/null
cd "$tempdir/remote.git"
$GIT config user.email "test@test.com"
$GIT config user.name "Test"

# Add multiple unencrypted files
echo "SECRET=abc" >"$tempdir/secret1.txt"
echo "PASSWORD=xyz" >"$tempdir/secret2.txt"
BLOB1=$($GIT hash-object -w "$tempdir/secret1.txt")
BLOB2=$($GIT hash-object -w "$tempdir/secret2.txt")
TREE=$(echo -e "100644 blob $BLOB1\tsecret1.txt\n100644 blob $BLOB2\tsecret2.txt" | $GIT mktree)
COMMIT=$(echo "Dirty commit" | $GIT commit-tree "$TREE")
$GIT update-ref refs/heads/master "$COMMIT"

print_info "Created dirty remote with 2 unencrypted files"

# Test 1: clean without URL/remotes shows usage
print_info "Test 1: Usage message..."
# First, ensure no gcrypt remotes in a fresh tmp repo
mkdir "$tempdir/no-remotes"
cd "$tempdir/no-remotes"
$GIT init >/dev/null
output=$("$SCRIPT_DIR/git-remote-gcrypt" clean 2>&1 || :)
if echo "$output" | grep -q "Usage: git-remote-gcrypt clean"; then
	print_success "clean shows usage when no URL/remote found"
else
	print_err "clean should show usage when no URL/remote found"
	echo "$output"
	exit 1
fi

# Test 2: clean (default) is scan-only
print_info "Test 2: Default scan-only mode..."
# Go to the remote repo (it is a git repo, so git-remote-gcrypt can run)
cd "$tempdir/remote.git"
output=$("$SCRIPT_DIR/git-remote-gcrypt" clean "$tempdir/remote.git" 2>&1)
if echo "$output" | grep -q "secret1.txt" && echo "$output" | grep -q "NOTE: This is a scan"; then
	print_success "clean defaults to scan-only? OK."
else
	print_err "clean defaults scan? Failed!"
	echo "$output"
	exit 1
fi

# Verify files still exist
if $GIT -C "$tempdir/remote.git" ls-tree HEAD | grep -q "secret1.txt"; then
	print_success "Files still exist after default scan"
else
	print_err "Default scan incorrectly deleted files!"
	exit 1
fi

# Test 3: Scan by remote name...
print_info "Test 3: Scan by remote name..."
$GIT init "$tempdir/client" >/dev/null
cd "$tempdir/client"
$GIT remote add origin "$tempdir/remote.git"
output=$("$SCRIPT_DIR/git-remote-gcrypt" clean origin 2>&1)
if echo "$output" | grep -q "Checking remote: $tempdir/remote.git"; then
	print_success "clean resolved 'origin' to URL"
else
	print_err "clean failed to resolve 'origin'"
	echo "$output"
	exit 1
fi

# Test 4: clean (no args) automatic discovery
print_info "Test 4: Automatic discovery..."
# Add a gcrypt:: remote to enable discovery
$GIT remote add gcrypt-origin "gcrypt::$tempdir/remote.git"
output=$("$SCRIPT_DIR/git-remote-gcrypt" clean 2>&1)
if echo "$output" | grep -q "Checking remote: gcrypt::$tempdir/remote.git"; then
	print_success "clean discovered gcrypt remotes automatically"
else
	print_err "clean failed automatic discovery"
	echo "$output"
	exit 1
fi

# Test 5: clean --force deletes files
print_info "Test 5: Force cleanup..."
"$SCRIPT_DIR/git-remote-gcrypt" clean "$tempdir/remote.git" --force 2>&1

# Verify files are gone
if $GIT -C "$tempdir/remote.git" ls-tree HEAD 2>/dev/null | grep -q "secret"; then
	print_err "Files still exist after cleanup!"
	$GIT -C "$tempdir/remote.git" ls-tree HEAD
	exit 1
else
	print_success "Files removed after clean --force"
fi

# Test 6: check command is recognized
print_info "Test 6: check command..."
output=$("$SCRIPT_DIR/git-remote-gcrypt" check "$tempdir/remote.git" 2>&1 || :)
if echo "$output" | grep -q "gcrypt: Checking remote:"; then
	print_success "check command is recognized"
else
	print_err "check command failed"
	echo "$output"
	exit 1
fi

print_success "All clean/check command tests passed!"
