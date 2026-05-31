#!/usr/bin/env zsh
#
# breathe — breathe life into a fresh Mac.
#
# A self-restarting bootstrap script. Each run inspects the machine, figures
# out the next step, and performs it. Steps that change the shell environment
# (e.g. installing Homebrew, which alters $PATH) write their config into
# ~/.zshrc and then spawn a *brand new* Terminal window via AppleScript. That
# new window sources the freshly-updated ~/.zshrc and re-runs breathe, which
# detects the completed step and moves on. Rinse, repeat, breathe.
#
# Run it with:
#   /bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/andrewculver/breathe/main/breathe.sh)"
#
set -u

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

# Where breathe lives on disk once bootstrapped. Respawned shells run this copy.
BREATHE_URL="${BREATHE_URL:-https://raw.githubusercontent.com/andrewculver/breathe/main/breathe.sh}"
BREATHE_HOME="${BREATHE_HOME:-$HOME/.breathe}"
BREATHE_BIN="$BREATHE_HOME/breathe.sh"

ZSHRC="$HOME/.zshrc"
SSH_DIR="$HOME/.ssh"
LOCAL_BIN="$HOME/.local/bin"

# Your personal zsh config repo, cloned from <github-username>/zshrc.
DOTFILES_REPO="zshrc"
DOTFILES_DIR="$HOME/.zsh"
DOTFILES_ENTRY="all.sh"

# ----------------------------------------------------------------------------
# Pretty output
# ----------------------------------------------------------------------------

if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  C_BLUE=$'\e[34m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi

