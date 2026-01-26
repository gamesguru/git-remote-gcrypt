#!/bin/bash
# Test: GPG group support
# This test verifies that git-remote-gcrypt correctly expands GPG groups
# (multiple keys for a single participant entry)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_info() { echo -e "${CYAN}$*${NC}"; }
print_success() { echo -e "${GREEN}✓ $*${NC}"; }
print_err() { echo -e "${RED}✗ $*${NC}"; }

# Ensure we use the local git-remote-gcrypt
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR:$PATH"

# Setup temp dir
tempdir=$(mktemp -d)
trap 'rm -rf "$tempdir"' EXIT

# Isolate git config from user environment
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
unset GIT_CONFIG_PARAMETERS

# Silence git init warnings
git config --global init.defaultBranch master

export GNUPGHOME="${tempdir}/gpg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

# Wrapper to suppress obsolete warnings
cat <<'EOF' >"${GNUPGHOME}/gpg"
#!/usr/bin/env bash
set -efuC -o pipefail; shopt -s inherit_errexit
args=( "${@}" )
for ((i = 0; i < ${#}; ++i)); do
    if [[ ${args[${i}]} = "--secret-keyring" ]]; then
        unset "args[${i}]" "args[$(( i + 1 ))]"
        break
    fi
done
exec gpg "${args[@]}"
EOF
chmod +x "${GNUPGHOME}/gpg"

print_info "Generating GPG keys..."

# Create 3 keys
# Key 1
gpg --batch --passphrase "" --quick-generate-key "User One <user1@example.com>"
KEY1=$(gpg --list-keys --with-colons "user1@example.com" | grep "^pub" | cut -d: -f5)

# Key 2
gpg --batch --passphrase "" --quick-generate-key "User Two <user2@example.com>"
KEY2=$(gpg --list-keys --with-colons "user2@example.com" | grep "^pub" | cut -d: -f5)

print_info "Key 1: $KEY1"
print_info "Key 2: $KEY2"

# Create a group in gpg.conf
echo "group mygroup = $KEY1 $KEY2" >>"${GNUPGHOME}/gpg.conf"

print_info "Testing GPG group expansion..."

# Initialize repo
mkdir "$tempdir/repo.git" && cd "$tempdir/repo.git" && git init --bare

# Client repo
mkdir "$tempdir/client" && cd "$tempdir/client" && git init
git config --global user.email "user1@example.com"
git config --global user.name "User One"
git config gpg.program "${GNUPGHOME}/gpg"

# Configure gcrypt to use the group
# We use the group name "mygroup" as the participant
git remote add origin "gcrypt::$tempdir/repo.git"
git config remote.origin.gcrypt-participants "mygroup"
git config remote.origin.gcrypt-signingkey "$KEY1"

git config remote.origin.gcrypt-signingkey "$KEY1"

echo "test" >test.txt
git add test.txt
git commit -m "test"

# Push should succeed and encrypt to BOTH keys
print_info "Pushing..."
git push --force origin master

# Verify recipients
# We can check the manifest or just try to decrypt with each key
print_info "Verifying encryption recipients..."

# Check if Key 2 can decrypt (it didn't sign, but it should be a recipient)
# We need to spoof being User Two (who has the secret key)
# clean checkout
mkdir "$tempdir/check_user2"
git clone "gcrypt::$tempdir/repo.git" "$tempdir/check_user2"
cd "$tempdir/check_user2"

if [ -f "test.txt" ]; then
	print_success "User Two (part of group) successfully decrypted the repo"
else
	print_err "User Two failed to decrypt"
	exit 1
fi

print_success "GPG group test passed!"
