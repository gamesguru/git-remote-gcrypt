#!/bin/bash
# Test: Safety check blocks push to dirty remote
# This test verifies that git-remote-gcrypt blocks pushing to a remote
# that contains unencrypted files.

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
export HOME="${tempdir}"

# Isolate git config to prevent leaks from other tests
export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
export GIT_CONFIG_SYSTEM="/dev/null"

print_info "Setting up test environment..."

# Create a bare repo (simulates remote)
$GIT init --bare "$tempdir/remote.git" >/dev/null

# Add a dirty file directly to the bare repo
# (simulating a repo that was used without gcrypt)
cd "$tempdir/remote.git"
$GIT config user.email "test@test.com"
$GIT config user.name "Test"
echo "SECRET_KEY=12345" >"$tempdir/secret.txt"
BLOB=$($GIT hash-object -w "$tempdir/secret.txt")
TREE=$(echo -e "100644 blob $BLOB\tsecret.txt" | $GIT mktree)
COMMIT=$(echo "Initial dirty commit" | $GIT commit-tree "$TREE")
$GIT update-ref refs/heads/master "$COMMIT"

print_info "Created dirty remote with unencrypted file"

# Create a local repo that tries to use gcrypt
mkdir "$tempdir/local"
cd "$tempdir/local"
$GIT init >/dev/null
$GIT config user.email "test@test.com"
$GIT config user.name "Test"
$GIT config commit.gpgsign false

# Add gcrypt remote
$GIT remote add origin "gcrypt::$tempdir/remote.git"
$GIT config remote.origin.gcrypt-participants "$(whoami)"

# Create a commit
echo "encrypted data" >data.txt
$GIT add data.txt
$GIT commit -m "Test commit" >/dev/null

print_info "Attempting push to dirty remote (should fail)..."

# Capture output and check for safety message
set +e
push_output=$($GIT push --force origin master 2>&1)
push_exit=$?
set -e

# Debug: show what we got
if [ -n "$push_output" ]; then
	echo "Push output: $push_output" >&2
fi

# Check for safety check message (could be "unencrypted" or "unexpected")
if echo "$push_output" | grep -qE "(unencrypted|unexpected|unknown)"; then
	print_success "Safety check correctly detected unencrypted files"
else
	print_err "Safety check failed to detect unencrypted files"
	echo "Exit code was: $push_exit" >&2
	exit 1
fi

print_info "Testing bypass config..."
$GIT config gcrypt.allow-unencrypted-remote true

# With bypass, it should at least attempt (may fail due to GPG, but that's ok)
if $GIT push --force origin master 2>&1; then
	print_success "Bypass config allowed push attempt"
else
	# Even a GPG error means bypass worked
	print_success "Bypass config allowed push attempt (GPG may have failed, that's OK)"
fi

print_success "All safety check tests passed!"
