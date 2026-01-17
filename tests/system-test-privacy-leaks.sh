#!/usr/bin/env bash
set -efuC -o pipefail
shopt -s inherit_errexit

# Helpers
print_info() { printf "\033[1;36m%s\033[0m\n" "$1"; }
print_success() { printf "\033[1;34m✓ %s\033[0m\n" "$1"; }
print_warn() { printf "\033[1;33m%s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m%s\033[0m\n" "$1"; }

umask 077
tempdir=$(mktemp -d)
readonly tempdir
trap 'rm -Rf -- "$tempdir"' EXIT

# Ensure git-remote-gcrypt is in PATH
repo_root=$(git rev-parse --show-toplevel)
test_version=$(git describe --tags --always --dirty 2>/dev/null || echo "test")
cp "$repo_root/git-remote-gcrypt" "$tempdir/git-remote-gcrypt"
sed "s/@@DEV_VERSION@@/$test_version/" "$tempdir/git-remote-gcrypt" >"$tempdir/git-remote-gcrypt.tmp"
mv "$tempdir/git-remote-gcrypt.tmp" "$tempdir/git-remote-gcrypt"
chmod +x "$tempdir/git-remote-gcrypt"
PATH=$tempdir:${PATH}
export PATH

# Setup GPG
export GNUPGHOME="${tempdir}/gpg"
mkdir "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

print_info "Step 1: generating GPG key..."
cat >"${tempdir}/key_params" <<EOF
%echo Generating a basic OpenPGP key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: Test User
Name-Comment: for gcrypt test
Name-Email: test@example.com
Expire-Date: 0
%no-protection
%commit
%echo done
EOF
gpg --batch --generate-key "${tempdir}/key_params" >/dev/null 2>&1

# Git config
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
unset GIT_CONFIG_PARAMETERS
git config --global user.name "Test User"
git config --global user.email "test@example.com"
git config --global init.defaultBranch "master"
git config --global commit.gpgsign false

print_info "Step 2: Create a 'compromised' remote repo"
# This simulates a repo where someone accidentally pushed a .env file
mkdir -p "${tempdir}/remote-repo"
cd "${tempdir}/remote-repo"
git init --bare

# Creating the dirty history
mkdir "${tempdir}/dirty-setup"
cd "${tempdir}/dirty-setup"
git init
git remote add origin "${tempdir}/remote-repo"
echo "API_KEY=12345-SUPER-SECRET" >.env
git add .env
git commit -m "Oops, pushed secret keys"
git push origin master

print_info "Step 3: Switch to git-remote-gcrypt usage"
# Now the user realizes their mistake (or just switches tools) and uses gcrypt
# expecting it to be secure.
mkdir "${tempdir}/local-gcrypt"
cd "${tempdir}/local-gcrypt"
git init
echo "safe encrypted data" >sensible_data.txt
git add sensible_data.txt
git commit -m "Initial encrypted commit"

git remote add origin "gcrypt::${tempdir}/remote-repo"
git config remote.origin.gcrypt-participants "test@example.com"
git config remote.origin.gcrypt-signingkey "test@example.com"

# Force push is required to initialize gcrypt over an existing repo
# Now EXPECT FAILURE because of our new safety check!
print_info "Attempting push to dirty repo (should fail due to safety check)..."
if git push --force origin master 2>/dev/null; then
	print_err "Safety check FAILED: Push succeeded but should have been blocked."
	exit 1
else
	print_success "Safety check PASSED: Push was blocked."
fi

# Now verify we can bypass it
print_info "Attempting push with bypass config..."
git config remote.origin.gcrypt-allow-unencrypted-remote true
git push --force origin master
print_success "Push with bypass succeeded."

print_info "Step 4: Verify LEAKAGE"
# We check the backend repo directly.
# If gcrypt worked "perfectly" (in a privacy sense), the old .env would be gone.
# But we know it persists.
cd "${tempdir}/remote-repo"

if git ls-tree -r master | grep -q ".env"; then
	print_warn "PRIVACY LEAK DETECTED: .env file matches found in remote!"
	print_warn "Content of .env in remote:"
	git show master:.env
	print_success "Test Passed: Vulnerability successfully reproduced."
else
	print_err "Unexpected: .env file NOT found. Did gcrypt overwrite it?"
	# detecting it is 'failure' of the vulnerability check, but 'success' for privacy
	exit 1
fi

print_info "Step 5: Mitigate the leak (manual cleanup)"
# Simulate the user cleaning up
cd "${tempdir}"
git clone "${tempdir}/remote-repo" "${tempdir}/cleanup-client"
cd "${tempdir}/cleanup-client"
git config user.email "cleanup@example.com"
git config user.name "Cleanup User"
git config commit.gpgsign false

if [ -f .env ]; then
	git rm .env
	git commit -m "Cleanup leaked .env"
	git push origin master
	print_success "Cleanup pushed."
else
	print_warn ".env not found in cleanup client? This is odd."
fi

print_info "Step 6: Verify leak is gone"
cd "${tempdir}/remote-repo"
if git ls-tree -r master | grep -q ".env"; then
	print_err "Cleanup FAILED: .env still exists!"
	exit 1
else
	print_success "Cleanup VERIFIED: .env is gone."
fi

print_info "Step 7: Verify gcrypt still works"
cd "${tempdir}/local-gcrypt"
echo "more data" >>sensible_data.txt
git add sensible_data.txt
git commit -m "Post-cleanup commit"
if git push origin master; then
	print_success "Gcrypt push succeeded after cleanup."
else
	print_err "Gcrypt push FAILED after cleanup."
	exit 1
fi

print_success "ALL TESTS PASSED."
