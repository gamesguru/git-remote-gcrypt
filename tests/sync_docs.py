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


def update_bash_completion(path, commands):
    if not os.path.exists(path):
        return
    with open(path, "r") as f:
        content = f.read()
    cmd_str = " ".join(commands)
    new_content = re.sub(r'commands="[^"]+"', f'commands="{cmd_str}"', content)
    with open(path, "w") as f:
        f.write(new_content)


def update_zsh_completion(path, commands):
    if not os.path.exists(path):
        return
    with open(path, "r") as f:
        content = f.read()
    cmd_str = " ".join(commands)
    # Match 1:command:(capabilities list push fetch check clean)
    new_content = re.sub(r"1:command:\([^)]+\)", f"1:command:({cmd_str})", content)
    with open(path, "w") as f:
        f.write(new_content)


def update_fish_completion(path, commands):
    if not os.path.exists(path):
        return
    with open(path, "r") as f:
        content = f.read()
    # Replace the list in "not __fish_seen_subcommand_from ..."
    cmd_str = " ".join(commands)
    new_content = re.sub(
        r'not __fish_seen_subcommand_from [^"]+',
        f"not __fish_seen_subcommand_from {cmd_str}",
        content,
    )
    with open(path, "w") as f:
        f.write(new_content)


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

    update_bash_completion(
        os.path.join(root_dir, "completions/bash/git-remote-gcrypt"), comp_commands
    )
    update_zsh_completion(
        os.path.join(root_dir, "completions/zsh/_git-remote-gcrypt"), comp_commands
    )
    update_fish_completion(
        os.path.join(root_dir, "completions/fish/git-remote-gcrypt.fish"), comp_commands
    )

    print("Completions updated.")


if __name__ == "__main__":
    main()
