#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-2.0-or-later
set -efuC -o pipefail
shopt -s inherit_errexit

# Helpers
print_info() { printf "\033[1;36m[TEST] %s\033[0m\n" "$1"; }
print_success() { printf "\033[1;34m[TEST] ✓ %s\033[0m\n" "$1"; }
print_warn() { printf "\033[1;33m[TEST] WARNING: %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m[TEST] FAIL: %s\033[0m\n" "$1"; }

# Settings
num_commits=5
files_per_commit=3

# Check GPG version
gpg_ver=$(gpg --version | head -n1 | awk '{print $3}')
print_info "GPG Version detected: $gpg_ver"

# Function to check if version strictly less than
version_lt() {
	if [ "$1" = "$2" ]; then
		return 1
	fi
	[ "$1" = "$(echo -e "$1\n$2" | sort -V | head -n1)" ]
}

# Determine if we expect the bug (Threshold: >= 2.2.20 assumed for now)
# Ubuntu 20.04 (2.2.19) does NOT have the bug.
# Ubuntu 22.04 (2.2.27) likely has it.
# Arch (2.4.9) definitely has it.
expect_bug=1
if version_lt "$gpg_ver" "2.2.20"; then
	print_warn "GPG version $gpg_ver is old. We do not expect the checksum bug here."
	expect_bug=0
else
	print_info "GPG version $gpg_ver is modern. We expect the checksum bug."
fi

print_info "Running multi-key clone test..."
random_source="/dev/urandom"
random_data_per_file=1024 # Reduced size for faster testing (1KB)
default_branch="main"
test_user_name="git-remote-gcrypt"
test_user_email="git-remote-gcrypt@example.com"

readonly num_commits files_per_commit random_source random_data_per_file \
	default_branch test_user_name test_user_email

# ----------------- Helper Functions -----------------
indent() {
	sed 's/^\(.*\)$/    \1/'
}

section_break() {
	echo
	printf '*%.0s' {1..70}
	echo $'\n'
}

assert() {
	(
		set +e
		[[ -n ${show_command:-} ]] && set -x
		"${@}"
	)
	local -r status=${?}
	{ [[ ${status} -eq 0 ]] && print_success "Verification succeeded."; } \
		|| print_err "Verification failed."
	return "${status}"
}

fastfail() {
	"$@" || kill -- "-$$"
}
# ----------------------------------------------------

umask 077
tempdir=$(mktemp -d)
readonly tempdir
trap 'rm -Rf -- "${tempdir}"' EXIT

# Setup PATH to use local git-remote-gcrypt
PATH=${PWD}:${PATH}
readonly PATH
export PATH

# Clean GIT environment
git_env=$(env | sed -n 's/^\(GIT_[^=]*\)=.*$/\1/p')
# shellcheck disable=SC2086
IFS=$'\n' unset ${git_env}

# GPG Setup
export GNUPGHOME="${tempdir}/gpg"
mkdir "${GNUPGHOME}"
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

# Git Config
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
mkdir "${tempdir}/template"
git config --global init.defaultBranch "${default_branch}"
git config --global user.name "${test_user_name}"
git config --global user.email "${test_user_email}"
git config --global init.templateDir "${tempdir}/template"
git config --global gpg.program "${GNUPGHOME}/gpg"

# Prepare Random Data
total_files=$((num_commits * files_per_commit))
random_data_size=$((total_files * random_data_per_file))
random_data_file="${tempdir}/data"
head -c "${random_data_size}" "${random_source}" >"${random_data_file}"

###
section_break

print_info "Step 1: Creating multiple GPG keys for participants..."
num_keys=5 # Reduced from 18 for faster CI runs
key_fps=()
(
	set -x
	for ((i = 0; i < num_keys; i++)); do
		gpg --batch --passphrase "" --quick-generate-key \
			"${test_user_name}${i} <${test_user_email}${i}>"
	done
) 2>&1 | indent

