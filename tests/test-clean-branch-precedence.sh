#!/bin/bash
# Test: clean command fails if master exists but is empty, and files are on main
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
mkdir "$tempdir/seeder_main" && cd "$tempdir/seeder_main"
$GIT init -b main
$GIT remote add origin "$tempdir/remote"
echo "SECRET DATA" >secret.txt
$GIT add secret.txt
$GIT config user.email "test@test.com"
$GIT config user.name "Test"
$GIT commit -m "Add secret"
$GIT push origin main

# 3. Create an empty 'master' branch on the remote using a second seeder
# We do this by pushing an unrelated history or just a new branch
print_info "Creating empty 'master' on remote..."
mkdir "$tempdir/seeder_master" && cd "$tempdir/seeder_master"
$GIT init -b master
$GIT remote add origin "$tempdir/remote"
touch empty.txt
$GIT add empty.txt
$GIT config user.email "test@test.com"
$GIT config user.name "Test"
$GIT commit -m "Add empty"
$GIT push origin master

# Now remote has both master (with empty.txt) and main (with secret.txt)
# But wait, if master has empty.txt, `clean` should at least find empty.txt.
# We want to simulate a case where `master` is "empty" or irrelevant, but `main` is the real one.
# If `master` has files, `clean` will report them.
# The user said: "Remote is empty. Nothing to clean."
# This implies `master` has NO files?
# How can a branch exist but have no files?
# Maybe `git ls-tree -r master` returns nothing if the branch is truly empty (e.g. only contains a .gitignore that was filtered out, or maybe just literally empty tree - possible in git but hard to maximize).
# Or maybe the user has `master` that is just NOT the one with the data.
# The user's output "Remote is empty" suggests `clean` found NOTHING.
# If `master` had `empty.txt`, `clean` would list `empty.txt`.

# Let's clean up `master` to be truly empty?
# GIT allows empty commits but they still have a tree.
# If we delete all files from master?
cd "$tempdir/seeder_master"
$GIT rm empty.txt
$GIT commit -m "Remove all"
$GIT push origin master

# Now master exists but has NO files. "secret.txt" is on main.
# `clean` should ideally check `main` (or all branches) and find `secret.txt`.
# If `clean` only checks `master`, it will see empty tree and say "Remote is clean".

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

# 5. Check if secret.txt is still there
cd "$tempdir/remote"
if $GIT -c core.quotePath=false ls-tree -r main | grep -q "secret.txt"; then
	print_err "FAILURE: secret.txt still exists on main!"
	exit 1
else
	print_success "SUCCESS: secret.txt was removed (or wasn't there)."
	# If it wasn't there, we need to know if we actually cleaned it.
	# The clean output should have mentioned it.
fi
