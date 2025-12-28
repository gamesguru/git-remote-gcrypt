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
# Git-remote-gcrypt often expects rsync to return 0 to proceed
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

echo "--- Step 1: Push (Triggers PUTREPO and PUT) ---"
git init "${tempdir}/repo"
cd "${tempdir}/repo"
touch data && git add data && git commit -m "rsync init"

# This triggers PUTREPO (to create the remote) and PUT (to upload objects)
git push "gcrypt::rsync://example.com/path" main 2>&1 | indent

# Force a manifest rewrite and object upload (PUT/PUTREPO)
git push "gcrypt::rsync://example.com/path" main

echo "--- Step 2: Delete Branch (Triggers REMOVE) ---"
# Deleting a remote branch forces the REMOVE block to execute
git push "gcrypt::rsync://example.com/path" :main 2>&1 | indent


echo "--- Step 3: Force Repack (Triggers line_count and GET) ---"
# Setting this env var forces the helper to download and count existing packs
export GCRYPT_FULL_REPACK=1
git push "gcrypt::rsync://example.com/path" main 2>&1 | indent

echo "✅ All rsync mock sequences completed."
