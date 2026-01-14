#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Large Object Test - Tests pack size limits and repacking behavior
# This test uses larger files to trigger Git's pack splitting.
#
set -efuC -o pipefail
shopt -s inherit_errexit

# Helpers
print_info() { printf "\033[1;36m%s\033[0m\n" "$1"; }
print_success() { printf "\033[1;34m✓ %s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m%s\033[0m\n" "$1"; }

indent() {
	sed 's/^\(.*\)$/    \1/'
}

section_break() {
	echo
	printf '*%.0s' {1..70}
	echo $'\n'
}

# Test parameters - large files to test pack splitting
num_commits=5
files_per_commit=3
random_source="/dev/urandom"
random_data_per_file=${GCRYPT_TEST_REPACK_SCENARIO_BLOB_SIZE:-5242880} # 5 MiB default
default_branch="main"
test_user_name="git-remote-gcrypt"
test_user_email="git-remote-gcrypt@example.com"
pack_size_limit=${GCRYPT_TEST_PACK_SIZE_LIMIT:-12m} # Original upstream value

readonly num_commits files_per_commit random_source random_data_per_file \
	default_branch test_user_name test_user_email pack_size_limit

print_info "Running large object system test..."
print_info "This test uses ${random_data_per_file} byte files to test pack size limits."

umask 077
tempdir=$(mktemp -d)
readonly tempdir
# shellcheck disable=SC2064
trap "rm -Rf -- '${tempdir}'" EXIT

# Set up the PATH
repo_root=$(git rev-parse --show-toplevel)
test_version=$(git describe --tags --always --dirty 2>/dev/null || echo "test")
cp "$repo_root/git-remote-gcrypt" "$tempdir/git-remote-gcrypt"
sed -i "s/@@DEV_VERSION@@/$test_version/" "$tempdir/git-remote-gcrypt"
chmod +x "$tempdir/git-remote-gcrypt"
PATH=$tempdir:${PATH}
readonly PATH
export PATH

# Unset any GIT_ environment variables
git_env=$(env | sed -n 's/^\(GIT_[^=]*\)=.*$/\1/p')
# shellcheck disable=SC2086
IFS=$'\n' unset ${git_env}

# Ensure a predictable gpg configuration.
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

# Ensure a predictable git configuration.
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL="${tempdir}/gitconfig"
mkdir "${tempdir}/template"
git config --global init.defaultBranch "${default_branch}"
git config --global user.name "${test_user_name}"
git config --global user.email "${test_user_email}"
git config --global init.templateDir "${tempdir}/template"
git config --global gpg.program "${GNUPGHOME}/gpg"
git config --global pack.packSizeLimit "${pack_size_limit}"

# Prepare the random data
total_files=$((num_commits * files_per_commit))
random_data_size=$((total_files * random_data_per_file))
random_data_file="${tempdir}/data"
print_info "Generating ${random_data_size} bytes of random data..."
head -c "${random_data_size}" "${random_source}" >"${random_data_file}"

###
section_break

print_info "Step 1: Creating GPG key..."
(
	set -x
	gpg --batch --passphrase "" --quick-generate-key \
		"${test_user_name} <${test_user_email}>"
) 2>&1 | indent

###
section_break

print_info "Step 2: Creating repository with large random files..."
{
	git init -- "${tempdir}/first"
	cd "${tempdir}/first"
	for ((i = 0; i < num_commits; ++i)); do
		for ((j = 0; j < files_per_commit; ++j)); do
			file_index=$((i * files_per_commit + j))
			random_data_index=$((file_index * random_data_per_file))
			echo "Writing large file $((file_index + 1))/${total_files} ($((random_data_per_file / 1024 / 1024)) MiB)"
			head -c "${random_data_per_file}" >"$((file_index)).data" < \
				<(tail -c "+$((random_data_index + 1))" "${random_data_file}" || :)
		done
		git add -- "${tempdir}/first"
		git commit -m "Commit #${i}"
	done
} | indent

###
section_break

print_info "Step 3: Creating bare repository..."
git init --bare -- "${tempdir}/second.git" | indent

###
section_break

print_info "Step 4: Pushing with large files (testing pack size limits)..."
{
	(
		set -x
		cd "${tempdir}/first"
		git push -f "gcrypt::${tempdir}/second.git#${default_branch}" \
			"${default_branch}"
	) 2>&1

	echo
	echo "Object files in second.git (should show pack splitting if limit hit):"
	(
		cd "${tempdir}/second.git/objects"
		find . -type f -exec du -sh {} + | sort -h
	) | indent

	# Count object files
	obj_count=$(find "${tempdir}/second.git/objects" -type f | wc -l)
	echo
	echo "Total object files: ${obj_count}"

	if [ "$obj_count" -gt 1 ]; then
		print_success "Multiple pack objects created (pack splitting occurred)."
	else
		print_info "Single pack object (data may not exceed limit)."
	fi
} | indent

###
section_break

print_info "Step 5: Cloning and verifying large files..."
{
	(
		set -x
		git clone -b "${default_branch}" \
			"gcrypt::${tempdir}/second.git#${default_branch}" -- \
			"${tempdir}/third"
	) 2>&1

	echo
	echo "Verifying file integrity..."
	if diff -r --exclude ".git" -- "${tempdir}/first" "${tempdir}/third" >/dev/null 2>&1; then
		print_success "All large files verified correctly."
	else
		print_err "File verification failed!"
		exit 1
	fi
} | indent

###
section_break

print_success "Large object test completed successfully."