log()   { print -- "${C_BLUE}${C_BOLD}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
info()  { print -- "    ${C_DIM}$*${C_RESET}"; }
ok()    { print -- "${C_GREEN}${C_BOLD} ✔${C_RESET} $*"; }
warn()  { print -- "${C_YELLOW}${C_BOLD} !${C_RESET} $*" >&2; }
die()   { print -- "${C_RED}${C_BOLD} ✘${C_RESET} $*" >&2; exit 1; }

banner() {
  print -- ""
  print -- "${C_BOLD}${C_BLUE}    ┌─────────────────────────────┐${C_RESET}"
  print -- "${C_BOLD}${C_BLUE}    │  breathe · fresh mac setup  │${C_RESET}"
  print -- "${C_BOLD}${C_BLUE}    └─────────────────────────────┘${C_RESET}"
  print -- ""
}

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

# Prompt for a value, showing the current/default in brackets. Reads from the
# terminal (not stdin) so it works even under `curl | zsh`. Empty input keeps
# the default.
#   ask <varname> <prompt> <default>
ask() {
  local __var="$1" __prompt="$2" __default="$3" __reply
  if [[ -n "$__default" ]]; then
    print -n -- "    ${C_BOLD}${__prompt}${C_RESET} [${C_DIM}${__default}${C_RESET}]: "
  else
    print -n -- "    ${C_BOLD}${__prompt}${C_RESET}: "
  fi
  IFS= read -r __reply </dev/tty 2>/dev/null || __reply=""
  [[ -z "$__reply" ]] && __reply="$__default"
  typeset -g "${__var}=${__reply}"
}

# The private key to treat as primary for github.com. Prefer modern key types,
# else fall back to the first private key that has a .pub sibling.
primary_ssh_key() {
  local k pub
  for k in "$SSH_DIR/id_ed25519" "$SSH_DIR/id_ecdsa" "$SSH_DIR/id_rsa"; do
    [[ -f "$k" ]] && { print -- "$k"; return 0; }
  done
  for pub in "$SSH_DIR"/*.pub(N); do
    k="${pub%.pub}"
    [[ -f "$k" ]] && { print -- "$k"; return 0; }
  done
}

# Homebrew's install prefix, by inspecting disk (works before brew is on PATH).
brew_prefix() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    print -- "/opt/homebrew"
  elif [[ -x /usr/local/bin/brew ]]; then
    print -- "/usr/local"
  fi
}

# Append a guarded block to ~/.zshrc, idempotently. Re-running is a no-op once
# the block's marker is present.
#   zshrc_block <name> <line> [<line> ...]
zshrc_block() {
  local name="$1"; shift
  local start="# >>> breathe:${name} >>>"
  local end="# <<< breathe:${name} <<<"

  touch "$ZSHRC"
  if grep -qF -- "$start" "$ZSHRC"; then
    return 0
  fi

  {
    print -- ""
    print -- "$start"
    local line
    for line in "$@"; do
      print -- "$line"
    done
    print -- "$end"
  } >> "$ZSHRC"
  ok "Added breathe:${name} block to ~/.zshrc"
}

# Re-open in a fresh Terminal window and continue. The new window is an
# interactive shell, so it sources ~/.zshrc (picking up any env we just wrote)
# before running breathe again.
spawn_new_shell() {
  info "(this window can be closed)"
  osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "Terminal"
  activate
  do script "zsh '$BREATHE_BIN' $*"
end tell
APPLESCRIPT
}

# Make sure a local copy of breathe exists on disk, then point this process at
# it. When run via \`curl | zsh\` there is no source file to copy, so we fetch a
# fresh copy from BREATHE_URL. Respawned shells already run BREATHE_BIN directly.
ensure_local() {
  mkdir -p "$BREATHE_HOME"
  if [[ "${0:A}" != "${BREATHE_BIN:A}" ]]; then
    if ! curl -fsSL "$BREATHE_URL" -o "$BREATHE_BIN" 2>/dev/null; then
      warn "Couldn't download breathe from $BREATHE_URL — respawns may not work."
      warn "Set BREATHE_URL to your repo's raw breathe.sh URL."
    fi
    chmod +x "$BREATHE_BIN" 2>/dev/null
  fi
}

# ----------------------------------------------------------------------------
# Steps
# ----------------------------------------------------------------------------

step_names() {
  log "Name your Mac"

  local cur_computer cur_local cur_host
  cur_computer="$(scutil --get ComputerName 2>/dev/null)"
  cur_local="$(scutil --get LocalHostName 2>/dev/null)"
  cur_host="$(scutil --get HostName 2>/dev/null)"
  [[ -n "$cur_host" ]] || cur_host="$cur_local"

  local computer local_host host
  ask computer   "Computer name (Finder & Sharing)"     "$cur_computer"
  ask local_host "Bonjour name (.local)"                "$cur_local"
  ask host       "Hostname"                             "$cur_host"

  # Bonjour / local hostname allows only letters, digits, and hyphens.
  local_host="${local_host// /-}"

  # Only the names that actually changed need setting — skip sudo entirely
  # (and the password prompt) if nothing changed.
  local -a changes
  [[ -n "$computer"   && "$computer"   != "$cur_computer" ]] && changes+=("ComputerName=$computer")
  [[ -n "$local_host" && "$local_host" != "$cur_local"    ]] && changes+=("LocalHostName=$local_host")
  [[ -n "$host"       && "$host"       != "$cur_host"     ]] && changes+=("HostName=$host")

  if (( ${#changes} == 0 )); then
    ok "Names unchanged."
  else
    info "Applying names (you may be asked for your password)…"
    local change
    for change in "${changes[@]}"; do
      sudo scutil --set "${change%%=*}" "${change#*=}"
    done
    ok "Named your Mac."
  fi
}

step_preferences() {
  log "Setting macOS preferences"

  # Hide icons on the desktop.
  defaults write com.apple.finder CreateDesktop false; killall Finder 2>/dev/null

  ok "Preferences set."
}

step_claude_code() {
  if have claude || [[ -x "$LOCAL_BIN/claude" ]]; then
    ok "Claude Code is installed"
  else
    log "Installing Claude Code"
    curl -fsSL https://claude.ai/install.sh | bash || die "Claude Code installation failed."
    ok "Claude Code installed."
  fi

  # Put ~/.local/bin on PATH for future shells…
  zshrc_block "claude" "export PATH=\"\$HOME/.local/bin:\$PATH\""
  # …and for the rest of this run, so `claude` is usable immediately.
  [[ ":$PATH:" == *":$LOCAL_BIN:"* ]] || export PATH="$LOCAL_BIN:$PATH"
}

step_homebrew() {
  if [[ -n "$(brew_prefix)" ]]; then
    # Already installed — just make sure it's on PATH for this process.
    have brew || eval "$("$(brew_prefix)/bin/brew" shellenv)"
    ok "Homebrew is installed"
    return 0
  fi

  log "Installing Homebrew"
  info "You may be asked for your macOS password and to press RETURN."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || die "Homebrew installation failed."

  local prefix; prefix="$(brew_prefix)"
  [[ -n "$prefix" ]] || die "Homebrew installed but brew binary not found."

  # Teach future shells where brew is.
  zshrc_block "homebrew" "eval \"\$(${prefix}/bin/brew shellenv)\""

  ok "Homebrew installed."
  # PATH won't update in this shell — hand off to a fresh one.
  log "Opening a fresh shell to continue…"
  spawn_new_shell
  exit 0
}

step_github_cli() {
  if have gh; then
    ok "GitHub CLI is installed"
    return 0
  fi
  log "Installing GitHub CLI"
  brew install gh || die "Failed to install gh."
  ok "GitHub CLI installed."
}

step_codex_cli() {
  if have codex; then
    ok "Codex CLI is installed"
    return 0
  fi
  log "Installing Codex CLI"
  brew install codex || die "Failed to install codex."
  ok "Codex CLI installed."
}

step_dock() {
  log "Tidying the Dock"

  # dockutil makes Dock edits painless. It needs Homebrew, so this step runs
  # after step_homebrew.
  if ! have dockutil; then
    info "Installing dockutil…"
    brew install dockutil >/dev/null 2>&1 \
      || { warn "Couldn't install dockutil — skipping Dock setup."; return 0; }
  fi

  # Default Apple apps we'd rather not clutter a fresh Dock with. Names are the
  # Dock labels; --remove is a no-op when the item is already gone.
  local -a remove=(
    Messages Mail Maps Photos FaceTime Calendar Contacts Reminders
    Notes Freeform Games TV Music Podcasts News "App Store" "System Settings"
    "iPhone Mirroring"
  )
  local name
  for name in "${remove[@]}"; do
    dockutil --remove "$name" --no-restart >/dev/null 2>&1
  done

  # Apps we *do* want — added only if installed and not already in the Dock.
  local -a add=(
    "/Applications/Tailscale.app"
    "/System/Applications/Utilities/Terminal.app"
    "/Applications/Codex.app"
  )
  local app label
  for app in "${add[@]}"; do
    label="${app:t:r}"
    if [[ ! -d "$app" ]]; then
      info "Skipping ${label} (not installed)"
      continue
    fi
    # --replacing pins the app to the persistent section, and makes re-runs a
    # no-op instead of stacking duplicates. (A plain --add would skip apps that
    # merely *appear* in the Dock's recent-apps section while running.)
    dockutil --add "$app" --replacing "$label" --no-restart >/dev/null 2>&1
  done

  # Drop the "recent applications" section (and its dividers) — running apps
  # that aren't pinned would otherwise show up there as duplicates.
  defaults write com.apple.dock show-recents -bool false

  killall Dock 2>/dev/null
  ok "Dock tidied."
}

step_github_auth() {
  if gh auth status >/dev/null 2>&1; then
    ok "Authenticated with GitHub as $(gh api user --jq .login 2>/dev/null)"
    return 0
  fi
  log "Signing you in to GitHub"
  info "Pick ${C_BOLD}SSH${C_RESET}${C_DIM} as the protocol and let gh generate & upload a key."
  gh auth login --hostname github.com --git-protocol ssh \
    || die "GitHub authentication did not complete."
  gh auth status >/dev/null 2>&1 || die "Still not authenticated with GitHub."
  ok "Signed in to GitHub."
}

step_ssh_agent() {
  local key; key="$(primary_ssh_key)"
  if [[ -z "$key" ]]; then
    warn "No SSH private key found in $SSH_DIR — skipping ssh-agent setup."
    return 0
  fi

  log "Loading your SSH key into ssh-agent"

  mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"

  # Persist the keychain-backed agent config so the key is available in every
  # future shell, not just this one. gh uploads the key to GitHub but doesn't
  # do this part.
  local cfg="$SSH_DIR/config"
  touch "$cfg"; chmod 600 "$cfg"
  if ! grep -qiE '^[[:space:]]*Host[[:space:]]+github\.com([[:space:]]|$)' "$cfg"; then
    {
      print -- ""
      print -- "# >>> breathe:ssh >>>"
      print -- "Host github.com"
      print -- "  AddKeysToAgent yes"
      print -- "  UseKeychain yes"
      print -- "  IdentityFile $key"
      print -- "# <<< breathe:ssh <<<"
    } >> "$cfg"
    ok "Wrote github.com SSH config."
  fi

  # Load every key that has a public counterpart into the running agent,
  # storing any passphrase in the macOS keychain (you'll be prompted once).
  local pub k
  for pub in "$SSH_DIR"/*.pub(N); do
    k="${pub%.pub}"
    [[ -f "$k" ]] || continue
    if ssh-add --apple-use-keychain "$k" 2>/dev/null; then
      ok "Added ${k:t} to ssh-agent (saved to keychain)"
    elif ssh-add "$k"; then
      ok "Added ${k:t} to ssh-agent"
    else
      warn "Couldn't add ${k:t} to ssh-agent."
    fi
  done
}

step_dotfiles() {
  local user; user="$(gh api user --jq .login 2>/dev/null)"
  [[ -n "$user" ]] || die "Couldn't determine your GitHub username."

  if [[ -d "$DOTFILES_DIR/.git" ]]; then
    ok "Dotfiles already cloned at $DOTFILES_DIR"
  else
    if [[ -e "$DOTFILES_DIR" ]]; then
      die "$DOTFILES_DIR exists but is not a git repo — move it aside and re-run."
    fi
    log "Cloning ${user}/${DOTFILES_REPO} into $DOTFILES_DIR"
    git clone "git@github.com:${user}/${DOTFILES_REPO}.git" "$DOTFILES_DIR" \
      || die "Failed to clone ${user}/${DOTFILES_REPO}. Does the repo exist?"
    ok "Cloned your zsh config."
  fi

  # Wire up the entrypoint so every new shell loads your config.
  zshrc_block "dotfiles" \
    "[ -f \"\$HOME/.zsh/${DOTFILES_ENTRY}\" ] && source \"\$HOME/.zsh/${DOTFILES_ENTRY}\""

  [[ -f "$DOTFILES_DIR/$DOTFILES_ENTRY" ]] \
    || warn "Heads up: $DOTFILES_DIR/$DOTFILES_ENTRY doesn't exist yet."
}

finish() {
  print -- ""
  ok "${C_BOLD}All done.${C_RESET}"
  info "Opening a fresh shell with your new config…"
  # Hand off to a brand-new shell that loads the updated ~/.zshrc (brew,
  # dotfiles, etc.) and breathes the final word.
  spawn_new_shell --welcome
  exit 0
}

# The first breath of the fresh shell.
welcome() {
  print -- ""
  ok "${C_BOLD}Your Mac is breathing.${C_RESET}"
  print -- ""
  print -- "${C_DIM}    And the LORD God formed man of the dust of the ground, and${C_RESET}"
  print -- "${C_DIM}    breathed into his nostrils the breath of life; and man${C_RESET}"
  print -- "${C_DIM}    became a living soul.${C_RESET}"
  print -- "${C_DIM}                                              — Genesis 2:7${C_RESET}"
  print -- ""
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

main() {
  [[ "$(uname -s)" == "Darwin" ]] || die "breathe only runs on macOS."

  # The fresh shell spawned at the very end just breathes the final word.
  if [[ "${1:-}" == "--welcome" ]]; then
    welcome
    return 0
  fi

  banner
  step_names        # first, before anything else
  step_preferences
  ensure_local

  step_claude_code
  step_homebrew     # may respawn + exit
  step_github_cli
  step_codex_cli
  step_dock
  step_github_auth
  step_ssh_agent
  step_dotfiles

  finish
}

# Skip auto-run when sourced for testing.
[[ -n "${BREATHE_TEST:-}" ]] || main "$@"
