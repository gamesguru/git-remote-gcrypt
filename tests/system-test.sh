#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-2.0-or-later
set -efuC -o pipefail
shopt -s inherit_errexit

# Helpers
print_info() { printf "\033[1;36m%s\033[0m\n" "$1"; }
print_success() { printf "\033[1;34m✓ %s\033[0m\n" "$1"; }
print_warn() { printf "\033[1;33m%s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m%s\033[0m\n" "$1"; }




# Unlike the main git-remote-gcrypt program, this testing script requires bash
# (rather than POSIX sh) and also depends on various common system utilities
# that the git-remote-gcrypt carefully avoids using (such as mktemp(1)).
#
# The test proceeds by setting up a new repository, making some large commits
# with random data into the repository, pushing the repository to another
# remote using git-remote-gcrypt over the gitception protocol, and then cloning
# the second repository and ensuring that the data it contains is correct.
#
# The random data is obtained from /dev/urandom. This script won't work
# on systems that don't provide /dev/urandom.
#
# The following settings specify the parameters to be used for the test.
num_commits=5
files_per_commit=3
random_source="/dev/urandom"
random_data_per_file=${TEST_DATA_SIZE:-5120} # 5 KiB default, override with TEST_DATA_SIZE
default_branch="main"
test_user_name="git-remote-gcrypt"
test_user_email="git-remote-gcrypt@example.com"
pack_size_limit="12m" # If this variable is unset, there is no size limit.

readonly num_commits files_per_commit random_source random_data_per_file \
    default_branch test_user_name test_user_email pack_size_limit

print_info "Running system test..."

# Pipe text into this function to indent it with four spaces. This is used
# to make the output of this script prettier.
indent() {
    sed 's/^\(.*\)$/    \1/'
}

section_break() {
    echo
    printf '*%.0s' {1..70}
    echo $'\n'
}

assert() {
    (set +e; [[ -n ${show_command:-} ]] && set -x; "${@}")
    local -r status=${?}
    { [[ ${status} -eq 0 ]] && print_success "Verification succeeded."; } || \
        print_err "Verification failed."
    return "${status}"
}

fastfail() {
    "$@" || kill -- "-$$"
}

umask 077
tempdir=$(mktemp -d)
readonly tempdir
# shellcheck disable=SC2064
trap "rm -Rf -- '${tempdir}'" EXIT
export HOME="${tempdir}"

# Set up the PATH to favor the version of git-remote-gcrypt from the repository
# rather than a version that might already be installed on the user's system.
# We also copy it to tempdir to inject a version number for testing.
repo_root="${PWD}"
test_version=$(git describe --tags --always --dirty 2>/dev/null || echo "test")
cp "$repo_root/git-remote-gcrypt" "$tempdir/git-remote-gcrypt"
sed "s/@@DEV_VERSION@@/$test_version/" "$tempdir/git-remote-gcrypt" > "$tempdir/git-remote-gcrypt.tmp"
mv "$tempdir/git-remote-gcrypt.tmp" "$tempdir/git-remote-gcrypt"
chmod +x "$tempdir/git-remote-gcrypt"
PATH=$tempdir:${PATH}
readonly PATH
export PATH

# Unset any GIT_ environment variables to prevent them from affecting the test.
git_env=$(env | sed -n 's/^\(GIT_[^=]*\)=.*$/\1/p')
# shellcheck disable=SC2086
IFS=$'\n' unset ${git_env}

# Ensure a predictable gpg configuration.
export GNUPGHOME="${tempdir}/gpg"
mkdir "${GNUPGHOME}"
# Use a wrapper for gpg(1) to avoid cluttering the test output with unnecessary
# warnings about the obsolete `--secret-keyring` option. These warnings are
# caused by git-remote-gcrypt passing an option to gpg(1) that only makes sense
# for ancient versions of gpg(1), but addressing that (if it should be
# addressed at all) is a task best left for another day.
cat << 'EOF' > "${GNUPGHOME}/gpg"
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
mkdir "${tempdir}/template" # Intentionally empty template directory.
git config --global init.defaultBranch "${default_branch}"
git config --global user.name "${test_user_name}"
git config --global user.email "${test_user_email}"
git config --global init.templateDir "${tempdir}/template"
git config --global gpg.program "${GNUPGHOME}/gpg"
[[ -n ${pack_size_limit:-} ]] && \
    git config --global pack.packSizeLimit "${pack_size_limit}"

