#!/usr/bin/env bash
# Tests for branch deletion to trigger REMOVE and gitception_remove
set -efuC -o pipefail
shopt -s inherit_errexit

# ----------------- Setup -----------------
indent() { sed 's/^\(.*\)$/    \1/'; }
section_break() { echo; printf '*%.0s' {1..70}; echo $'\n'; }

umask 077
tempdir=$(mktemp -d)
trap "rm -Rf -- '${tempdir}'" EXIT

# Setup PATH
PATH=$(git rev-parse --show-toplevel):${PATH}
export PATH

# GPG Setup
export GNUPGHOME="${tempdir}/gpg"
mkdir -p "${GNUPGHOME}"
echo "no-tty" >> "$GNUPGHOME/gpg.conf"
echo "pinentry-mode loopback" >> "$GNUPGHOME/gpg.conf"

echo "Generating GPG key..."
gpg --batch --passphrase "" --quick-generate-key "deleter <del@example.com>" 2>&1 | indent
key_fp=$(gpg --list-keys --with-colons | grep "^fpr" | head -n1 | cut -d: -f10)

# Git Config
export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
git config --global user.name "Deleter"
git config --global user.email "del@example.com"
git config --global init.defaultBranch "main"
git config --global gcrypt.participants "$key_fp"
git config --global gcrypt.gpg-args "--pinentry-mode loopback --no-tty"

# ----------------- Tests -----------------

section_break
echo "Test 1: Delete a remote branch (Triggers gitception_remove)"
{
	# 1. Init and push TWO branches
	git init -- "${tempdir}/repo"
	cd "${tempdir}/repo"
	touch file1 && git add file1 && git commit -m "Main commit"

	git checkout -b feature
	touch file2 && git add file2 && git commit -m "Feature commit"

	# Push both to remote
	echo "Pushing main and feature..."
	git push "gcrypt::${tempdir}/remote" main feature 2>&1 | indent

	# 2. Verify both exist
	echo "Verifying refs before delete..."
	git ls-remote "gcrypt::${tempdir}/remote" | grep "refs/heads/" | indent

	# 3. DELETE the feature branch
	# This syntax (:branch_name) tells git to delete the remote ref
	echo "DELETING feature branch..."
	git push "gcrypt::${tempdir}/remote" :feature 2>&1 | indent

	# 4. Verify 'feature' is gone but 'main' remains
	echo "Verifying deletion..."
	refs=$(git ls-remote "gcrypt::${tempdir}/remote")
	echo "$refs" | indent

	if echo "$refs" | grep -q "refs/heads/feature"; then
		echo "❌ ERROR: Feature branch was NOT deleted!"
		exit 1
	fi

	if ! echo "$refs" | grep -q "refs/heads/main"; then
		echo "❌ ERROR: Main branch was accidentally deleted!"
		exit 1
	fi

	echo "✅ PASS: Branch deletion successful."
} | indent

section_break
echo "Test 2: Delete a Tag (Triggers line_count logic via manifest rewrite)"
{
	cd "${tempdir}/repo"
	git checkout main
	git tag v1.0

	echo "Pushing tag v1.0..."
	git push "gcrypt::${tempdir}/remote" v1.0 2>&1 | indent

	echo "Deleting tag v1.0..."
	git push "gcrypt::${tempdir}/remote" :v1.0 2>&1 | indent

	# Verify
	if git ls-remote "gcrypt::${tempdir}/remote" | grep -q "refs/tags/v1.0"; then
		echo "❌ ERROR: Tag was NOT deleted!"
		exit 1
	fi
	echo "✅ PASS: Tag deletion successful."
} | indent

echo
echo "Deletion tests passed."
