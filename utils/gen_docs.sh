#!/bin/sh
set -e

# gen_docs.sh
# Generates documentation and shell completions from git-remote-gcrypt source.
# Strictly POSIX sh compliant.

SCRIPT_KEY="HELP_TEXT"
SRC="git-remote-gcrypt"
README_TMPL="completions/templates/README.rst.in"
README_OUT="README.rst"
BASH_TMPL="completions/templates/bash.in"
BASH_OUT="completions/bash/git-remote-gcrypt"
ZSH_TMPL="completions/templates/zsh.in"
ZSH_OUT="completions/zsh/_git-remote-gcrypt"
FISH_TMPL="completions/templates/fish.in"
FISH_OUT="completions/fish/git-remote-gcrypt.fish"

# Ensure we're in the project root
if [ ! -f "$SRC" ]; then
	echo "Error: Must be run from project root" >&2
	exit 1
fi

# Extract HELP_TEXT variable content
# Using sed to capture lines between double quotes of HELP_TEXT="..."
# Assumes HELP_TEXT="..." is a single block.
RAW_HELP=$(sed -n "/^$SCRIPT_KEY=\"/,/\"$/p" "$SRC" | sed "s/^$SCRIPT_KEY=\"//;s/\"$//")

# 1. Prepare {commands_help} for README (Indented for RST)
# We want the Options and Git Protocol Commands sections
COMMANDS_HELP=$(echo "$RAW_HELP" | sed -n '/^Options:/,$p' | sed 's/^/    /')

# 2. Parse Commands and Flags for Completions
# Extract command names (first word after 2 spaces)
COMMANDS_LIST=$(echo "$RAW_HELP" | awk '/^  [a-z]+ / {print $1}' | grep -vE "^(help|version)$" | sort | tr '\n' ' ' | sed 's/ $//')

# Extract clean flags
# Text: "    clean -f, --force    Actually delete files..."
# We want: "-f --force -i --init" for Bash
CLEAN_FLAGS_RAW=$(echo "$RAW_HELP" | grep "^    clean -" | awk -F'  ' '{print $2}' | sed 's/,//g')
CLEAN_FLAGS_BASH=$(echo "$CLEAN_FLAGS_RAW" | tr '\n' ' ' | sed 's/ $//')

# For Zsh: we want simple list for now as per plan, user asked for dynamic but safe.
# Constructing a simple list of flags requires parsing.
# The previous python script just injected them.
CLEAN_FLAGS_ZSH=""
# We'll just provide the flags as a list for _arguments
# ZSH format roughly: '(-f --force)'{-f,--force}'[desc]'
# Only generate if there are actual flags
COMMA_FLAGS=$(echo "$CLEAN_FLAGS_BASH" | tr ' ' ',')
if [ -n "$CLEAN_FLAGS_BASH" ]; then
	CLEAN_FLAGS_ZSH="'(${CLEAN_FLAGS_BASH})' {${COMMA_FLAGS}} '[flag]'"
else
	CLEAN_FLAGS_ZSH=""
fi

# For Fish
# We need to turn "-f, --force" into:
# complete ... -s f -l force ...
CLEAN_FLAGS_FISH=""
# Use a loop over the raw lines
IFS="
"
for line in $CLEAN_FLAGS_RAW; do
	# line is like "-f --force"
	short=$(echo "$line" | awk '{print $1}' | sed 's/-//')
	long=$(echo "$line" | awk '{print $2}' | sed 's/--//')
	# Escape quotes if needed (none usually)
	CLEAN_FLAGS_FISH="${CLEAN_FLAGS_FISH}complete -c git-remote-gcrypt -f -n \"__fish_seen_subcommand_from clean\" -s $short -l $long -d 'Flag';\n"
done
unset IFS

# 3. Generate README
echo "Generating $README_OUT..."
sed "s/{commands_help}/$(echo "$COMMANDS_HELP" | sed 's/[\/&]/\\&/g' | awk '{printf "%s\\n", $0}')/" "$README_TMPL" >"$README_OUT"

# 4. Generate Bash
echo "Generating Bash completions..."
sed "s/{commands}/$COMMANDS_LIST/; s/{clean_flags_bash}/$CLEAN_FLAGS_BASH/" "$BASH_TMPL" >"$BASH_OUT"

# 5. Generate Zsh
echo "Generating Zsh completions..."
# Zsh substitution is tricky with the complex string.
# We'll stick to replacing {commands} and {clean_flags_zsh}
# Need to escape special chars for sed
# safe_cmds removed as unused
# For clean_flags_zsh, since it contains quotes and braces, we need care.
# We'll read the template line by line? No, sed is standard.
# We use a temp file for the replacement string to avoid sed escaping hell for large blocks?
# Or just keep it simple.
sed "s/{commands}/$COMMANDS_LIST/" "$ZSH_TMPL" \
	| sed "s|{clean_flags_zsh}|$CLEAN_FLAGS_ZSH|" >"$ZSH_OUT"

# 6. Generate Fish
echo "Generating Fish completions..."
# Fish needs {not_sc_list} which matches {commands} (space separated)
sed "s/{not_sc_list}/$COMMANDS_LIST/g" "$FISH_TMPL" \
	|
	# Multi-line replacement in sed is hard. Use awk?
	# Or just injecting the string with escaped newlines.
	sed "s|{clean_flags_fish}|$CLEAN_FLAGS_FISH|" >"$FISH_OUT"

echo "Done."
