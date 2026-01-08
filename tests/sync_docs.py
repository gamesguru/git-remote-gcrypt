#!/usr/bin/env python3
import os
import re
import sys


def extract_help_text(script_path):
    with open(script_path, "r") as f:
        content = f.read()

    match = re.search(r'HELP_TEXT="(.*?)"', content, re.DOTALL)
    if not match:
        print("Error: Could not find HELP_TEXT in git-remote-gcrypt", file=sys.stderr)
        sys.exit(1)
    return match.group(1)


def parse_commands(help_text):
    commands = []
    # Look for lines starting with lowercase words in the Options: or Git Protocol Commands sections
    lines = help_text.split("\n")
    capture = False
    for line in lines:
        line = line.strip()
        if line.startswith("Options:") or line.startswith("Git Protocol Commands"):
            capture = True
            continue
        if line.startswith("Environment Variables:"):
            capture = False
            continue

        if capture and line:
            # Match lines like "check [URL]      Description" or "capabilities     Description"
            match = re.match(r"^([a-z-]+)(\s+.*)?$", line)
            if match:
                cmd = match.group(1)
                if cmd not in ["help", "version"]:
                    commands.append(cmd)
    return sorted(list(set(commands)))


BASH_TEMPLATE = r'''# Bash completion for git-remote-gcrypt
# Install to: /etc/bash_completion.d/ or ~/.local/share/bash-completion/completions/

_git_remote_gcrypt() {{
	local cur prev opts commands
	COMPREPLY=()
	cur="${{COMP_WORDS[COMP_CWORD]}}"
	prev="${{COMP_WORDS[COMP_CWORD - 1]}}"
	opts="-h --help -v --version --check"
	commands="{commands}"

	# 1. First argument: complete commands and global options
	if [[ $COMP_CWORD -eq 1 ]]; then
		COMPREPLY=($(compgen -W "$commands $opts" -- "$cur"))
		if [[ "$cur" == gcrypt::* ]]; then
			COMPREPLY+=("$cur")
		fi
		return 0
	fi

	# 2. Handle subcommands
	case "${{COMP_WORDS[1]}}" in
		clean)
			local remotes=$(git remote -v 2>/dev/null | grep 'gcrypt::' | awk '{{print $1}}' | sort -u || :)
			COMPREPLY=($(compgen -W "-f --force -h --help $remotes" -- "$cur"))
			return 0
			;;
		check|--check)
			COMPREPLY=($(compgen -f -- "$cur"))
			return 0
			;;
		capabilities|fetch|list|push)
			COMPREPLY=($(compgen -W "-h --help" -- "$cur"))
			return 0
			;;
	esac

	# 3. Fallback (global flags if not in a known subcommand?)
	if [[ "$cur" == -* ]]; then
		COMPREPLY=($(compgen -W "$opts" -- "$cur"))
		return 0
	fi
}}

complete -F _git_remote_gcrypt git-remote-gcrypt
'''

ZSH_TEMPLATE = r'''#compdef git-remote-gcrypt
# Zsh completion for git-remote-gcrypt
# Install to: ~/.zsh/completions/ or /usr/share/zsh/site-functions/

_git_remote_gcrypt() {{
	local -a args
	args=(
		'(- *)'{{-h,--help}}'[show help message]'
		'(- *)'{{-v,--version}}'[show version information]'
		'--check[check if URL is a gcrypt repository]:URL:_files'
		'1:command:({commands})'
		'*::subcommand arguments:->args'
	)
	_arguments -s -S $args

	case $words[1] in
	clean)
		_arguments \
			'(-f --force)'{{-f,--force}}'[actually delete files]' \
			'*:gcrypt URL: _alternative "remotes:gcrypt remote:($(git remote -v 2>/dev/null | grep "gcrypt::" | awk "{{print \$1}}" | sort -u))" "files:file:_files"'
		;;
	check)
		_arguments \
			'1:gcrypt URL:_files'
		;;
	*)
		_arguments \
			'*:gcrypt URL:'
		;;
	esac
}}

_git_remote_gcrypt "$@"
'''

