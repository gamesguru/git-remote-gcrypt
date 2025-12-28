#!/usr/bin/env bash
set -efuC -o pipefail
tempdir=$(mktemp -d)
trap "rm -Rf -- '${tempdir}'" EXIT

indent() { sed 's/^\(.*\)$/    \1/'; }
PATH="$(git rev-parse --show-toplevel):${PATH}"
export PATH

# 1. MOCK BINARIES (Rsync and Rclone)
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
PATH="${tempdir}/bin:${PATH}"

# 2. GPG SETUP (Two keys with same UID)
export GNUPGHOME="${tempdir}/gpg"
mkdir -p "${GNUPGHOME}"
echo "pinentry-mode loopback" >> "$GNUPGHOME/gpg.conf"
gpg --batch --passphrase "" --quick-generate-key "Duplicate <dup@example.com>" 2>/dev/null
gpg --batch --passphrase "" --quick-generate-key "Duplicate <dup@example.com>" 2>/dev/null

# 3. GIT CONFIG
export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
git config --global init.defaultBranch "main"
git config --global gcrypt.participants "Duplicate" # Triggers Lines 467/469
git config --global gcrypt.gpg-args "--pinentry-mode loopback --no-tty"

# 4. RUN RSYNC & RCLONE (Triggers PUTREPO, PUT, REMOVE, line_count)
git init "${tempdir}/repo"
cd "${tempdir}/repo"
touch f && git add f && git commit -m "init"

# Rsync Blocks (Lines 239, 259, 290, 313)
git push "gcrypt::rsync://example.com/path" main 2>&1 | indent
git push "gcrypt::rsync://example.com/path" :main 2>&1 | indent

# Rclone Blocks (Lines 242, 262, 294, 317)
git push "gcrypt::rclone://remote:bucket/path" main 2>&1 | indent

# ID Mismatch (Lines 576-583)
git remote add origin "gcrypt::${tempdir}/remote_local"
git push origin main 2>&1 | indent
git config "remote.origin.gcrypt-id" ":id:FORGED"
git fetch origin 2>&1 | indent
