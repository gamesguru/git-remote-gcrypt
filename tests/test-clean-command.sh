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

# Isolate git config from user environment
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL=/dev/null

# Suppress git advice messages
# Note: git-remote-gcrypt reads actual config files, not just CLI -c options
GIT="git -c advice.defaultBranchName=false -c commit.gpgSign=false"

# --------------------------------------------------
# Set up test environment
# --------------------------------------------------
# Create temp directory
tempdir=$(mktemp -d)
trap 'rm -rf "$tempdir"' EXIT

print_info "Setting up test environment..."

# --------------------------------------------------
# GPG Setup (Derived from system-test.sh)
# --------------------------------------------------
export GNUPGHOME="${tempdir}/gpg"
mkdir "${GNUPGHOME}"

# Wrapper to suppress obsolete warnings
cat <<'EOF' >"${GNUPGHOME}/gpg"
#!/usr/bin/env bash
set -efuC -o pipefail; shopt -s inherit_errexit
args=( "${@}" )
for ((i = 0; i < ${#}; ++i)); do
    if [[ ${args[${i}]} = "--secret-keyring" ]]; then
        unset "args[${i}]" "args[$(( i + 1 ))]"
        break
    fi
done
exec gpg "${args[@]}"
EOF
chmod +x "${GNUPGHOME}/gpg"

# Generate key
(
	gpg --batch --passphrase "" --quick-generate-key "Test <test@test.com>"
)

# --------------------------------------------------
# Git Setup
# --------------------------------------------------

# Create a bare repo with dirty files
$GIT init --bare "$tempdir/remote.git" >/dev/null
cd "$tempdir/remote.git"
$GIT config user.email "test@test.com"
$GIT config user.name "Test"
$GIT config gpg.program "${GNUPGHOME}/gpg"
# Needed for encryption to work during setup
$GIT config gcrypt.participants "test@test.com"

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
# Test 2: Safety Check (Abort on non-gcrypt)
# --------------------------------------------------
print_info "Test 2: Safety Check (Abort on non-gcrypt)..."
cd "$tempdir/remote.git"
output=$("$SCRIPT_DIR/git-remote-gcrypt" clean "$tempdir/remote.git" 2>&1 || :)
assert_grep "Error: No gcrypt manifest found" "$output" "clean aborts on non-gcrypt repo"

if $GIT ls-tree HEAD | grep -q "secret1.txt"; then
	print_success "Files preserved (Safety check passed)"
else
	print_err "Files deleted despite safety check!"
	exit 1
fi

# --------------------------------------------------
# Test 3: Remote resolution (Abort on non-gcrypt)
# --------------------------------------------------
print_info "Test 3: Remote resolution..."
mkdir -p "$tempdir/client" && cd "$tempdir/client" && $GIT init >/dev/null
$GIT config gpg.program "${GNUPGHOME}/gpg"
$GIT remote add origin "$tempdir/remote.git"
output=$("$SCRIPT_DIR/git-remote-gcrypt" clean origin 2>&1 || :)
assert_grep "Error: Remote 'origin' is not a gcrypt:: remote" "$output" "clean aborts on resolved non-gcrypt remote"

# --------------------------------------------------
# Test 4: Remote listing
# --------------------------------------------------
print_info "Test 4: Remote listing..."
$GIT remote add gcrypt-origin "gcrypt::$tempdir/remote.git"
output=$("$SCRIPT_DIR/git-remote-gcrypt" clean 2>&1 || :)
assert_grep "Available remotes:" "$output" "clean lists remotes"
assert_grep "gcrypt-origin" "$output" "clean listed 'gcrypt-origin'"

# --------------------------------------------------
# Test 5: Clean Valid Gcrypt Repo
# --------------------------------------------------
print_info "Test 5: Clean Valid Gcrypt Repo..."

# 1. Initialize a valid gcrypt repo
mkdir "$tempdir/valid.git" && cd "$tempdir/valid.git" && $GIT init --bare >/dev/null
cd "$tempdir/client"
$GIT config user.name "Test"
$GIT config user.email "test@test.com"
$GIT config user.signingkey "test@test.com"
# Create content to push
echo "valid content" >content.txt
$GIT add content.txt
$GIT commit -m "init valid"
# Push to intialize
set -x
$GIT push -f "gcrypt::$tempdir/valid.git" master:master || {
	set +x
	print_err "Git push failed"
	exit 1
}
set +x

print_info "Initialized valid gcrypt repo"

# 2. Inject garbage file into the remote git index/tree
cd "$tempdir/valid.git"
GREF="refs/gcrypt/gitception"
if ! $GIT rev-parse --verify "$GREF" >/dev/null 2>&1; then
	print_err "Gref $GREF not found in remote!"
	exit 1
fi

GARBAGE_BLOB=$(echo "GARBAGE DATA" | $GIT hash-object -w --stdin)
CURRENT_TREE=$($GIT rev-parse "$GREF^{tree}")
export GIT_INDEX_FILE=index.garbage
$GIT read-tree "$CURRENT_TREE"
$GIT update-index --add --cacheinfo 100644 "$GARBAGE_BLOB" "garbage_file"
NEW_TREE=$($GIT write-tree)
rm index.garbage
PARENT=$($GIT rev-parse "$GREF")
NEW_COMMIT=$(echo "Inject garbage" | $GIT commit-tree "$NEW_TREE" -p "$PARENT")
$GIT update-ref "$GREF" "$NEW_COMMIT"

# Verify injection
if ! $GIT ls-tree -r "$GREF" | grep -q "garbage_file"; then
	print_err "Failed to inject garbage_file into $GREF"
	exit 1
fi
print_info "Injected garbage_file into remote $GREF"

# 3. Scan (expect to find garbage_file)
set -x
output=$("$SCRIPT_DIR/git-remote-gcrypt" clean "gcrypt::$tempdir/valid.git" 2>&1)
set +x
assert_grep "garbage_file" "$output" "clean identified unencrypted file in valid repo"
assert_grep "NOTE: This is a scan" "$output" "clean scan-only mode confirmed"

# 4. Clean Force
"$SCRIPT_DIR/git-remote-gcrypt" clean "gcrypt::$tempdir/valid.git" --force >/dev/null 2>&1

# Verify garbage_file is GONE from the GREF tree
UPDATED_TREE=$($GIT rev-parse "$GREF^{tree}")
if $GIT ls-tree -r "$UPDATED_TREE" | grep -q "garbage_file"; then
	print_err "Garbage file still exists in remote git tree after CLEAN FORCE!"
	exit 1
else
	print_success "Garbage file removed successfully."
fi

# --------------------------------------------------
# Test 6: check command
# --------------------------------------------------
print_info "Test 6: check command..."
output=$("$SCRIPT_DIR/git-remote-gcrypt" check "$tempdir/remote.git" 2>&1 || :)
assert_grep "gcrypt: Checking remote:" "$output" "check command is recognized"

print_success "All clean/check command tests passed!"
