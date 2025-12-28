#!/usr/bin/env bash
# Mock test for rsync, rclone, and GPG edge cases
set -efuC -o pipefail
shopt -s inherit_errexit

indent() { sed 's/^\(.*\)$/    \1/'; }
tempdir=$(mktemp -d)
trap "rm -Rf -- '${tempdir}'" EXIT

# 1. MOCK BINARIES: Provide both rsync and rclone
mkdir -p "${tempdir}/bin"
cat << 'EOF' > "${tempdir}/bin/rsync"
#!/bin/bash
exit 0
EOF
cat << 'EOF' > "${tempdir}/bin/rclone"
#!/bin/bash
exit 0
EOF
chmod +x "${tempdir}/bin/rsync" "${tempdir}/bin/rclone"

PATH="${tempdir}/bin:$(git rev-parse --show-toplevel):${PATH}"
export PATH
export LOG_FILE="${tempdir}/backend.log"

# 2. GPG Setup: Two keys with the same UID to trigger warnings (Lines 467/469)
export GNUPGHOME="${tempdir}/gpg"
mkdir -p "${GNUPGHOME}"
echo "pinentry-mode loopback" >> "$GNUPGHOME/gpg.conf"
# Generate two distinct keys with the same name
gpg --batch --passphrase "" --quick-generate-key "Collision <col@example.com>" 2>/dev/null
gpg --batch --passphrase "" --quick-generate-key "Collision <col@example.com>" 2>/dev/null
key_fp=$(gpg --list-keys --with-colons | grep "^fpr" | head -n1 | cut -d: -f10)

# 3. Git Config
export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
git config --global user.name "BackendTester"
git config --global user.email "test@example.com"
git config --global init.defaultBranch "main"
# Using the name "Collision" triggers the 'multiple keys' warnings
git config --global gcrypt.participants "Collision"
git config --global gcrypt.gpg-args "--pinentry-mode loopback --no-tty"

echo "--- Step 1: Rsync Logic (PUTREPO, PUT, REMOVE, line_count) ---"
git init "${tempdir}/repo_rsync"
cd "${tempdir}/repo_rsync"
touch data && git add data && git commit -m "rsync init"
git push "gcrypt::rsync://example.com/path" main 2>&1 | indent
git push "gcrypt::rsync://example.com/path" :main 2>&1 | indent
export GCRYPT_FULL_REPACK=1
git push "gcrypt::rsync://example.com/path" main 2>&1 | indent
unset GCRYPT_FULL_REPACK

echo "--- Step 2: Rclone Logic (GET, PUT, PUTREPO, REMOVE) ---"
# These hit lines 242, 262, 294, 317
git push "gcrypt::rclone://remote:bucket/path" main 2>&1 | indent
git push "gcrypt::rclone://remote:bucket/path" :main 2>&1 | indent

echo "--- Step 3: Remote ID Mismatch (Lines 576-583) ---"
# Force mismatch by changing the local config record after a push
git remote add origin "gcrypt::${tempdir}/remote_local"
git push origin main 2>&1 | indent
git config "remote.origin.gcrypt-id" ":id:FORGED"
git fetch origin 2>&1 | indent

echo "✅ All mock sequences completed."
