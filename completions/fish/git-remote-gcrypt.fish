# Fish completion for git-remote-gcrypt
# Install to: ~/.config/fish/completions/

complete -c git-remote-gcrypt -s h -l help -d 'Show help message'
complete -c git-remote-gcrypt -s v -l version -d 'Show version information'
complete -c git-remote-gcrypt -l check -d '(Legacy) Check if URL is a gcrypt repository' -r -F

# Subcommands
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from capabilities list push fetch check clean" -a 'check' -d 'Check if URL is a gcrypt repository'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from capabilities list push fetch check clean" -a 'clean' -d 'Scan/Clean unencrypted files from remote'

# Clean flags
complete -c git-remote-gcrypt -f -n "__fish_seen_subcommand_from clean" -s f -l force -d 'Actually delete files during clean'

# Git protocol commands
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from capabilities list push fetch check clean" -a 'capabilities' -d 'Show git remote helper capabilities'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from capabilities list push fetch check clean" -a 'list' -d 'List refs in remote repository'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from capabilities list push fetch check clean" -a 'push' -d 'Push refs to remote repository'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from capabilities list push fetch check clean" -a 'fetch' -d 'Fetch refs from remote repository'
