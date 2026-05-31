# breathe

> Breathe life into a fresh Mac.

`breathe` is a single zsh script you run on a brand-new Mac to kick off the
installation of your most-wanted tools — in the spirit of the Homebrew
installer, but it doesn't stop at one shell. Some steps (like installing
Homebrew) change your shell environment and only take effect in a *new* shell.
So after those steps, breathe opens a fresh Terminal window via AppleScript,
re-runs itself, detects the completed step, and carries on. It keeps going
until everything's set up.

## Prerequisites

A few GUI apps are best installed by hand before (or alongside) running breathe:

- **1Password for Mac** — [direct download](https://downloads.1password.com/mac/1Password.zip)
  (1Password 8 ships as a `.zip`, not a `.dmg`; see the
  [downloads page](https://1password.com/downloads/mac))
- **Tailscale** — [Mac App Store](https://apps.apple.com/us/app/tailscale/id1475387142?mt=12)
- **Screens 5** — [Mac App Store](https://apps.apple.com/us/app/screens-5-vnc-remote-desktop/id1663047912)

## Run it

Paste this into Terminal:

```sh
/bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/andrewculver/breathe/main/breathe.sh)"
```

That's it. Follow the prompts — you'll be asked for your macOS password
(for Homebrew) and walked through signing in to GitHub.

## What it does

It's a state machine. Each run detects what's already done and advances to the
next step:

1. **Homebrew** — installs it, writes `eval "$(brew shellenv)"` into your
   `~/.zshrc`, then spawns a fresh shell (so `brew` is on `PATH`) and re-runs.
2. **GitHub CLI** — `brew install gh`.
3. **GitHub auth + SSH** — `gh auth login` over SSH, generating and uploading
   an SSH key for you.
4. **ssh-agent** — loads the key into `ssh-agent` and the macOS keychain, and
   writes an `~/.ssh/config` entry (`AddKeysToAgent`/`UseKeychain`) so it's
   available in every future shell — `gh` uploads the key but doesn't do this.
5. **Your dotfiles** — clones `your-username/zshrc` into `~/.zsh` and sources
   its `all.sh` from `~/.zshrc`.

Every step is idempotent: re-running breathe at any point is safe. Config it
writes into `~/.zshrc` is wrapped in guarded `# >>> breathe:... >>>` blocks, so
it's added once and easy to find.

## How the shell-spawning works

When a step changes the environment, breathe:

1. Writes the needed config into `~/.zshrc`.
2. Uses `osascript` to tell Terminal to `do script "zsh ~/.breathe/breathe.sh"` —
   opening a new window. That window is an interactive shell, so it sources the
   updated `~/.zshrc` first, then runs breathe again.
3. Exits. The new window picks up where it left off.

A copy of the script is cached at `~/.breathe/breathe.sh` so respawned shells
always have something local to run.

## Configuration

The script reads two optional environment variables:

| Variable       | Default                             | Purpose                                  |
| -------------- | ----------------------------------- | ---------------------------------------- |
| `BREATHE_URL`  | this repo's raw `breathe.sh`        | Where respawned shells fetch breathe from |
| `BREATHE_HOME` | `~/.breathe`                        | Where the cached copy lives              |

If you fork this, update the `andrewculver/breathe` URLs in `breathe.sh` and in
the curl command above to point at your fork, and make sure you have a
`your-username/zshrc` repo with an `all.sh` entrypoint.

## Requirements

- macOS (the AppleScript respawn uses the Terminal app)
- An internet connection
- A GitHub account with a `zshrc` repo
