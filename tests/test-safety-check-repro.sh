#!/bin/bash
# Test: Safety check aborts on standard git files (HEAD, config, etc)
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${CYAN}$*${NC}"; }
print_success() { echo -e "${GREEN}✓ $*${NC}"; }
print_err() { echo -e "${RED}✗ $*${NC}"; }

# Setup path
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR:$PATH"

# Setup temp dir
tempdir=$(mktemp -d)
trap 'rm -rf "$tempdir"' EXIT

export GNUPGHOME="${tempdir}/gpg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

# GPG Wrapper
cat <<'EOF' >"${GNUPGHOME}/gpg"
#!/usr/bin/env bash
exec /usr/bin/gpg --no-tty "$@"
EOF
chmod +x "${GNUPGHOME}/gpg"

# Helper for git
GIT="git -c advice.defaultBranchName=false -c commit.gpgSign=false -c init.defaultBranch=master"

# Generate key
gpg --batch --passphrase "" --quick-generate-key "Test <test@test.com>"
KEYID=$(gpg --list-keys --with-colons "test@test.com" | awk -F: '/^pub:/ { print $5 }')

# 1. Init bare repo as "remote" (creates HEAD, config, description, etc)
print_info "Initializing 'remote' as standard bare repo..."
mkdir "$tempdir/remote" && cd "$tempdir/remote"
$GIT init --bare

# 2. Try to clone/push using gcrypt
print_info "Attempting check/stat from gcrypt..."
cd "$tempdir"
mkdir client && cd client
$GIT init
$GIT config user.email "test@test.com"
$GIT config user.name "Test"

# We use 'stat' because it triggers early_safety_check
# Use rsync to trigger the dumb backend logic
# rsync needs ssh, might be complex in restricted env.
# Let's mock rsync instead?
# Or just use the fact that 'islocalrepo' check failed because of HEAD.
# 'islocalrepo' is: isnull "${1##/*}" && [ ! -e "$1/HEAD" ]
# The user has HEAD on the remote. rsync doesn't check HEAD locally.
# If we used rsync://, 'islocalrepo' wouldn't run.

# Mock rsync command to list files?
# The script calls: rsync --no-motd --list-only ...
# If we override rsync function...

# Better: Just pretend to be sftp or rsync by overriding checks? No.

# Mock rsync command to list files?
# The script calls: rsync --no-motd --list-only ...

# We create a fake 'rsync' in a temp bin dir
mkdir -p "$tempdir/bin"
cat <<EOF >"$tempdir/bin/rsync"
#!/bin/bash
# Mock rsync listing
if echo "\$@" | grep -q "list-only"; then
    echo "DEBUG: Mock rsync listing contents of $tempdir/remote" >&2
    # Simulate rsync output format: drwxr-xr-x          4096 2023/01/01 00:00:00 .
    # But strictly speaking we just need the filename at the end.
    for f in \$(ls -1 "$tempdir/remote"); do
        echo "-rw-r--r--          1024 2023/01/01 00:00:00 \$f"
    done
else
    # Fallback or error
    echo "Mock rsync called with: \$@" >&2
    exit 0
fi
EOF
chmod +x "$tempdir/bin/rsync"
export PATH="$tempdir/bin:$PATH"

# Use a dummy host for rsync, as we are mocking the binary
if "$SCRIPT_DIR/git-remote-gcrypt" stat "gcrypt::rsync://mock/$tempdir/remote" >"$tempdir/output" 2>&1; then

	cat "$tempdir/output"
	if grep -q "Found unexpected files: HEAD config" "$tempdir/output"; then
		print_success "Caught safety violation correctly."
	else
		print_err "Failed but wrong message?"
		exit 1
	fi
else
	print_err "Safety check passed unexpectedly!"
	exit 1
fi