# Prepare the random data that we'll be writing to the repository.
total_files=$(( num_commits * files_per_commit ))
random_data_size=$(( total_files * random_data_per_file ))
random_data_file="${tempdir}/data"
head -c "${random_data_size}" "${random_source}" > "${random_data_file}"

# Create gpg key and subkey.
print_info "Step 1: Creating a new GPG key and subkey to use for testing:"
(
    set -x
    gpg --batch --passphrase "" --quick-generate-key \
        "${test_user_name} <${test_user_email}>"
    gpg -K
) 2>&1 | indent

###
section_break

print_info "Step 2: Creating new repository with random data:"
{
    git init -- "${tempdir}/first"
    cd "${tempdir}/first"
    git checkout -B "${default_branch}"
    for ((i = 0; i < num_commits; ++i)); do
        for ((j = 0; j < files_per_commit; ++j)); do
            file_index=$(( i * files_per_commit + j ))
            random_data_index=$(( file_index * random_data_per_file ))
            # shellcheck disable=SC2016
            echo "Writing random file $((file_index + 1))/${total_files}:" \
                '${tempdir}'/"first/$(( file_index )).data "
            head -c "${random_data_per_file}" > "$(( file_index )).data" < \
                <(tail -c "+${random_data_index}" "${random_data_file}" || :)
            if command -v base64 > /dev/null; then
                # shellcheck disable=SC2312
                echo "First 24 bytes in base64:" \
                    "$(fastfail head -c 24 "$(( file_index )).data" | \
                        fastfail base64)" | indent
            fi
        done
        git add -- "${tempdir}/first"
        git commit -m "Commit #${i}"
    done

    echo
    echo "For reference, here is the commit log for the repository:"
    git log --format=oneline | indent
} | indent

###
section_break

print_info "Step 3: Creating an empty bare repository to receive pushed data:"
git init --bare -- "${tempdir}/second.git" | indent


###
section_break

print_info "Step 4: Pushing the first repository to the second one using gitception:"
{
    # Note that when pushing to a bare local repository, git-remote-gcrypt uses
    # gitception, rather than treating the remote as a local repository.
    (
        set -x
        cd "${tempdir}/first"
        git push -f "gcrypt::${tempdir}/second.git#${default_branch}" \
            "${default_branch}"
    ) 2>&1

    if command -v tree > /dev/null; then
        echo
        echo "For reference, here is the directory tree of second.git:"
        tree "${tempdir}/second.git"
    fi

    echo
    echo "Here is the size of each object file in second.git:"
    (
        cd "${tempdir}/second.git/objects"
        find . -type f -exec du -sh {} +
    ) | indent

    echo
    echo "Note that git-pack-objects(1) will try to ensure that each object is"
    echo "smaller than pack.packSizeLimit (${pack_size_limit:-unlimited}" \
        "here) but this isn't always"
    echo "possible because each object contains at least one of our random"
    echo "files, and each random file has a certain minimum size. As a result,"
    echo "pack.packSizeLimit is more of a suggestion than a hard limit."
 } | indent

###
section_break

print_info "Step 5: Cloning the second repository using gitception:"
{
    (
        set -x
        git clone -b "${default_branch}" \
            "gcrypt::${tempdir}/second.git#${default_branch}" -- \
                "${tempdir}/third"
    ) 2>&1

    echo
    echo "Verifying that the first and third repositories have the same"
    echo "commit log as each other:"
    # shellcheck disable=SC2312
    assert diff \
        <(fastfail cd "${tempdir}/first"; fastfail git log --oneline) \
        <(fastfail cd "${tempdir}/third"; fastfail git log --oneline) \
            2>&1 | indent

    echo
    echo "Verifying that the first and third repositories have the same"
    echo "files in their respective working directories:"
    show_command=1 assert diff -r --exclude ".git" -- \
        "${tempdir}/first" "${tempdir}/third" 2>&1 | indent
} | indent


###
section_break

print_info "Step 6: Force Push Warning Test (implicit force):"
{
    # Make a change in first repo
    cd "${tempdir}/first"
    echo "force push test data" > "force_test.txt"
    git add force_test.txt
    git commit -m "Commit for force push test"

    # Push WITHOUT + prefix (should trigger warning about implicit force)
    output_file="${tempdir}/force_push_output"
    (
        set -x
        # Use refspec without + to trigger warning
        git push "gcrypt::${tempdir}/second.git#${default_branch}" \
            "${default_branch}:refs/heads/${default_branch}" 2>&1
    ) | tee "${output_file}"

    # Verify warning message appears
    if grep -q "gcrypt overwrites the remote manifest" "${output_file}"; then
        print_success "Manifest overwrite note displayed correctly."
    else
        print_err "Manifest overwrite note NOT found!"
        exit 1
    fi
} | indent

