#!/bin/bash
# Test: git-remote-gcrypt works inside a submodule

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

# Setup PATH to use local git-remote-gcrypt (coverage instrumentation support)
test_version=$(git describe --tags --always --dirty 2>/dev/null | sed 's/-\([0-9]*\)-g/+\1~/' || echo "test")
test_version=$(printf '%s\n' "$test_version" | sed 's:[&/\\]:\\&:g')

# Isolate git config from user environment
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL=/dev/null
unset GIT_CONFIG_PARAMETERS

GIT="git -c protocol.file.allow=always -c advice.defaultBranchName=false -c commit.gpgSign=false -c init.defaultBranch=master"

# --------------------------------------------------
# Set up test environment
# --------------------------------------------------
tempdir=$(mktemp -d)
trap 'rm -rf "$tempdir"' EXIT

print_info "Setting up test environment..."

cp "$SCRIPT_DIR/git-remote-gcrypt" "$tempdir/git-remote-gcrypt"
sed "s/@@DEV_VERSION@@/$test_version/" "$tempdir/git-remote-gcrypt" >"$tempdir/git-remote-gcrypt.tmp"
mv "$tempdir/git-remote-gcrypt.tmp" "$tempdir/git-remote-gcrypt"
chmod +x "$tempdir/git-remote-gcrypt"
export PATH=$tempdir:${PATH}

# --------------------------------------------------
# GPG Setup
# --------------------------------------------------
export GNUPGHOME="${tempdir}/gpg"
mkdir "${GNUPGHOME}"

cat <<'EOF' >"${GNUPGHOME}/gpg"
#!/usr/bin/env bash
set -efuC -o pipefail; shopt -s inherit_errexit
args=( "${@}" )
for ((i = 0; i < ${#args[@]}; ++i)); do
    if [[ ${args[${i}]} = "--secret-keyring" ]]; then
        unset "args[${i}]" "args[$(( i + 1 ))]"
        break
    fi
done
exec /usr/bin/gpg "${args[@]}"
EOF
chmod +x "${GNUPGHOME}/gpg"

# Generate key
gpg --batch --passphrase "" --quick-generate-key "Test <test@test.com>" >/dev/null 2>&1

# --------------------------------------------------
# Repo Setup
# --------------------------------------------------

print_info "Creating repos..."
# 1. gcrypt remote
mkdir "$tempdir/remote.git" && cd "$tempdir/remote.git" && $GIT init --bare >/dev/null

# 2. regular remote for submodule
mkdir "$tempdir/sub_remote.git" && cd "$tempdir/sub_remote.git" && $GIT init --bare >/dev/null
cd "$tempdir"
$GIT clone "sub_remote.git" "sub_local" >/dev/null 2>&1
cd "sub_local"
$GIT config user.email "test@test.com"
$GIT config user.name "Test"
echo "submodule init" >sub.txt
$GIT add sub.txt
$GIT commit -m "init sub" >/dev/null
$GIT push origin master >/dev/null 2>&1

# 3. Main repo
cd "$tempdir"
mkdir main_repo && cd main_repo
$GIT init >/dev/null
$GIT config user.email "test@test.com"
$GIT config user.name "Test"

$GIT submodule add "../sub_remote.git" my_submodule >/dev/null 2>&1
$GIT commit -m "add submodule" >/dev/null

# explicitly run git submodule absorbgitdirs to be absolutely sure
$GIT submodule absorbgitdirs my_submodule

# Let's verify .git is a file
cd my_submodule
if [ -d .git ]; then
	print_err ".git is a directory, expected a file!"
	exit 1
fi
if [ ! -f .git ]; then
	print_err ".git file is missing!"
	exit 1
fi

print_success "Submodule .git is a file. (gitdir: $(cat .git))"

$GIT config user.email "test@test.com"
$GIT config user.name "Test"
$GIT config user.signingkey "test@test.com"
$GIT config gpg.program "${GNUPGHOME}/gpg"

# Setup gcrypt remote
$GIT remote add gcrypt-origin "gcrypt::$tempdir/remote.git"
$GIT config remote.gcrypt-origin.gcrypt-participants "test@test.com"

echo "secret data" >secret.txt
$GIT add secret.txt
$GIT commit -m "add secret" >/dev/null

print_info "Pushing via gcrypt from within submodule..."

if ! $GIT push gcrypt-origin master --force; then
	print_err "Push failed!"
	exit 1
fi

print_success "Push succeeded."
print_success "All submodule tests passed!"
