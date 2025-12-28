#!/usr/bin/env bash
# Tests for branch deletion to trigger REMOVE, gitception_remove, and line_count
set -efuC -o pipefail
shopt -s inherit_errexit

# ----------------- Setup -----------------
indent() { sed 's/^\(.*\)$/    \1/'; }
tempdir=$(mktemp -d)
trap "rm -Rf -- '${tempdir}'" EXIT

PATH=$(git rev-parse --show-toplevel):${PATH}
export PATH

export GNUPGHOME="${tempdir}/gpg"
mkdir -p "${GNUPGHOME}"
echo "no-tty" >> "$GNUPGHOME/gpg.conf"
echo "pinentry-mode loopback" >> "$GNUPGHOME/gpg.conf"

echo "Generating GPG key..."
gpg --batch --passphrase "" --quick-generate-key "deleter <del@example.com>" 2>&1 | indent
key_fp=$(gpg --list-keys --with-colons | grep "^fpr" | head -n1 | cut -d: -f10)

export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
git config --global user.name "Deleter"
git config --global user.email "del@example.com"
git config --global init.defaultBranch "main"
git config --global gcrypt.participants "$key_fp"
git config --global gcrypt.gpg-args "--pinentry-mode loopback --no-tty"

echo "--- Setup: Init and Push ---"
git init -- "${tempdir}/repo"
cd "${tempdir}/repo"
touch file1 && git add file1 && git commit -m "Main commit"
git checkout -b feature
touch file2 && git add file2 && git commit -m "Feature commit"

# Push both to remote
echo "Pushing main and feature..."
git push "gcrypt::${tempdir}/remote" main feature 2>&1 | indent

echo "--- Test 1: Delete 'feature' (Standard REMOVE) ---"
git push "gcrypt::${tempdir}/remote" :feature 2>&1 | indent

# Verify feature is gone
if git ls-remote "gcrypt::${tempdir}/remote" | grep -q "refs/heads/feature"; then
    echo "❌ ERROR: Feature branch was NOT deleted!"
    exit 1
fi
echo "✅ PASS: Single branch deletion successful."


echo "--- Test 2: Delete 'main' (Total Wipeout -> gitception_remove) ---"
# This step empties the manifest. This usually triggers different logic
# (like line_count checking for 0, or removing the manifest blob).
git push "gcrypt::${tempdir}/remote" :main 2>&1 | indent

# Verify remote is empty
count=$(git ls-remote "gcrypt::${tempdir}/remote" | wc -l)
if [ "$count" -ne 0 ]; then
    echo "❌ ERROR: Remote should be empty, but found $count refs."
    exit 1
fi
echo "✅ PASS: Total deletion successful."
