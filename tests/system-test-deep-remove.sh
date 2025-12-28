#!/usr/bin/env bash
# Tests for nested gcrypt (Gitception) to trigger gitception_remove
set -efuC -o pipefail
shopt -s inherit_errexit

# ----------------- Setup -----------------
indent() { sed 's/^\(.*\)$/    \1/'; }
tempdir=$(mktemp -d)
trap 'rm -Rf -- "${tempdir}"' EXIT

PATH=$(git rev-parse --show-toplevel):${PATH}
export PATH

export GNUPGHOME="${tempdir}/gpg"
mkdir -p "${GNUPGHOME}"
echo "no-tty" >> "$GNUPGHOME/gpg.conf"
echo "pinentry-mode loopback" >> "$GNUPGHOME/gpg.conf"

gpg --batch --passphrase "" --quick-generate-key "deep <deep@example.com>" >/dev/null 2>&1
key_fp=$(gpg --list-keys --with-colons | grep "^fpr" | head -n1 | cut -d: -f10)

export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
git config --global user.name "DeepTester"
git config --global user.email "deep@example.com"
git config --global init.defaultBranch "main"
git config --global gcrypt.participants "$key_fp"
git config --global gcrypt.gpg-args "--pinentry-mode loopback --no-tty"

echo "--- Step 1: Create Inner Remote ---"
git init --bare "${tempdir}/inner.git" | indent

echo "--- Step 2: Push to Inner (First Layer) ---"
git init "${tempdir}/repo"
cd "${tempdir}/repo"
touch base && git add base && git commit -m "base"
git checkout -b feature
touch feat && git add feat && git commit -m "feat"
git push "gcrypt::${tempdir}/inner.git" main feature 2>&1 | indent

echo "--- Step 3: Trigger Gitception (Deep Layer) ---"
# We now treat the inner gcrypt repo as the target for a second layer.
# Deleting a branch here should force gitception_remove to rewrite the Gref tree.
export GITCEPTION=1
git push "gcrypt::${tempdir}/inner.git" :feature 2>&1 | indent

# Verify
if git ls-remote "gcrypt::${tempdir}/inner.git" | grep -q "refs/heads/feature"; then
    echo "❌ ERROR: Feature branch still exists."
    exit 1
fi
echo "✅ PASS: Deep removal triggered."
