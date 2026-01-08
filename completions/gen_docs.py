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


def update_readme(path, template_path):
    if not os.path.exists(template_path):
        print(f"Error: Template not found at {template_path}", file=sys.stderr)
        sys.exit(1)
        
    with open(template_path, "r") as f:
        template_content = f.read()

    # If the destination exists, check if it matches
    if os.path.exists(path):
        with open(path, "r") as f:
            content = f.read()
    else:
        content = ""

    if content != template_content:
        print(f"Updating README at: {path}")
        with open(path, "w") as f:
            f.write(template_content)
    else:
        print(f"README at {path} is up to date.")


def update_bash_completion(path, template_path, commands):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    
    with open(template_path, "r") as f:
        template = f.read()
        
    cmd_str = " ".join(commands)
    content = template.replace("{commands}", cmd_str)
    
    with open(path, "w") as f:
        f.write(content)


def update_zsh_completion(path, template_path, commands):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    
    with open(template_path, "r") as f:
        template = f.read()
        
    cmd_str = " ".join(commands)
    content = template.replace("{commands}", cmd_str)
    
    with open(path, "w") as f:
        f.write(content)


def update_fish_completion(path, template_path, commands):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    
    with open(template_path, "r") as f:
        template = f.read()
        
    cmd_str = " ".join(commands)
    content = template.replace("{not_sc_list}", cmd_str)
    
    with open(path, "w") as f:
        f.write(content)


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)
    script_path = os.path.join(root_dir, "git-remote-gcrypt")
    templates_dir = os.path.join(script_dir, "templates")

    help_text = extract_help_text(script_path)
    commands = parse_commands(help_text)

    # We always want protocol commands in completions too
    comp_commands = sorted(
        list(set(commands + ["capabilities", "list", "push", "fetch"]))
    )

    print(f"Detected commands: {' '.join(comp_commands)}")
    
    # Bash
    bash_path = os.path.join(root_dir, "completions/bash/git-remote-gcrypt")
    bash_tmpl = os.path.join(templates_dir, "bash.in")
    print(f"Updating Bash completions at: {bash_path}")
    update_bash_completion(bash_path, bash_tmpl, comp_commands)

    # Zsh
    zsh_path = os.path.join(root_dir, "completions/zsh/_git-remote-gcrypt")
    zsh_tmpl = os.path.join(templates_dir, "zsh.in")
    print(f"Updating Zsh completions at: {zsh_path}")
    update_zsh_completion(zsh_path, zsh_tmpl, comp_commands)

    # Fish
    fish_path = os.path.join(root_dir, "completions/fish/git-remote-gcrypt.fish")
    fish_tmpl = os.path.join(templates_dir, "fish.in")
    print(f"Updating Fish completions at: {fish_path}")
    update_fish_completion(fish_path, fish_tmpl, comp_commands)
    
    readme_path = os.path.join(root_dir, "README.rst")
    readme_tmpl = os.path.join(templates_dir, "README.rst.in")
    update_readme(readme_path, readme_tmpl)

    print("Completions and Documentation updated.")


if __name__ == "__main__":
    main()
