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
  log "Opening a fresh shell to continue…"
  info "(this window can be closed)"
  osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "Terminal"
  activate
  do script "zsh '$BREATHE_BIN'"
end tell
APPLESCRIPT
}

# Make sure a local copy of breathe exists on disk, then point this process at
# it. When run via \`curl | zsh\` there is no source file to copy, so we fetch a
# fresh copy from BREATHE_URL. Respawned shells already run BREATHE_BIN directly.
ensure_local() {
  mkdir -p "$BREATHE_HOME"
  if [[ "${0:A}" != "${BREATHE_BIN:A}" ]]; then
    info "Caching breathe at $BREATHE_BIN"
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
  ok "${C_BOLD}All done — your Mac is breathing.${C_RESET}"
  info "Open a new terminal (or run: source ~/.zshrc) to load your config."
  print -- ""
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

main() {
  [[ "$(uname -s)" == "Darwin" ]] || die "breathe only runs on macOS."
  ensure_local
  banner

  step_homebrew     # may respawn + exit
  step_github_cli
  step_github_auth
  step_dotfiles

  finish
}

# Skip auto-run when sourced for testing.
[[ -n "${BREATHE_TEST:-}" ]] || main "$@"
