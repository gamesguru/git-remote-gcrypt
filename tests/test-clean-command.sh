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

# Test 1: --clean without URL shows usage
print_info "Test 1: Usage message..."
if "$SCRIPT_DIR/git-remote-gcrypt" --clean 2>&1 | grep -q "Usage"; then
	print_success "--clean shows usage when URL missing"
else
	print_err "--clean should show usage when URL missing"
	exit 1
fi

# Test 2: --clean --dry-run shows files without deleting
print_info "Test 2: Dry run mode..."
output=$("$SCRIPT_DIR/git-remote-gcrypt" --clean "$tempdir/remote.git" --dry-run 2>&1)
if echo "$output" | grep -q "secret1.txt" && echo "$output" | grep -q "Dry run"; then
	print_success "--clean --dry-run shows files and doesn't delete"
else
	print_err "--clean --dry-run failed"
	echo "$output"
	exit 1
fi

# Verify files still exist
if $GIT -C "$tempdir/remote.git" ls-tree HEAD | grep -q "secret1.txt"; then
	print_success "Files still exist after dry run"
else
	print_err "Dry run incorrectly deleted files!"
	exit 1
fi

# Test 3: --clean --force deletes files
print_info "Test 3: Force cleanup..."
"$SCRIPT_DIR/git-remote-gcrypt" --clean "$tempdir/remote.git" --force 2>&1

# Verify files are gone
if $GIT -C "$tempdir/remote.git" ls-tree HEAD 2>/dev/null | grep -q "secret"; then
	print_err "Files still exist after cleanup!"
	$GIT -C "$tempdir/remote.git" ls-tree HEAD
	exit 1
else
	print_success "Files removed after --clean --force"
fi

print_success "All --clean command tests passed!"
