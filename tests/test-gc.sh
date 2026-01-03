#!/bin/bash
# Test: Verify GCRYPT_FULL_REPACK garbage collection
# This test verifies that old unreachable blobs are removed when repacking.

set -e
set -x

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${CYAN}$*${NC}"; }
print_success() { echo -e "${GREEN}✓ $*${NC}"; }
print_err() { echo -e "${RED}✗ $*${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR:$PATH"
GIT="git -c advice.defaultBranchName=false"

tempdir=$(mktemp -d)
trap 'rm -rf "$tempdir"' EXIT

print_info "Setting up test environment..."

# 1. Setup simulated remote
$GIT init --bare "$tempdir/remote.git" >/dev/null

# 2. Setup local repo
mkdir "$tempdir/local"
cd "$tempdir/local"
$GIT init >/dev/null
$GIT config user.email "test@test.com"
$GIT config user.name "Test"
$GIT config commit.gpgsign false

# Add gcrypt remote
$GIT remote add origin "gcrypt::$tempdir/remote.git"
$GIT config remote.origin.gcrypt-participants "$(whoami)"

# 3. Create a large blob that we will later delete
print_info "Creating initial commit with large blob..."
# Use git hashing to make a known large object instead of dd if possible, or just dd
dd if=/dev/urandom of=largeblob bs=1K count=100 2>/dev/null # 100KB is enough to trigger pack
$GIT add largeblob
$GIT commit -m "Add large blob" >/dev/null
echo "Pushing initial data..."
git push origin master >/dev/null 2>&1 || {
	echo "Push failed"
	exit 1
}

# Verify remote has the blob (check size of packfiles)
pack_size_initial=$(du -s "$tempdir/remote.git" | cut -f1)
print_info "Initial remote size: ${pack_size_initial}K"

# 4. Remove the blob from history (make it unreachable)
print_info "Rewriting history to remove the blob..."
# Create new orphan branch
$GIT checkout --orphan clean-history >/dev/null 2>&1
rm -f largeblob
echo "clean data" >data.txt
$GIT add data.txt
$GIT commit -m "Clean history" >/dev/null

# 5. Force push with Repack
print_info "Force pushing with GCRYPT_FULL_REPACK=1..."
export GCRYPT_FULL_REPACK=1
# We need to force push to overwrite the old master
if git push --force origin clean-history:master >push.log 2>&1; then
	print_success "Push successful"
	cat push.log
else
	print_err "Push failed!"
	cat push.log
	exit 1
fi

# 6. Verify remote size decreased
pack_size_final=$(du -s "$tempdir/remote.git" | cut -f1)
print_info "Final remote size: ${pack_size_final}K"

if [ "$pack_size_final" -lt "$pack_size_initial" ]; then
	print_success "Garbage collection worked! Size decreased ($pack_size_initial -> $pack_size_final)"
else
	print_err "Garbage collection failed! Size did not decrease ($pack_size_initial -> $pack_size_final)"
	# Show listing of remote files for debugging
	ls -lR "$tempdir/remote.git"
	exit 1
fi
