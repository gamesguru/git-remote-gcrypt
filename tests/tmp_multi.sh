#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-2.0-or-later
set -efuC -o pipefail
shopt -s inherit_errexit

# Settings
num_commits=5
files_per_commit=3
random_source="/dev/urandom"
random_data_per_file=1024 # Reduced size for faster testing (1KB)
default_branch="main"
test_user_name="git-remote-gcrypt"
test_user_email="git-remote-gcrypt@example.com"
pack_size_limit="12m"

readonly num_commits files_per_commit random_source random_data_per_file \
    default_branch test_user_name test_user_email pack_size_limit

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
    (set +e; [[ -n ${show_command:-} ]] && set -x; "${@}")
    local -r status=${?}
    { [[ ${status} -eq 0 ]] && echo "Verification succeeded.";} || \
        echo "Verification failed."
    return "${status}"
}

fastfail() {
    "$@" || kill -- "-$$"
}
# ----------------------------------------------------

umask 077
tempdir=$(mktemp -d)
readonly tempdir
trap "rm -Rf -- '${tempdir}'" EXIT

# Setup PATH to use local git-remote-gcrypt
PATH=$(git rev-parse --show-toplevel):${PATH}
readonly PATH
export PATH

# Clean GIT environment
git_env=$(env | sed -n 's/^\(GIT_[^=]*\)=.*$/\1/p')
IFS=$'\n' unset ${git_env}

# GPG Setup
export GNUPGHOME="${tempdir}/gpg"
mkdir "${GNUPGHOME}"
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
total_files=$(( num_commits * files_per_commit ))
random_data_size=$(( total_files * random_data_per_file ))
random_data_file="${tempdir}/data"
head -c "${random_data_size}" "${random_source}" > "${random_data_file}"

###
section_break

echo "Step 1: Creating multiple GPG keys for participants..."
num_keys=3 # We only need 3 keys to prove multikey (2 participants + 1 outsider)
key_fps=()
(
    set -x
    for ((i = 0; i < num_keys; i++)); do
        gpg --batch --passphrase "" --quick-generate-key \
            "${test_user_name}${i} <${test_user_email}${i}>"
    done
) 2>&1 | indent

# Capture fingerprints
key_fps=($(gpg --list-keys --with-colons | grep "^fpr" | cut -d: -f10))
echo "Generated keys: ${key_fps[@]}" | indent

###
section_break

echo "Step 2: Creating source repository..."
{
    git init -- "${tempdir}/first"
    cd "${tempdir}/first"
    for ((i = 0; i < num_commits; ++i)); do
        for ((j = 0; j < files_per_commit; ++j)); do
            file_index=$(( i * files_per_commit + j ))
            random_data_index=$(( file_index * random_data_per_file ))
            head -c "${random_data_per_file}" > "$(( file_index )).data" < \
                <(tail -c +"${random_data_index}" "${random_data_file}" || :)
        done
        git add .
        git commit -q -m "Commit #${i}"
    done
    git log --format=oneline | indent
} | indent

###
section_break

echo "Step 3: Creating bare remote..."
git init --bare -- "${tempdir}/second.git" | indent

###
section_break

echo "Step 4: Pushing with MULTIPLE participants [Key 0 and Key 1]..."
{
    (
        set -x
        cd "${tempdir}/first"
        # CRITICAL FIX: Add multiple space-separated participants
        git config gcrypt.participants "${key_fps[0]} ${key_fps[1]}"
        git push -f "gcrypt::${tempdir}/second.git#${default_branch}" "${default_branch}"
    ) 2>&1
} | indent

###
section_break

echo "Step 5: Unhappy Path - Test clone with NO matching keys..."
{
    original_gnupghome="${GNUPGHOME}"
    export GNUPGHOME="${tempdir}/gpg-empty"
    mkdir "${GNUPGHOME}"

    # We expect this to FAIL
    (
        set +e
        git clone -b "${default_branch}" "gcrypt::${tempdir}/second.git#${default_branch}" -- "${tempdir}/fail_test"
        if [ $? -eq 0 ]; then
             echo "ERROR: Clone succeeded unexpectedly with empty keyring!"
             exit 1
        fi
    ) 2>&1 | indent

    echo "Clone failed as expected." | indent
    export GNUPGHOME="${original_gnupghome}"
}

###
section_break

echo "Step 6: Happy Path - Clone using valid keyring..."
{
    (
        set -x
        git clone -b "${default_branch}" "gcrypt::${tempdir}/second.git#${default_branch}" -- "${tempdir}/third"
    ) 2>&1

    echo "Verifying content match..."
    assert diff -r --exclude ".git" -- "${tempdir}/first" "${tempdir}/third" 2>&1 | indent
} | indent
