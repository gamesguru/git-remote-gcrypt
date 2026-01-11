
Saturday, 1/10/26

Q: Does the manifest

The issue here is the second one is a valid, encrypted remote.
The tool is doing too much work and providing dumb results, at times, by trying to be fancy and smart.

.. code-block:: shell

    shane@coffeelake:~/repos/git-remote-gcrypt$ cd -
    /home/shane
    direnv: loading ~/.envrc
    direnv: export +RIPGREP_CONFIG_PATH +VIRTUAL_ENV +VIRTUAL_ENV_PROMPT ~PATH
    shane@coffeelake:~$ git remote update
    Fetching github
    gcrypt: git-remote-gcrypt version 1.5-10-ge258c9e (deb running on arch)
    gcrypt: ERROR: Remote repository contains unencrypted or unknown files!
    gcrypt: To protect your privacy, git-remote-gcrypt will NOT push to this remote.
    gcrypt: Found unexpected files: .bash_aliases .bash_exports .bash_history.coffeelake
    gcrypt: To see unencrypted files, use: git-remote-gcrypt clean git@github.com:gamesguru/shane.git
    gcrypt: To fix and remove these files, use: git-remote-gcrypt clean --force git@github.com:gamesguru/shane.git
    error: could not fetch github

    # This shouldn't warn, it's a valid encrypted remote!
    Fetching origin
    gcrypt: git-remote-gcrypt version 1.5-10-ge258c9e (deb running on arch)
    gcrypt: ERROR: Remote repository is not empty!
    gcrypt: To protect your privacy, git-remote-gcrypt will NOT push to this remote
    gcrypt: unless you force it or clean it.
    gcrypt: Found files: 91bd0c092128cf2e60e1a608c31e92caf1f9c1595f83f2890ef17c0e4881aa0a b5cb4d58020a8b6376ce627e3c4d2404a1e5bb772bd20eecedbe3ff9212d9aae ...
    gcrypt: To see files: git-remote-gcrypt clean rsync://git@dev:repos/home.shane.git
    gcrypt: To init anyway (DANGEROUS if not empty): git push --force ...
    gcrypt: OR set gcrypt.allow-unencrypted-remote to true.
    error: could not fetch origin
