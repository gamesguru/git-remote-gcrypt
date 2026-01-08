# Fish completion for git-remote-gcrypt
# Install to: ~/.config/fish/completions/

complete -c git-remote-gcrypt -s h -l help -d 'Show help message'
complete -c git-remote-gcrypt -s v -l version -d 'Show version information'
complete -c git-remote-gcrypt -l check -d '(Legacy) Check if URL is a gcrypt repository' -r -F

# Subcommands
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from capabilities check clean fetch list push" -a 'check' -d 'Check if URL is a gcrypt repository'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from capabilities check clean fetch list push" -a 'clean' -d 'Scan/Clean unencrypted files from remote'
complete -c git-remote-gcrypt -n "__fish_seen_subcommand_from clean check" -a "(git remote -v 2>/dev/null | grep 'gcrypt::' | awk '{print \$1}' | sort -u)" -d 'Gcrypt Remote'

# Clean flags
complete -c git-remote-gcrypt -f -n "__fish_seen_subcommand_from capabilities check clean fetch list push" -s f -l force -d 'Actually delete files during clean'

# Git protocol commands
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from capabilities check clean fetch list push" -a 'capabilities' -d 'Show git remote helper capabilities'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from capabilities check clean fetch list push" -a 'list' -d 'List refs in remote repository'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from capabilities check clean fetch list push" -a 'push' -d 'Push refs to remote repository'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from capabilities check clean fetch list push" -a 'fetch' -d 'Fetch refs from remote repository'
