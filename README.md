# breathe

Breathe life into a fresh Mac.

## Prerequisites

Install these by hand:

- [1Password for Mac](https://downloads.1password.com/mac/1Password.zip)
- [Tailscale](https://apps.apple.com/us/app/tailscale/id1475387142?mt=12)
- [Screens 5](https://apps.apple.com/us/app/screens-5-vnc-remote-desktop/id1663047912)
- [Google Chrome](https://www.google.com/chrome/)
- [Codex](https://chatgpt.com/codex/)

## Run it

```sh
/bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/andrewculver/breathe/main/breathe.sh)"
```

Follow the prompts. It names your Mac, installs Claude Code, Homebrew, the
GitHub CLI, and Codex CLI, signs you in to GitHub, sets up your SSH key, and
clones your `zshrc` dotfiles.