FISH_TEMPLATE = r'''# Fish completion for git-remote-gcrypt
# Install to: ~/.config/fish/completions/

complete -c git-remote-gcrypt -s h -l help -d 'Show help message'
complete -c git-remote-gcrypt -s v -l version -d 'Show version information'
complete -c git-remote-gcrypt -l check -d '(Legacy) Check if URL is a gcrypt repository' -r -F

# Subcommands
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from {not_sc_list}" -a 'check' -d 'Check if URL is a gcrypt repository'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from {not_sc_list}" -a 'clean' -d 'Scan/Clean unencrypted files from remote'
complete -c git-remote-gcrypt -n "__fish_seen_subcommand_from clean check" -a "(git remote -v 2>/dev/null | grep 'gcrypt::' | awk '{{print \$1}}' | sort -u)" -d 'Gcrypt Remote'

# Clean flags
complete -c git-remote-gcrypt -f -n "__fish_seen_subcommand_from {not_sc_list}" -s f -l force -d 'Actually delete files during clean'

# Git protocol commands
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from {not_sc_list}" -a 'capabilities' -d 'Show git remote helper capabilities'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from {not_sc_list}" -a 'list' -d 'List refs in remote repository'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from {not_sc_list}" -a 'push' -d 'Push refs to remote repository'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from {not_sc_list}" -a 'fetch' -d 'Fetch refs from remote repository'
'''

DETECT_SECTION = r'''Detecting gcrypt repos
======================

To detect if a git url is a gcrypt repo, use::

    git-remote-gcrypt check url

(Legacy syntax ``--check`` is also supported).

Exit status is 0'''

CLEAN_SECTION = r'''Cleaning gcrypt repos
=====================

To scan for unencrypted files in a remote gcrypt repo, use::

    git-remote-gcrypt clean [url|remote]

If no URL or remote is specified, ``git-remote-gcrypt`` will list all
available ``gcrypt::`` remotes.

By default, this command only performs a scan. To actually remove the
unencrypted files, you must use the ``--force`` (or ``-f``) flag::

    git-remote-gcrypt clean url --force

'''


def update_readme(path):
    if not os.path.exists(path):
        return
    with open(path, "r") as f:
        content = f.read()

    # robustly replace sections
    pattern1 = r"(Detecting gcrypt repos\n======================.*?Exit status is 0)"
    new_content = re.sub(pattern1, DETECT_SECTION, content, flags=re.DOTALL)
    
    pattern2 = r"(Cleaning gcrypt repos\n=====================.*?)(?=\nKnown issues)"
    new_content = re.sub(pattern2, CLEAN_SECTION, new_content, flags=re.DOTALL)
    
    if content != new_content:
        print(f"Updating README sections at: {path}")
        with open(path, "w") as f:
            f.write(new_content)
    else:
        print(f"README at {path} is up to date.")


def update_bash_completion(path, commands):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cmd_str = " ".join(commands)
    content = BASH_TEMPLATE.format(commands=cmd_str)
    with open(path, "w") as f:
        f.write(content)


def update_zsh_completion(path, commands):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cmd_str = " ".join(commands)
    content = ZSH_TEMPLATE.format(commands=cmd_str)
    with open(path, "w") as f:
        f.write(content)


def update_fish_completion(path, commands):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cmd_str = " ".join(commands)
    content = FISH_TEMPLATE.format(not_sc_list=cmd_str)
    with open(path, "w") as f:
        f.write(content)


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)
    script_path = os.path.join(root_dir, "git-remote-gcrypt")

    help_text = extract_help_text(script_path)
    commands = parse_commands(help_text)

    # We always want protocol commands in completions too
    comp_commands = sorted(
        list(set(commands + ["capabilities", "list", "push", "fetch"]))
    )

    print(f"Detected commands: {' '.join(comp_commands)}")
    
    bash_path = os.path.join(root_dir, "completions/bash/git-remote-gcrypt")
    print(f"Updating Bash completions at: {bash_path}")
    update_bash_completion(bash_path, comp_commands)

    zsh_path = os.path.join(root_dir, "completions/zsh/_git-remote-gcrypt")
    print(f"Updating Zsh completions at: {zsh_path}")
    update_zsh_completion(zsh_path, comp_commands)

    fish_path = os.path.join(root_dir, "completions/fish/git-remote-gcrypt.fish")
    print(f"Updating Fish completions at: {fish_path}")
    update_fish_completion(fish_path, comp_commands)
    
    readme_path = os.path.join(root_dir, "README.rst")
    update_readme(readme_path)

    print("Completions and Documentation updated.")


if __name__ == "__main__":
    main()
