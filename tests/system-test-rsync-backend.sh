#!/usr/bin/env bash
# Mock test for rsync backend logic
set -efuC -o pipefail
shopt -s inherit_errexit

indent() { sed 's/^\(.*\)$/    \1/'; }
tempdir=$(mktemp -d)
trap "rm -Rf -- '${tempdir}'" EXIT

# 1. MOCK RSYNC: Create a fake rsync that just 'touches' files
mkdir -p "${tempdir}/bin"
cat << 'EOF' > "${tempdir}/bin/rsync"
#!/bin/bash
# Fake rsync: log calls and pretend to work
echo "[MOCK] rsync $@" >> "${LOG_FILE}"
# If it's a 'get' or 'list', ensure we don't crash
exit 0
EOF
chmod +x "${tempdir}/bin/rsync"

# Update PATH to prioritize our mock
PATH="${tempdir}/bin:$(git rev-parse --show-toplevel):${PATH}"
export PATH
export LOG_FILE="${tempdir}/rsync.log"

# 2. GPG/Git Setup
export GNUPGHOME="${tempdir}/gpg"
mkdir -p "${GNUPGHOME}"
echo "pinentry-mode loopback" >> "$GNUPGHOME/gpg.conf"
gpg --batch --passphrase "" --quick-generate-key "rsync <rsync@example.com>" 2>/dev/null
key_fp=$(gpg --list-keys --with-colons | grep "^fpr" | head -n1 | cut -d: -f10)

export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
git config --global user.name "RsyncTester"
git config --global user.email "rsync@example.com"
git config --global init.defaultBranch "main"
git config --global gcrypt.participants "$key_fp"
git config --global gcrypt.gpg-args "--pinentry-mode loopback --no-tty"

echo "--- Test: Push to rsync:// URL ---"
git init "${tempdir}/repo"
cd "${tempdir}/repo"
touch data && git add data && git commit -m "rsync test"

# This triggers the rsync-specific block in git-remote-gcrypt
if git push "gcrypt::rsync://example.com/path" main 2>&1 | indent; then
    echo "✅ PASS: Rsync logic triggered."
else
    echo "❌ ERROR: Push failed."
    exit 1
fi
