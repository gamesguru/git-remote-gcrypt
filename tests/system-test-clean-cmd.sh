#!/bin/bash
# tests/test-clean-complex.sh
# Verifies clean command on filenames with spaces and parentheses.

TEST_DIR=$(dirname "$0")
BIN="$TEST_DIR/../git-remote-gcrypt"
git_remote_gcrypt() {
	bash "$BIN" "$@"
}

# Setup temp environment
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Create a "remote" bare repo to simulate git backend
REMOTE_REPO="$TMPDIR/remote.git"
git init --bare "$REMOTE_REPO" >/dev/null

# Create a commit in the remote with "garbage" files
# We need to simulate how git-remote-gcrypt stores files (in refs/gcrypt/...)
# or just in master if it's a raw repo being cleaned?
# If we run clean --init, we are cleaning a raw repo. So files are in HEAD (or master/main).

# Helper to create commit
(
	cd "$TMPDIR" || exit 1
	mkdir worktree
	cd worktree || exit 1
	git init >/dev/null
	git remote add origin "$REMOTE_REPO"

	# Create files with spaces and parens
	mkdir -p ".csv"
	touch ".csv/sheet-shanes-secondary-sheets-Univ Grades (OU).csv"
	touch "normal.txt"

	git add .
	git commit -m "Initial commit with garbage" >/dev/null
	git push origin master >/dev/null
)

URL="file://$REMOTE_REPO"

echo "--- Status before clean ---"
# We can use git ls-tree on remote to verify
git --git-dir="$REMOTE_REPO" ls-tree -r master --name-only

echo "--- Running clean --init --force ---"
OUTPUT=$(git_remote_gcrypt clean --init --force "$URL" 2>&1)
EXIT_CODE=$?
echo "$OUTPUT"

if [ $EXIT_CODE -ne 0 ]; then
	echo "FAIL: clean command failed."
	exit 1
fi

echo "--- Status after clean ---"
FILES=$(git --git-dir="$REMOTE_REPO" ls-tree -r master --name-only)
echo "$FILES"

if [[ $FILES == *".csv"* ]]; then
	# We expect the file to be GONE.
	# Note: clean --init --force deletes ALL files (because map is not found)
	# So if there are ANY files left, it's a fail.
	# But clean command actually updates the refs (typically master or refs/gcrypt/...).
	# Wait, git-remote-gcrypt clean cleans "refs/heads/master" or "refs/heads/main" if mapped?
	# No, it checks what files are there.
	# If standard remote, it might be cleaning HEAD?

	# Let's check if the file persists.
	if echo "$FILES" | grep -q "Univ Grades"; then
		echo "FAIL: The complex filename was NOT removed."
		exit 1
	fi
fi

if [ -z "$FILES" ]; then
	echo "PASS: All files removed."
else
	# It might leave an empty tree or commit?
	echo "FAIL: Files persist: $FILES"
	exit 1
fi
