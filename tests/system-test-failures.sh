#!/bin/bash
# Tests for failure modes and error handling in git-remote-gcrypt
set -efuC -o pipefail
shopt -s inherit_errexit

# ----------------- Setup -----------------
indent() { sed 's/^\(.*\)$/    \1/'; }
section_break() { echo; printf '*%.0s' {1..70}; echo $'\n'; }

umask 077
tempdir=$(mktemp -d)
trap "rm -Rf -- '${tempdir}'" EXIT

# Setup PATH to use the wrapper/local script
PATH=$(git rev-parse --show-toplevel):${PATH}
export PATH

# GPG Setup (Standard loopback config)
export GNUPGHOME="${tempdir}/gpg"
mkdir -p "${GNUPGHOME}"
echo "no-tty" >> "$GNUPGHOME/gpg.conf"
echo "pinentry-mode loopback" >> "$GNUPGHOME/gpg.conf"

# Generate one valid key for the "Good" side of operations
echo "Generating valid GPG key..."
gpg --batch --passphrase "" --quick-generate-key "valid-user <valid@example.com>" 2>&1 | indent
valid_key=$(gpg --list-keys --with-colons | grep "^fpr" | head -n1 | cut -d: -f10)

# Git Config
export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
git config --global user.name "Tester"
git config --global user.email "test@example.com"
git config --global init.defaultBranch "main"
git config --global gcrypt.participants "$valid_key"
git config --global gcrypt.gpg-args "--pinentry-mode loopback --no-tty"

# ----------------- Tests -----------------

section_break
echo "Test 1: Pushing to a remote with an INVALID GPG Key ID"
{
    git init -- "${tempdir}/repo_bad_key"
    cd "${tempdir}/repo_bad_key"
    touch file && git add file && git commit -m "Init"

    # Configure a fake key that definitely doesn't exist
    git config gcrypt.participants "DEADBEEF00000000DEADBEEF00000000DEADBEEF"

    echo "Attempting push (should fail)..."
    if git push "gcrypt::${tempdir}/remote_bad_key" main 2>&1; then
        echo "❌ ERROR: Push succeeded despite invalid key!"
        exit 1
    else
        echo "✅ PASS: Push failed as expected."
    fi
} | indent

section_break
echo "Test 2: Fetching from a Corrupted Manifest"
{
    # 1. Create a valid repo first
    git init -- "${tempdir}/repo_corrupt"
    cd "${tempdir}/repo_corrupt"
    touch data && git add data && git commit -m "Data"
    # Use valid key
    git config gcrypt.participants "$valid_key"
    git push "gcrypt::${tempdir}/remote_corrupt" main

    # 2. Corrupt the manifest on the remote
    # The remote is a bare git repo. The manifest is a blob, but gcrypt stores
    # metadata in refs/gcrypt/gitception*.
    # We will simulate corruption by overwriting the remote ref to point to garbage.

    echo "Corrupting remote..."
    cd "${tempdir}/remote_corrupt"
    # Point the gcrypt ref to a random hash that doesn't exist or isn't a signature
    echo "This is not a valid encrypted manifest" > corrupt_file
    hash=$(git hash-object -w corrupt_file)
    git update-ref refs/gcrypt/gitception "$hash"

    # 3. Try to clone/fetch from it
    echo "Attempting clone from corrupt remote (should fail)..."
    if git clone "gcrypt::${tempdir}/remote_corrupt" "${tempdir}/clone_fail" 2>&1; then
        echo "❌ ERROR: Clone succeeded despite corrupt manifest!"
        exit 1
    else
        echo "✅ PASS: Clone failed as expected."
    fi
} | indent

section_break
echo "Test 3: Unsupported URL Scheme"
{
    # Try using a scheme that git-remote-gcrypt definitely shouldn't handle cleanly
    # or should error out on immediately if passed incorrectly.

    echo "Attempting push to invalid scheme..."
    # Note: git itself might catch this, but we want to see if gcrypt explodes if invoked manually
    # or via the helper syntax.

    if git push "gcrypt::ftp://example.com/repo" main 2>&1; then
         echo "❌ ERROR: Push succeeded to unsupported FTP scheme?"
         exit 1
    else
         echo "✅ PASS: Push failed."
    fi
} | indent

echo
echo "All Failure/Edge-case tests passed."
