#!/usr/bin/env bash
set -efuC -o pipefail
tempdir=$(mktemp -d)
trap "rm -Rf -- '${tempdir}'" EXIT
PATH="$(git rev-parse --show-toplevel):${PATH}"
export PATH

# 1. Setup GPG with two keys having same UID (Triggers line 467/469 warnings)
export GNUPGHOME="${tempdir}/gpg"
mkdir -p "${GNUPGHOME}"
echo "pinentry-mode loopback" >> "$GNUPGHOME/gpg.conf"
gpg --batch --passphrase "" --quick-generate-key "Duplicate <dup@example.com>" 2>/dev/null
gpg --batch --passphrase "" --quick-generate-key "Duplicate <dup@example.com>" 2>/dev/null

export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
git config --global init.defaultBranch "main"
git config --global gcrypt.participants "Duplicate"

echo "--- Test: Duplicate Key Warnings ---"
git init "${tempdir}/repo"
cd "${tempdir}/repo"
touch f && git add f && git commit -m "init"
# Should trigger warnings about multiple keys matching 'Duplicate'
git push "gcrypt::${tempdir}/remote" main 2>&1 | indent

echo "--- Test: No Valid Recipients (Lines 494-498) ---"
git config gcrypt.participants "NON_EXISTENT_KEY_ID"
git push "gcrypt::${tempdir}/remote2" main 2>&1 || echo "Caught expected lack of keys"
