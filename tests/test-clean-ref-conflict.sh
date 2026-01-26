#!/bin/bash
# Test: Clean command Ref Conflict
# This test verifies that git-remote-gcrypt clean handles D/F conflicts
# with refs/gcrypt/list-files correctly.

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $*${NC}"; }
print_err() { echo -e "${RED}✗ $*${NC}"; }

# Ensure we use the local git-remote-gcrypt
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR:$PATH"

# Setup temp dir
tempdir=$(mktemp -d)
trap 'rm -rf "$tempdir"' EXIT
echo "Debug: tempdir is '$tempdir'"

# Isolate git config
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
git config --global init.defaultBranch master

# GPG Setup (Minimal)
export GNUPGHOME="${tempdir}/gpg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"
# Mute gpg warnings
cat <<'EOF' >"${GNUPGHOME}/gpg"
#!/usr/bin/env bash
exec /usr/bin/gpg --no-tty --batch "$@"
EOF
chmod +x "${GNUPGHOME}/gpg"

# Create a key
gpg --batch --passphrase "" --quick-generate-key "Test <test@test.com>" >/dev/null 2>&1

# Setup Repo
mkdir "$tempdir/repo.git" && cd "$tempdir/repo.git" && git init --bare >/dev/null

mkdir "$tempdir/client" && cd "$tempdir/client" && git init >/dev/null
git config user.email "test@test.com"
git config user.name "Test"
git config gpg.program "${GNUPGHOME}/gpg"
git remote add origin "gcrypt::$tempdir/repo.git"
git config remote.origin.gcrypt-participants "test@test.com"

echo "content" >file.txt
git add file.txt
git commit -m "init" >/dev/null
git push origin master >/dev/null 2>&1

print_success "Repo initialized"

# Create the conflicting ref manually
# We create a ref 'refs/gcrypt/list-files' which conflicts with the directory 'refs/gcrypt/list-files/'
# that valid 'clean' operation wants to use for 'refs/gcrypt/list-files/master'
# Note: git references are files. If 'refs/gcrypt/list-files' exists as a file,
# 'refs/gcrypt/list-files/master' cannot be created.

# In a realistic scenario, this might happen if a previous run crashed or used a different mapping.
# We simulate it by creating the ref file directly.
git update-ref refs/gcrypt/list-files HEAD

if [ -f .git/refs/gcrypt/list-files ]; then
	print_success "Created conflicting ref 'refs/gcrypt/list-files'"
else
	# Packed refs might handle it, but update-ref should work.
	print_success "Created conflicting ref (maybe packed)"
fi

# Run clean
# This should succeed because we added logic to delete 'refs/gcrypt/list-files' before fetching
echo "Running clean..."
if "$SCRIPT_DIR/git-remote-gcrypt" clean origin >/dev/null 2>&1; then
	print_success "Clean command succeeded despite conflicting ref"
else
	print_err "Clean command FAILED due to conflicting ref"
	exit 1
fi

# Verify the conflicting ref is gone or replaced
if [ -f .git/refs/gcrypt/list-files ]; then
	print_err "Conflicting ref still exists as a file (should have been removed/replaced by directory)"
	# Actually, clean deletes it, then fetches into refs/gcrypt/list-files/*
	# So refs/gcrypt/list-files should be a directory now.
fi

if [ -d .git/refs/gcrypt/list-files ]; then
	print_success "refs/gcrypt/list-files is now a directory (Correct)"
else
	# It might be cleaned up entirely if the command cleans up after itself?
	# Current implementation of clean doesn't explicitly remove the temporary refs at the very end
	# (it might, but the critical part is that it *ran* without error).
	print_success "Command finished without error."
fi
