#!/bin/sh
set -e

# Setup test environment
echo "Setting up test environment..."
PROJECT_ROOT="$(pwd)"
mkdir -p .tmp
TEST_DIR="$PROJECT_ROOT/.tmp/gcrypt_test"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

REPO_DIR="$TEST_DIR/repo"
REMOTE_DIR="$TEST_DIR/remote"

mkdir -p "$REPO_DIR"
mkdir -p "$REMOTE_DIR"

# Initialize repo
cd "$REPO_DIR"
git init
git config user.email "you@example.com"
git config user.name "Your Name"

# Create a few text files
echo "content 1" >file1.txt
echo "content 2" >file2.txt
echo "content 3" >file3.txt
git add file1.txt file2.txt file3.txt
git commit -m "Initial commit with multiple files"

# Setup gcrypt remote
GCRYPT_BIN="$PROJECT_ROOT/git-remote-gcrypt"
if [ ! -x "$GCRYPT_BIN" ]; then
	echo "Error: git-remote-gcrypt binary not found at $GCRYPT_BIN"
	exit 1
fi

# GPG Setup (embedded)
export GNUPGHOME="$TEST_DIR/gpg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

# Wrapper to suppress warnings, handle args, and FORCE GNUPGHOME
cat <<EOF >"${GNUPGHOME}/gpg"
#!/usr/bin/env bash
export GNUPGHOME="$GNUPGHOME"
set -efuC -o pipefail; shopt -s inherit_errexit
args=( "\${@}" )
for ((i = 0; i < \${#}; ++i)); do
    if [[ \${args[\${i}]} = "--secret-keyring" ]]; then
        unset "args[\${i}]" "args[\$(( i + 1 ))]"
        break
    fi
done
exec gpg "\${args[@]}"
EOF
chmod +x "${GNUPGHOME}/gpg"

# Generate key
echo "Generating GPG key..."
gpg --batch --passphrase "" --quick-generate-key "Test <test@test.com>"

# Initialize REMOTE_DIR as a bare git repo so gcrypt treats it as a git backend (gitception)
# This is required to trigger gitception_remove
git init --bare "$REMOTE_DIR"

# Configure remote
git remote add origin "gcrypt::$REMOTE_DIR"
git config remote.origin.gcrypt-participants "test@test.com"
git config remote.origin.gcrypt-signingkey "test@test.com"

# Configure global git for test to avoid advice noise
git config --global advice.defaultBranchName false

export PATH="$PROJECT_ROOT:$PATH"

echo "Pushing to remote..."
# Explicitly use +master to ensure 'force' is detected by gcrypt to allow init
git push origin +master

# Create garbage on remote
cd "$TEST_DIR"
git clone "$REMOTE_DIR" raw_remote_clone
cd raw_remote_clone
git checkout master || git checkout -b master

# Add multiple garbage files
echo "garbage 1" >garbage1.txt
echo "garbage 2" >garbage2.txt
git add garbage1.txt garbage2.txt
git commit -m "Add garbage files"
git push origin master

# Go back to local repo
cd "$REPO_DIR"

# Create conflicting local files (untracked but matching name, different content)
# This simulates the "local modifications" error when `clean` tries to remove them.
echo "local conflict 1" >garbage1.txt
echo "local conflict 2" >garbage2.txt
# Add them to local index so they are 'tracked' in the worktree, potentially confusing git rm against the temp index?
# Or just ensure they exist. The user reported 'local modifications'.
git add garbage1.txt garbage2.txt

echo "Running clean --force (expecting failure and hints)..."
echo "---------------------------------------------------"
if ! git-remote-gcrypt clean --force origin; then
	echo "---------------------------------------------------"
	echo "Clean failed as expected."
else
	echo "Clean succeeded unexpectedly!"
	exit 1
fi
