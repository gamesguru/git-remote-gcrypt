#!/bin/bash
# Test: clean command fails if refs/gcrypt/list-files exists as a file (D/F conflict)
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
print_info() { echo -e "${GREEN}$*${NC}"; }
print_err() { echo -e "${RED}✗ $*${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR:$PATH"
tempdir=$(mktemp -d)
trap 'rm -rf "$tempdir"' EXIT

export GNUPGHOME="${tempdir}/gpg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"
cat <<'EOF' >"${GNUPGHOME}/gpg"
#!/usr/bin/env bash
exec /usr/bin/gpg --no-tty "$@"
EOF
chmod +x "${GNUPGHOME}/gpg"

GIT="git -c advice.defaultBranchName=false -c commit.gpgSign=false"
gpg --batch --passphrase "" --quick-generate-key "Test <test@test.com>"

mkdir "$tempdir/remote" && cd "$tempdir/remote"
$GIT init --bare

mkdir "$tempdir/seeder" && cd "$tempdir/seeder"
$GIT init -b main
$GIT remote add origin "$tempdir/remote"
echo "DATA" >file.txt
$GIT add file.txt
$GIT commit -m "init"
$GIT push origin main

print_info "Attempting clean with poisoned environment..."
cd "$tempdir"
git init
# Create a commit so we have something to point the ref to
touch foo
git add foo
git commit -m "init"

# POISON: Create a ref that conflicts with the directory we want to use
# The old code used refs/gcrypt/list-files as a file.
# The new code uses refs/gcrypt/list-files/BRANCH.
# If we have the old ref, git fetch might fail.
git update-ref refs/gcrypt/list-files HEAD

if "$SCRIPT_DIR/git-remote-gcrypt" clean --init --force "gcrypt::$tempdir/remote"; then
	print_info "Clean command finished."
else
	print_err "Clean command returned error code."
fi

# Check if file still exists (it should be gone if clean worked)
cd "$tempdir/remote"
files=$($GIT ls-tree -r main | grep "file.txt" || :)
if [ -n "$files" ]; then
	print_err "FAILURE: file.txt still exists on main! (Clean likely failed silently)"
	exit 1
else
	print_info "SUCCESS: file.txt was removed."
fi