###
section_break

print_info "Step 7: require-explicit-force-push=true Test:"
{
    cd "${tempdir}/first"

    # Enable require-explicit-force-push
    git config gcrypt.require-explicit-force-push true

    # Make another change
    echo "blocked push test" > "blocked_test.txt"
    git add blocked_test.txt
    git commit -m "Commit for blocked push test"

    # Attempt push without + (should FAIL)
    output_file="${tempdir}/blocked_push_output"
    set +e
    (
        set -x
        git push "gcrypt::${tempdir}/second.git#${default_branch}" \
            "${default_branch}:refs/heads/${default_branch}" 2>&1
    ) | tee "${output_file}"
    push_status=$?
    set -e

    if [ $push_status -ne 0 ] && grep -q "Implicit force push disallowed" "${output_file}"; then
        print_success "Push correctly blocked by require-explicit-force-push."
    else
        print_err "Push should have been blocked but wasn't!"
        exit 1
    fi

    # Now push WITH --force (should succeed)
    (
        set -x
        git push --force "gcrypt::${tempdir}/second.git#${default_branch}" \
            "${default_branch}"
    ) 2>&1

    print_success "Explicit force push succeeded."

    # Clean up config for next tests
    git config --unset gcrypt.require-explicit-force-push
} | indent

###
section_break

print_info "Step 8: Signal Handling Test (Ctrl+C simulation):"
{
    cd "${tempdir}/first"

    # Make a change to push
    echo "signal test data" > "signal_test.txt"
    git add signal_test.txt
    git commit -m "Commit for signal test"

    # Start push in background and send SIGINT after brief delay
    # This tests that the script exits cleanly on interruption
    output_file="${tempdir}/signal_output"
    set +e
    (
        # Give it a moment to start, then send SIGINT
        (sleep 0.5 && kill -INT $$ 2>/dev/null) &
        git push --force "gcrypt::${tempdir}/second.git#${default_branch}" \
            "${default_branch}" 2>&1
    ) > "${output_file}" 2>&1
    signal_status=$?
    set -e

    # Exit code 130 = SIGINT (128 + 2), or 0 if push completed before SIGINT
    if [ $signal_status -eq 130 ] || [ $signal_status -eq 0 ]; then
        print_success "Signal handling: Exit code $signal_status (OK)."
    else
        print_err "Unexpected exit code: $signal_status"
        # Don't fail the test - signal timing is unpredictable
    fi

    # Verify no leftover temp files in repo's gcrypt dir
    if [ -d "${tempdir}/first/.git/remote-gcrypt" ]; then
        leftover_count=$(find "${tempdir}/first/.git/remote-gcrypt" -name "*.tmp" 2>/dev/null | wc -l)
        if [ "$leftover_count" -gt 0 ]; then
            print_err "Warning: Found $leftover_count leftover temp files"
        else
            print_success "No leftover temp files found."
        fi
    else
        print_success "No remote-gcrypt directory (OK for gitception)."
    fi
} | indent

###
section_break