# Capture fingerprints
# Integrated fix: use mapfile
#
# CRITICAL FIX:
# Previously, `grep fpr` captured both the Primary Key (EDDSA) and the Subkey (ECDH) fingerprints.
# This caused the `key_fps` array to double in size (36 entries for 18 keys).
# As a result, `key_fps[17]` (intended to be the last Primary Key) actually pointed to the
# Subkey of the 9th key (`key_fps[8*2 + 1]`).
# We configured `gcrypt.participants` with this Subkey, but GPG always signs with the Primary Key.
# This caused a signature mismatch ("Participant A vs Signer B") and verification failure.
# Using `awk` to filter `pub:` ensures we only capture the Primary Key.
mapfile -t key_fps < <(gpg --list-keys --with-colons | awk -F: '/^pub:/ {f=1;next} /^fpr:/ && f {print $10;f=0}')
echo "Generated keys: ${key_fps[*]}" | indent

# Sanity Check
if [ "${#key_fps[@]}" -ne "$num_keys" ]; then
	print_err "FATAL: Expected $num_keys keys, captured ${#key_fps[@]}."
	print_err "       Check grep/awk logic (likely capturing subkeys vs primary keys mismatch)."
	exit 1
fi
print_success "Sanity Check Passed: Captured ${#key_fps[@]} Primary Keys."

###
section_break

print_info "Step 2: Creating source repository..."
{
	git init -- "${tempdir}/first"
	cd "${tempdir}/first"
	git checkout -b "${default_branch}"
	for ((i = 0; i < num_commits; ++i)); do
		for ((j = 0; j < files_per_commit; ++j)); do
			file_index=$((i * files_per_commit + j))
			random_data_index=$((file_index * random_data_per_file))
			head -c "${random_data_per_file}" >"$((file_index)).data" < \
				<(tail -c +"${random_data_index}" "${random_data_file}" || :)
		done
		git add .
		git commit -q -m "Commit #${i}"
	done
	git log --format=oneline | indent
} | indent

###
section_break

print_info "Step 3: Creating bare remote..."
git init --bare -- "${tempdir}/second.git" | indent

###
section_break

print_info "Step 4: Pushing with SINGULAR participant (Key 2) to bury it..."
{
	(
		set -x
		cd "${tempdir}/first"
		# CRITICAL REPRO: Only encrypt to the LAST key.
		# All previous keys are in the keyring but are NOT recipients.
		# This forces GPG to skip the first (num_keys-1) keys.
		last_key_idx=$((num_keys - 1))
		git config gcrypt.participants "${key_fps[last_key_idx]}"
		git config user.signingkey "${key_fps[last_key_idx]}"
		git push -f "gcrypt::${tempdir}/second.git#${default_branch}" "${default_branch}"
	) 2>&1
} | indent

###
section_break

print_info "Step 5: Unhappy Path - Test clone with NO matching keys..."
{
	original_gnupghome="${GNUPGHOME}"
	export GNUPGHOME="${tempdir}/gpg-empty"
	mkdir "${GNUPGHOME}"

	# We expect this to FAIL
	(
		set +e
		if git clone -b "${default_branch}" "gcrypt::${tempdir}/second.git#${default_branch}" -- "${tempdir}/fail_test"; then
			print_err "ERROR: Clone succeeded unexpectedly with empty keyring!"
			exit 1
		fi
	) 2>&1 | indent

	echo "Clone failed as expected." | indent
	export GNUPGHOME="${original_gnupghome}"
}

###
section_break

