#!/bin/bash
# Test: clean command should wipe all branches with files
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
GIT="git -c advice.defaultBranchName=false -c commit.gpgSign=false"

# Generate key
gpg --batch --passphrase "" --quick-generate-key "Test <test@test.com>"

# 1. Init bare repo (the "remote")
print_info "Initializing 'remote'..."
mkdir "$tempdir/remote" && cd "$tempdir/remote"
$GIT init --bare

# 2. Populate 'main' branch with a file
print_info "Populating remote 'main' with a file..."
mkdir "$tempdir/seeder" && cd "$tempdir/seeder"
$GIT init -b main
$GIT remote add origin "$tempdir/remote"
echo "KEY DATA" >key.txt
$GIT add key.txt
$GIT config user.email "test@test.com"
$GIT config user.name "Test"
$GIT commit -m "Add key"
$GIT push origin main

# 3. Populate 'master' branch with a file
print_info "Populating remote 'master' with a file..."
$GIT checkout -b master
echo "CONFIG DATA" >config.txt
$GIT add config.txt
$GIT commit -m "Add config"
$GIT push origin master

# Now remote has master (config.txt) and main (key.txt + config.txt? No, branched off main).
# Both have unencrypted files.
# `clean` should remove files from both.

# 4. Attempt clean
print_info "Attempting clean..."
cd "$tempdir"
git init
# Explicitly target the remote
if "$SCRIPT_DIR/git-remote-gcrypt" clean --init --force "gcrypt::$tempdir/remote"; then
	print_info "Clean command finished."
else
	print_err "Clean command failed."
	exit 1
fi

# 5. Check if files still exist
cd "$tempdir/remote"
FAIL=0
if $GIT -c core.quotePath=false ls-tree -r main | grep -q "key.txt"; then
	print_err "FAILURE: key.txt still exists on main!"
	FAIL=1
else
	print_success "SUCCESS: key.txt was removed from main."
fi

if $GIT -c core.quotePath=false ls-tree -r master | grep -q "config.txt"; then
	print_err "FAILURE: config.txt still exists on master!"
	FAIL=1
else
	print_success "SUCCESS: config.txt was removed from master."
fi

if [ $FAIL -eq 1 ]; then
	exit 1
fi