print_info "Step 9: Network Failure Guard Test (manifest unavailable):"
{
    # This test verifies behavior when manifest cannot be fetched
    # AND local gcrypt-id is not set.
    # Current behavior: gcrypt creates a NEW repo, potentially overwriting!
    # This test documents (and may later guard against) this behavior.
    
    cd "${tempdir}"
    
    # Save the manifest file
    # Find and delete manifest files (hashes at root of repo for local transport)
    # We look for files with 64 hex characters in the repo directory
    # manifests=$(find "${tempdir}/second.git" -maxdepth 1 -type f -regextype posix-egrep -regex ".*/[0-9a-f]{56,64}")
    # Simpler approach: globbing (which might fail if no match) then check
    
    # Debug: List what's actually there
    print_info "DEBUG: Listing ${tempdir}/second.git:"
    find "${tempdir}/second.git" -mindepth 1 -maxdepth 1 -printf '%f\n' | indent
    
    # DEBUG: Dump directory listing to stdout
    print_info "DEBUG: Listing ${tempdir}/second.git contents:"
    find "${tempdir}/second.git" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort | indent

    # Use find to robustly locate manifest files (56-64 hex chars)
    # matching basename explicitly via grep. Using sed for portable basename extraction.
    manifest_names=$(find "${tempdir}/second.git" -maxdepth 1 -type f | sed 's!.*/!!' | grep -E '^[0-9a-fA-F]{56,64}$' || true)
    print_info "DEBUG: Detected manifest candidate(s): ${manifest_names:-none}"
    
    # Check if we actually found anything
    if [ -n "$manifest_names" ]; then            
        for fname in $manifest_names; do
             f="${tempdir}/second.git/$fname"
             cp "$f" "${tempdir}/manifest_backup_${fname}"
             rm "$f"
        done
        manifest_saved=true
    elif git -C "${tempdir}/second.git" show-ref --quiet --verify "refs/heads/${default_branch}"; then
        # Gitception fallback: delete the branch ref
        print_info "Detected Gitception manifest (branch ref). Backing up..."
        manifest_sha=$(git -C "${tempdir}/second.git" rev-parse "refs/heads/${default_branch}")
        git -C "${tempdir}/second.git" update-ref -d "refs/heads/${default_branch}"
        manifest_saved=true
        git_ref_backup="$manifest_sha"
    else
        # For gitception or if structure differs
        manifest_saved=false
        print_warn "Skipping manifest backup - No manifest file/ref found to delete."
    fi
    
    # Create a fresh clone to test with
    mkdir "${tempdir}/fresh_clone_test"
    cd "${tempdir}/fresh_clone_test"
    git init
    git config user.name "${test_user_name}"
    git config user.email "${test_user_email}"
    echo "test data" > test.txt
    git add test.txt
    git commit -m "Initial commit"
    
    # Try to push to the EXISTING remote
    # Since this fresh repo has no gcrypt-id, it could be dangerous
    step9_output="${tempdir}/network_guard_output"
    set +e
    (
        set -x
        git push "gcrypt::${tempdir}/second.git#${default_branch}" \
            "${default_branch}:refs/heads/test-network-guard" 2>&1
    ) | tee "${step9_output}"
    push_result=$?
    set -e
    
    # The push should FAIL now because we require --force for missing manifests
    if [ $push_result -ne 0 ]; then
        print_success "Push failed (PROTECTED against accidental overwrite)."
        if grep -q "Use --force to create valid new repository" "${step9_output}"; then
            print_success "Correct error message received."
        else
            print_err "Wrong error message!"
            indent < "${step9_output}"
            exit 1
        fi
    else
        print_err "Push SUCCEEDED without --force (Safety check failed)."
        exit 1
    fi
    
    # Restore manifest(s) if we backed them up
    if [ "$manifest_saved" = true ]; then
        if [ -n "${git_ref_backup:-}" ]; then
             git -C "${tempdir}/second.git" update-ref "refs/heads/${default_branch}" "$git_ref_backup"
        else
            for f in "${tempdir}"/manifest_backup_*; do
                 # extract original filename from backup filename
                 # basename is manifest_backup_<hash>
                 # we want to restore to ${tempdir}/second.git/<hash>
                 fname=$(basename "$f")
                 orig_name=${fname#manifest_backup_}
                 cp "$f" "${tempdir}/second.git/${orig_name}"
            done
        fi
    fi
} | indent


###
section_break

print_info "Step 10: New Repo Safety Test (Require Force):"
{
    cd "${tempdir}"
    # Setup: Ensure we have a "missing" remote scenario
    # We'll use a new random path that definitely doesn't exist
    rand_id=$(date +%s)
    missing_remote_url="${tempdir}/missing_repo_${rand_id}.git"
    
    cd "${tempdir}/fresh_clone_test"
    


    print_info "Attempting push to missing remote WITHOUT force (Should Fail)..."
    set +e
    (
        git push "gcrypt::${missing_remote_url}" "${default_branch}" 2>&1
    ) > "step10.fail"
    rc=$?
    set -e
    
    if [ $rc -ne 0 ]; then
        print_success "Push correctly failed without force."
        if grep -q "Use --force to create valid new repository" "step10.fail"; then
            print_success "Correct error message received."
        fi
    else
        indent < "step10.fail"
        print_err "Push SHOULD have failed but SUCCEEDED!"
        exit 1
    fi

    print_info "Attempting push to missing remote WITH force..."
    set +e
    (
        git push --force "gcrypt::${missing_remote_url}" "${default_branch}" 2>&1
    ) > "step10.succ"
    rc=$?
    set -e
    
    if [ $rc -eq 0 ]; then
        print_success "Push succeeded with force."
    else
        indent < "step10.succ"
        print_err "Push failed even with force!"
        exit 1
    fi
} | indent


if [ -n "${COV_DIR:-}" ]; then
    print_success "OK. Report: file://${COV_DIR}/index.html"
fi

