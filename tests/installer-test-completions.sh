#!/bin/bash
# tests/test-completions.sh
# Verifies that bash completion script offers correct commands and excludes plumbing.

# Mock commands if necessary?
# The completion script calls `git remote` etc. We can mock git.

# Setup
TEST_DIR=$(dirname "$0")
COMP_FILE="$TEST_DIR/../completions/bash/git-remote-gcrypt"

if [ ! -f "$COMP_FILE" ]; then
	echo "FAIL: Completion file not found at $COMP_FILE"
	exit 1
fi

# shellcheck source=/dev/null
source "$COMP_FILE"

# Mock variables used by completion
COMP_WORDS=()
COMP_CWORD=0
COMPREPLY=()

# --- Mock git ---
# shellcheck disable=SC2329,SC2317
git() {
	if [[ $1 == "remote" ]]; then
		echo "origin"
		echo "backup"
	fi
}
export -f git

# --- Helper to run completion ---
run_completion() {
	COMP_WORDS=("$@")
	COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
	COMPREPLY=()
	_git_remote_gcrypt
}

# --- Tests ---

FAILURES=0

echo "Test 1: Top-level commands (git-remote-gcrypt [TAB])"
run_completion "git-remote-gcrypt" ""
# Expect: check clean stat -h --help -v --version
# Expect NO: capabilities list push fetch
EXPECTED="check clean stat"
FORBIDDEN="capabilities list push fetch"

OUTPUT="${COMPREPLY[*]}"

for cmd in $EXPECTED; do
	if [[ ! $OUTPUT =~ $cmd ]]; then
		echo "  FAIL: Expected '$cmd' in completion output."
		FAILURES=$((FAILURES + 1))
	fi
done

for cmd in $FORBIDDEN; do
	if [[ $OUTPUT =~ $cmd ]]; then
		echo "  FAIL: Forbidden '$cmd' found in completion output."
		FAILURES=$((FAILURES + 1))
	fi
done

if [[ $OUTPUT =~ check ]] && [[ ! $OUTPUT =~ capabilities ]]; then
	echo "  PASS: Top-level commands look correct."
fi

echo "Test 2: 'stat' subcommand (git-remote-gcrypt stat [TAB])"
run_completion "git-remote-gcrypt" "stat" ""
# Should complete remotes (mocked as origin backup)
OUTPUT="${COMPREPLY[*]}"
if [[ $OUTPUT =~ "origin" ]] && [[ $OUTPUT =~ "backup" ]]; then
	echo "  PASS: 'stat' completes remotes."
else
	echo "  FAIL: 'stat' did not complete remotes. Got: $OUTPUT"
	FAILURES=$((FAILURES + 1))
fi

echo "Test 3: 'clean' subcommand flags (git-remote-gcrypt clean [TAB])"
run_completion "git-remote-gcrypt" "clean" ""
# Should have -f --force etc.
OUTPUT="${COMPREPLY[*]}"
if [[ $OUTPUT =~ "--force" ]] && [[ $OUTPUT =~ "--init" ]]; then
	echo "  PASS: 'clean' completes flags."
else
	echo "  FAIL: 'clean' missing flags. Got: $OUTPUT"
	FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -eq 0 ]; then
	echo "--------------------------"
	echo "All completion tests passed."
	exit 0
else
	echo "--------------------------"
	echo "$FAILURES completion tests FAILED."
	exit 1
fi
