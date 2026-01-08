#!/bin/bash
# Test: clean command removes unencrypted files
# This test verifies that git-remote-gcrypt clean correctly identifies
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

# --------------------------------------------------
# Set up test environment
# --------------------------------------------------
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

# Test helper
assert_grep() {
	local pattern="$1"
	local input="$2"
	local msg="$3"
	if echo "$input" | grep -q "$pattern"; then
		print_success "$msg"
	else
		print_err "$msg - Pattern '$pattern' not found"
		echo "Output: $input"
		exit 1
	fi
}

# --------------------------------------------------
# Test 1: Usage message when no remotes found
# --------------------------------------------------
print_info "Test 1: Usage message..."
mkdir "$tempdir/empty" && cd "$tempdir/empty" && $GIT init >/dev/null
output=$("$SCRIPT_DIR/git-remote-gcrypt" clean 2>&1 || :)
assert_grep "Usage: git-remote-gcrypt clean" "$output" "clean shows usage when no URL/remote found"

# --------------------------------------------------
# Test 2: Default scan-only mode
# --------------------------------------------------
print_info "Test 2: Default scan-only mode..."
cd "$tempdir/remote.git"
output=$("$SCRIPT_DIR/git-remote-gcrypt" clean "$tempdir/remote.git" 2>&1)
assert_grep "secret1.txt" "$output" "clean identifies unencrypted files"
assert_grep "NOTE: This is a scan" "$output" "clean defaults to scan-only mode"

if $GIT ls-tree HEAD | grep -q "secret1.txt"; then
	print_success "Files still exist after default scan"
else
	print_err "Default scan incorrectly deleted files!"
	exit 1
fi

# --------------------------------------------------
# Test 3: Remote resolution
# --------------------------------------------------
print_info "Test 3: Remote resolution..."
mkdir -p "$tempdir/client" && cd "$tempdir/client" && $GIT init >/dev/null
$GIT remote add origin "$tempdir/remote.git"
output=$("$SCRIPT_DIR/git-remote-gcrypt" clean origin 2>&1)
assert_grep "Checking remote: $tempdir/remote.git" "$output" "clean resolved 'origin' to URL"

# --------------------------------------------------
# Test 4: Remote listing
# --------------------------------------------------
print_info "Test 4: Remote listing..."
$GIT remote add gcrypt-origin "gcrypt::$tempdir/remote.git"
output=$("$SCRIPT_DIR/git-remote-gcrypt" clean 2>&1 || :)
assert_grep "Available gcrypt remotes:" "$output" "clean lists remotes"
assert_grep "gcrypt-origin" "$output" "clean listed 'gcrypt-origin'"

# --------------------------------------------------
# Test 5: Force cleanup
# --------------------------------------------------
print_info "Test 5: Force cleanup..."
"$SCRIPT_DIR/git-remote-gcrypt" clean "$tempdir/remote.git" --force >/dev/null 2>&1
if $GIT -C "$tempdir/remote.git" ls-tree HEAD 2>/dev/null | grep -q "secret"; then
	print_err "Files still exist after force cleanup!"
	exit 1
else
	print_success "Files removed after clean --force"
fi

# --------------------------------------------------
# Test 6: check command
# --------------------------------------------------
print_info "Test 6: check command..."
output=$("$SCRIPT_DIR/git-remote-gcrypt" check "$tempdir/remote.git" 2>&1 || :)
assert_grep "gcrypt: Checking remote:" "$output" "check command is recognized"

print_success "All clean/check command tests passed!"