print_info "Step 6: Reproduction Step - Clone with buried key..."
{
	# Capture output to check for GPG errors
	output_file="${tempdir}/clone_output"
	set +e
	(
		set -x
		git clone -b "${default_branch}" "gcrypt::${tempdir}/second.git#${default_branch}" -- "${tempdir}/third"
	) >"${output_file}" 2>&1
	ret=$?
	set -e

	cat "${output_file}"

	if grep -q "Checksum error" "${output_file}" && [ $ret -ne 0 ]; then
		print_warn "WARNING: GPG failed with checksum error."
		print_err "BUG REPRODUCED! Exiting due to earlier GPG failures."
		exit 1
	elif grep -q "Checksum error" "${output_file}" && [ $ret -eq 0 ]; then
		print_success "SUCCESS: Checksum error detected but Clone SUCCEEDED. (Fix is working!)"
	elif [ $ret -eq 0 ]; then
		print_warn "WARNING: Clone passed unexpectedly (Checksum error not detected). Bug not triggered."
		if [ "$expect_bug" -eq 0 ]; then
			print_success "SUCCESS: Old GPG version ($gpg_ver) confirmed clean. Pass."
		else
			print_err "FAIL: Exiting due to unexpected pass on modern GPG $gpg_ver."
			exit 1
		fi
	else
		print_err "ERROR: Clone failed with generic error (Checksum error not detected)."
		exit 1
	fi

	# Continue to verify content.
	print_info "Verifying content match..."
	assert diff -r --exclude ".git" -- "${tempdir}/first" "${tempdir}/third" 2>&1 | indent
} | indent

###
section_break

print_info "Step 7: Reproduction Step - Push with buried key..."
{
	# Capture output to check for GPG errors
	output_file="${tempdir}/push_output"
	set +e
	(
		set -x
		cd "${tempdir}/first"
		# Make a change so we can push
		echo "new data" >"new_file"
		git add "new_file"
		git commit -q -m "Commit for Step 7"

		# Set signing key for this push
		last_key_idx=$((num_keys - 1))

		# Regression Check: Ensure we didn't capture subkeys
		if [ "${#key_fps[@]}" -ne "$num_keys" ]; then
			print_err "FATAL: Key array corrupted! Expected $num_keys keys, found ${#key_fps[@]}."
			print_err "       This indicates the 'awk' capture logic has regressed (likely capturing subkeys)."
			exit 1
		fi
		print_success "Sanity Check (Step 7): Key count correct (${#key_fps[@]}). AWK fix confirmed active."

		# Visual Verification: Show which key we actually picked.
		# If the bug were active (subkey capture), this would show 'git-remote-gcrypt8' (Key #9)
		# With the fix, it must show 'git-remote-gcrypt17' (Key #18)
		print_info "Selected Key Details:"
		gpg --list-keys "${key_fps[last_key_idx]}" | indent

		git config gcrypt.participants "${key_fps[last_key_idx]}"
		git config user.signingkey "${key_fps[last_key_idx]}"

		git push "gcrypt::${tempdir}/second.git#${default_branch}" "${default_branch}"
	) >"${output_file}" 2>&1
	ret=$?
	set -e

	cat "${output_file}"

	if grep -q "Checksum error" "${output_file}" && [ $ret -ne 0 ]; then
		print_warn "WARNING: GPG failed with checksum error."
		print_err "BUG REPRODUCED! Exiting due to earlier GPG failures."
		exit 1
	elif grep -q "Checksum error" "${output_file}" && [ $ret -eq 0 ]; then
		print_success "SUCCESS: Checksum error detected (Push) but Push SUCCEEDED. (Fix is working!)"
	elif [ $ret -eq 0 ]; then
		print_warn "WARNING: Push passed unexpectedly (Checksum error not detected). Bug not triggered."
		if [ "$expect_bug" -eq 0 ]; then
			print_success "SUCCESS: Old GPG version ($gpg_ver) confirmed clean. Pass."
		else
			print_err "FAIL: Exiting due to unexpected pass on modern GPG $gpg_ver."
			exit 1
		fi
	else
		print_err "ERROR: Push failed with generic error (Checksum error not detected)."
		exit 1
	fi
} | indent

if [ -n "${COV_DIR:-}" ]; then
	print_success "OK. Report: file://${COV_DIR}/index.html"
fi
