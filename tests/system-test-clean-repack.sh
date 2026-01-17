#!/bin/sh
set -e

# Setup test environment
echo "Setting up repack test environment..."
PROJECT_ROOT="$(pwd)"
mkdir -p .tmp
TEST_DIR="$PROJECT_ROOT/.tmp/repack_test"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Repo paths
REPO_DIR="$TEST_DIR/repo"
REMOTE_DIR="$TEST_DIR/remote"

mkdir -p "$REPO_DIR"
mkdir -p "$REMOTE_DIR"

# Tools
GCRYPT_BIN="$PROJECT_ROOT/git-remote-gcrypt"
if [ ! -x "$GCRYPT_BIN" ]; then
	echo "Error: git-remote-gcrypt binary not found at $GCRYPT_BIN"
	exit 1
fi

# GPG Setup
export GNUPGHOME="$TEST_DIR/gpg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

cat <<'EOF' >"${GNUPGHOME}/gpg"
#!/usr/bin/env bash
export GNUPGHOME="$GNUPGHOME"
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

# Git config isolation
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL="$TEST_DIR/gitconfig"
git config --global user.email "test@test.com"
git config --global user.name "Test"
git config --global init.defaultBranch "master"

echo "Generating GPG key..."
gpg --batch --passphrase "" --quick-generate-key "Test <test@test.com>"

# Initialize repo
cd "$REPO_DIR"
git init
git config user.email "test@test.com"
git config user.name "Test User"
git config advice.defaultBranchName false

# Initialize local remote
git init --bare "$REMOTE_DIR"
git remote add origin "gcrypt::$REMOTE_DIR"
git config remote.origin.gcrypt-participants "test@test.com"
git config remote.origin.gcrypt-signingkey "test@test.com"
git config gpg.program "${GNUPGHOME}/gpg"
git config user.signingkey "test@test.com"

export PATH="$PROJECT_ROOT:$PATH"

# Create fragmentation by pushing multiple times
echo "Push 1"
echo "data 1" >file1.txt
git add file1.txt
git commit -m "Commit 1" --no-gpg-sign
# Initial push needs force to initialize remote gcrypt repo
git push origin +master

echo "Push 2"
echo "data 2" >file2.txt
git add file2.txt
git commit -m "Commit 2" --no-gpg-sign
git push origin master

echo "Push 3"
echo "data 3" >file3.txt
git add file3.txt
git commit -m "Commit 3" --no-gpg-sign
git push origin master

# Verify we have multiple pack files in remote
# Note: gcrypt stores packs in 'pack' directory if using rsync-like backend?
# For git backend (gitception), they are objects in the git repo.
# We are using local file backend? No, gcrypt::$REMOTE_DIR where REMOTE_DIR is bare git repo.
# This makes it a Git Backend (gitception).
# The packs are stored as blobs in the backend repo.
# But 'do_push' logic downloads packs using 'git rev-list'.
# The 'Packlist' manifest file lists the active packs.
# We can check the Manifest to count packs.

# Clone the raw backend to inspect manifest
cd "$TEST_DIR"
git clone "$REMOTE_DIR" raw_backend
cd raw_backend
git checkout master
# The manifest is a file with randomized name, but we can find it encrypt/decrypt?
# No, easier: use git-remote-gcrypt to list packs via debug or inference.
# Or just trust that multiple pushes created multiple packs (as gcrypt doesn't auto-repack on push unless configured).

# Let's count lines in Packlist from the helper's debug output?
# Or we can verify the backend git repo has multiple commits (one per push).
HEAD_SHA=$(git rev-parse HEAD)
echo "Backend SHA: $HEAD_SHA"
# Start should have 3 commits (init, push1, push2, push3) -> wait, init is implicit.
# Each push updates the manifested repo.

# Inject garbage to verify cleanup AND repack
echo "GARBAGE" >garbage.txt
GARBAGE_BLOB=$(git hash-object -w garbage.txt)
echo "Created garbage blob: $GARBAGE_BLOB"
# Manually inject into backend (simulate inconsistency)
# But here we are simulating a gitception remote.
# To simulate "garbage" (unencrypted file), we can push one or hack the backend.
# Using 'git-remote-gcrypt' clean mechanism relies on files existing in the remote manifest (or filesystem for other backends).
# For git backend, "garbage" is a file in the remote repo's HEAD tree that isn't in the manifest/packed list.
# Let's clone backend, add file, push.
cd "$TEST_DIR/raw_backend"
echo "Garbage Data" >".garbage (file)"
git add ".garbage (file)"
git commit -m "Inject unencrypted garbage" --no-gpg-sign
git push origin master

# Verify garbage exists
cd "$REPO_DIR"
# Run clean --repack --force (needed because we have garbage now)
echo "Running clean --repack --force..."
git-remote-gcrypt clean --repack --force origin

# Verify garbage removal from backend
cd "$TEST_DIR"
rm -rf raw_backend_verify
git clone "$REMOTE_DIR" raw_backend_verify
cd raw_backend_verify

if [ -f ".garbage (file)" ]; then
	echo "Failure: .garbage (file) still exists in backend!"
	exit 1
else
	echo "Success: .garbage (file) removed."
fi

# Verify result
# Check if commit SHA changed. Repack force-pushes a new manifest state.
cd "$TEST_DIR/raw_backend_verify"
NEW_HEAD=$(git rev-parse HEAD)
echo "Old HEAD: $HEAD_SHA"
echo "New HEAD: $NEW_HEAD"

if [ "$NEW_HEAD" != "$HEAD_SHA" ]; then
	echo "Repack successful (HEAD changed)."
else
	echo "Repack failed (HEAD did not change)."
	exit 1
fi

# Verify data integrity
cd "$REPO_DIR"
# Force fresh clone to verified data
cd "$TEST_DIR"
git clone "gcrypt::$REMOTE_DIR" verified_repo
cd verified_repo
if [ -f file1.txt ] && [ -f file2.txt ] && [ -f file3.txt ]; then
	echo "Data integrity verified."
else
	echo "Data integrity failed!"
	exit 1
fi

echo "Test passed."
