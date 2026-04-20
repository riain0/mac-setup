#!/usr/bin/env bash
# =============================================================================
#  mac-setup.sh — Platform Engineer Laptop Bootstrap
#  Idempotent: safe to run multiple times on any macOS machine
#
#  Usage:
#    ./setup.sh                  → install everything (local clone)
#    ./setup.sh teardown         → remove everything installed by this script
#
#    Without cloning:
#    bash <(curl -fsSL https://raw.githubusercontent.com/riain0/mac-setup/main/setup.sh)
#    bash <(curl -fsSL https://raw.githubusercontent.com/riain0/mac-setup/main/setup.sh) teardown
#
#  The Brewfile controls exactly what gets installed — comment out any line
#  there to skip a package without touching this script.
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()     { echo -e "${CYAN}${BOLD}[setup]${RESET} $*"; }
success() { echo -e "${GREEN}\u2713${RESET} $*"; }
warn()    { echo -e "${YELLOW}\u26a0${RESET}  $*"; }
section() { echo -e "\n${BLUE}${BOLD}---  $*  ${RESET}"; }
fail()    { echo -e "${RED}\u2717${RESET} $*"; exit 1; }

MODE="${1:-install}"

[[ "$(uname)" == "Darwin" ]] || fail "macOS only."

# If running via curl (no local files), download repo files to a temp dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="$SCRIPT_DIR/Brewfile"
CLAUDE_SRC="$SCRIPT_DIR/CLAUDE.md"
_TMPDIR=""

if [[ ! -f "$BREWFILE" ]]; then
  _TMPDIR="$(mktemp -d)"
  BREWFILE="$_TMPDIR/Brewfile"
  CLAUDE_SRC="$_TMPDIR/CLAUDE.md"
  REPO_RAW="https://raw.githubusercontent.com/riain0/mac-setup/main"
  log "Running without local clone — downloading repo files..."
  curl -fsSL "$REPO_RAW/Brewfile"   -o "$BREWFILE"    || fail "Failed to download Brewfile"
  curl -fsSL "$REPO_RAW/CLAUDE.md"  -o "$CLAUDE_SRC"  || fail "Failed to download CLAUDE.md"
  trap '[[ -n "$_TMPDIR" ]] && rm -rf "$_TMPDIR"' EXIT
fi

# =============================================================================
# TEARDOWN
# =============================================================================
teardown() {
  section "Teardown - removing platform engineer tools"
  warn "KEPT: git, curl, wget, gnupg, zsh (universal tools)"
  echo ""
  read -r -p "Are you sure? Type 'yes' to continue: " confirm
  [[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 0; }

  if [[ -f "$BREWFILE" ]]; then
    section "Removing Brewfile packages..."
    # Extract all brew/cask entries from the Brewfile, skip comments and taps
    while IFS= read -r line; do
      # skip blanks, comments, tap lines
      [[ "$line" =~ ^[[:space:]]*(#|tap|$) ]] && continue

      if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
        pkg="${BASH_REMATCH[1]}"
        short="${pkg##*/}"
        # Skip core tools we always keep
        [[ "$short" =~ ^(git|curl|wget|gnupg|zsh)$ ]] && continue
        if brew list --formula "$short" &>/dev/null 2>&1; then
          log "Removing ${short}..."
          brew uninstall "$short" --ignore-dependencies 2>/dev/null \
            && success "Removed ${short}" \
            || warn "Could not remove ${short}"
        fi
      fi

      if [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
        pkg="${BASH_REMATCH[1]}"
        if brew list --cask "$pkg" &>/dev/null 2>&1; then
          log "Removing cask ${pkg}..."
          brew uninstall --cask "$pkg" 2>/dev/null \
            && success "Removed ${pkg}" \
            || warn "Could not remove ${pkg}"
        fi
      fi
    done < "$BREWFILE"
  else
    warn "Brewfile not found at $BREWFILE - skipping package removal"
  fi

  # HashiCorp tap
  if brew tap | grep -q "hashicorp/tap"; then
    log "Removing hashicorp/tap..."
    brew untap hashicorp/tap 2>/dev/null || true
  fi

  # AWS CLI v2 (installed via pkg, not brew)
  if [[ -f /usr/local/aws-cli/aws ]]; then
    log "Removing AWS CLI v2..."
    sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws /usr/local/bin/aws_completer
    success "AWS CLI removed"
  fi

  # Oh My Zsh
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    read -r -p "Remove Oh My Zsh? [y/N]: " omz
    if [[ "$omz" =~ ^[Yy]$ ]]; then
      env ZSH="$HOME/.oh-my-zsh" bash "$HOME/.oh-my-zsh/tools/uninstall.sh" 2>/dev/null \
        || rm -rf "$HOME/.oh-my-zsh"
      success "Oh My Zsh removed"
    fi
  fi

  # ~/.zshrc mac-setup block
  if grep -qF "# -- mac-setup" "$HOME/.zshrc" 2>/dev/null; then
    log "Removing mac-setup block from ~/.zshrc..."
    sed -i '' "/# -- mac-setup/,/# -- end mac-setup/d" "$HOME/.zshrc"
    success "~/.zshrc cleaned up"
  fi

  # Claude CLI
  if command -v claude &>/dev/null; then
    log "Removing Claude CLI..."
    rm -f "$(command -v claude)" 2>/dev/null || true
    success "Claude CLI removed"
  fi

  # Claude Code global config
  if [[ -f "$HOME/.claude/CLAUDE.md" ]]; then
    read -r -p "Remove ~/.claude/CLAUDE.md? [y/N]: " claude_cfg
    if [[ "$claude_cfg" =~ ^[Yy]$ ]]; then
      rm -f "$HOME/.claude/CLAUDE.md"
      success "~/.claude/CLAUDE.md removed"
    fi
  fi

  brew autoremove 2>/dev/null || true
  brew cleanup --prune=all -q 2>/dev/null || true

  echo ""
  success "Teardown complete"
  echo -e "  Homebrew itself was not removed. To remove it:"
  echo -e "  ${YELLOW}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)\"${RESET}"
  echo ""
  exit 0
}

[[ "$MODE" == "teardown" ]] && teardown

# =============================================================================
# INSTALL
# =============================================================================

[[ -f "$BREWFILE" ]] || fail "Brewfile not found at $BREWFILE — keep it next to this script."

# Only prompt for sudo if operations that need it haven't run yet
_needs_sudo=false
! command -v aws &>/dev/null && _needs_sudo=true
! grep -qF "/opt/homebrew/bin/zsh" /etc/shells 2>/dev/null && _needs_sudo=true

if $_needs_sudo; then
  log "Some steps require sudo — enter password once:"
  sudo -v
  while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done &
  SUDO_PID=$!
  trap "kill $SUDO_PID 2>/dev/null" EXIT
fi

# =============================================================================
section "Xcode Command Line Tools"
# =============================================================================
if xcode-select -p &>/dev/null 2>&1; then
  success "Xcode CLT already installed"
else
  warn "Xcode CLT not detected - Homebrew will install it in the next step."
fi

# =============================================================================
section "Homebrew"
# =============================================================================
if command -v brew &>/dev/null; then
  success "Homebrew already installed - updating"
  brew update --quiet
else
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
  fi
  success "Homebrew installed"
fi

# =============================================================================
section "Brewfile"
# =============================================================================
log "Installing packages from Brewfile..."
# --no-upgrade skips upgrading already-installed packages (keep it fast)
brew bundle --file="$BREWFILE" --no-upgrade
success "Brewfile packages installed"

# Post-install steps that brew bundle can't handle
log "Running post-install steps..."

# fzf shell integration
"$(brew --prefix)/opt/fzf/install" --all --no-update-rc &>/dev/null || true

# git-lfs system hooks
git lfs install --system &>/dev/null || true

# tfenv: remove any conflicting standalone terraform, then install latest
if brew list --formula terraform &>/dev/null 2>&1; then
  log "Removing standalone terraform (tfenv will manage it)..."
  brew unlink terraform 2>/dev/null || true
  brew uninstall terraform --ignore-dependencies 2>/dev/null || true
fi
if command -v tfenv &>/dev/null; then
  log "Installing latest Terraform via tfenv..."
  tfenv install latest 2>/dev/null || true
  tfenv use latest     2>/dev/null || true
  success "Terraform $(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || echo 'latest') active"
fi

# =============================================================================
section "AWS CLI v2"
# =============================================================================
# Installed via native pkg — brew version lags behind
if command -v aws &>/dev/null; then
  success "AWS CLI already installed ($(aws --version 2>&1 | awk '{print $1}'))"
else
  log "Installing AWS CLI v2..."
  TMP=$(mktemp -d)
  curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "$TMP/AWSCLIV2.pkg"
  sudo installer -pkg "$TMP/AWSCLIV2.pkg" -target /
  rm -rf "$TMP"
  success "AWS CLI v2 installed"
fi

# =============================================================================
section "Claude CLI"
# =============================================================================
if command -v claude &>/dev/null; then
  success "Claude CLI already installed"
else
  log "Installing Claude CLI..."
  curl -fsSL https://claude.ai/install.sh | sh \
    && success "Claude CLI installed" \
    || warn "Claude CLI install failed - visit https://claude.ai/download"
fi

# =============================================================================
section "Claude Code Config"
# =============================================================================
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"
CLAUDE_CFG="$CLAUDE_DIR/CLAUDE.md"

if [[ ! -f "$CLAUDE_SRC" ]]; then
  warn "CLAUDE.md not found next to setup.sh - skipping"
elif [[ -f "$CLAUDE_CFG" ]] && diff -q "$CLAUDE_CFG" "$CLAUDE_SRC" &>/dev/null; then
  success "~/.claude/CLAUDE.md already up to date"
else
  [[ -f "$CLAUDE_CFG" ]] && cp "$CLAUDE_CFG" "${CLAUDE_CFG}.bak"
  cp "$CLAUDE_SRC" "$CLAUDE_CFG"
  success "~/.claude/CLAUDE.md installed"
fi

# =============================================================================
section "Shell - Zsh"
# =============================================================================
ZSH_PATH="$(brew --prefix)/bin/zsh"
if ! grep -qF "$ZSH_PATH" /etc/shells; then
  log "Adding Homebrew zsh to /etc/shells..."
  echo "$ZSH_PATH" | sudo tee -a /etc/shells
fi
if [[ "$SHELL" == *"zsh" ]]; then
  success "Already using zsh ($SHELL) - skipping chsh"
else
  log "Changing default shell to zsh..."
  chsh -s "$ZSH_PATH"
  success "Default shell changed - re-login to take effect"
fi

# =============================================================================
section "Oh My Zsh"
# =============================================================================
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  success "Oh My Zsh already installed"
else
  log "Installing Oh My Zsh..."
  RUNZSH=no CHSH=no \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  success "Oh My Zsh installed"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
  log "Installing zsh-autosuggestions..."
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
  log "Installing zsh-syntax-highlighting..."
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi
if [[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]]; then
  log "Installing Powerlevel10k..."
  git clone --depth=1 https://github.com/romkatv/powerlevel10k \
    "$ZSH_CUSTOM/themes/powerlevel10k"
fi
success "OMZ plugins and Powerlevel10k ready"

# =============================================================================
section "macOS Defaults"
# =============================================================================
log "Applying developer-friendly macOS defaults..."

defaults write NSGlobalDomain AppleShowAllExtensions   -bool true
defaults write com.apple.finder AppleShowAllFiles      -bool true
defaults write com.apple.finder ShowPathbar            -bool true
defaults write com.apple.LaunchServices LSQuarantine   -bool false
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain KeyRepeat                -int 2
defaults write NSGlobalDomain InitialKeyRepeat         -int 15

mkdir -p "$HOME/Screenshots"
defaults write com.apple.screencapture location        "$HOME/Screenshots"
defaults write com.apple.screencapture disable-shadow  -bool true
defaults write com.apple.dock autohide                 -bool true
defaults write com.apple.dock show-recents             -bool false

killall Finder Dock 2>/dev/null || true
success "macOS defaults applied"

# =============================================================================
section "Git Global Config"
# =============================================================================
if [[ -z "$(git config --global user.name 2>/dev/null)" ]]; then
  echo -n "  Git name: "; read -r GIT_NAME
  git config --global user.name "$GIT_NAME"
fi
if [[ -z "$(git config --global user.email 2>/dev/null)" ]]; then
  echo -n "  Git email: "; read -r GIT_EMAIL
  git config --global user.email "$GIT_EMAIL"
fi

git config --global init.defaultBranch  main
git config --global pull.rebase         true
git config --global rebase.autoStash    true
git config --global core.autocrlf       input
git config --global core.editor         vim
git config --global fetch.prune         true
git config --global diff.colorMoved     zebra
git config --global alias.lg   "log --oneline --graph --decorate --all"
git config --global alias.st   status
git config --global alias.co   checkout
success "Git config set"

# =============================================================================
section "Zsh Config"
# =============================================================================
ZSHRC="$HOME/.zshrc"

if grep -qF "# -- mac-setup" "$ZSHRC" 2>/dev/null; then
  success "~/.zshrc already configured - skipping"
else
  # Back up existing .zshrc then write a clean one.
  # The prepend+append approach creates duplicate OMZ sources when the default
  # Oh My Zsh .zshrc is already present, causing p10k to abort sourcing early.
  [[ -f "$ZSHRC" ]] && cp "$ZSHRC" "${ZSHRC}.bak"

  cat > "$ZSHRC" << 'ZSHRC_BLOCK'
# -- mac-setup ----------------------------------------------------------------

# Powerlevel10k instant prompt - must be first, before any output
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Homebrew - must be before OMZ so plugins find their commands at load time
eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
  git
  docker
  kubectl
  terraform
  aws
  gcloud
  gh
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source "$ZSH/oh-my-zsh.sh"

# zoxide (smarter cd)
eval "$(zoxide init zsh)" 2>/dev/null || true

# direnv
eval "$(direnv hook zsh)" 2>/dev/null || true

# fzf
eval "$(fzf --zsh)" 2>/dev/null || true

# -- Aliases: Navigation ------------------------------------------------------
alias ll='eza -la --git --icons'
alias lt='eza --tree --level=2 --icons'
alias cat='bat --style=plain'
alias cd='z'
alias c='clear'

# -- Aliases: Git -------------------------------------------------------------
alias gs='git status'
alias gd='git diff'
alias gco='git checkout'
alias gbr='git branch'
alias gcm='git commit -m'
alias gpl='git pull --rebase'
alias gps='git push'
alias glg='git lg'

# -- Aliases: Kubernetes ------------------------------------------------------
alias k='kubectl'
alias kctx='kubectx'
alias kns='kubens'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgn='kubectl get nodes'
alias kga='kubectl get all'
alias kd='kubectl describe'
alias kl='kubectl logs -f'
alias ke='kubectl exec -it'
alias kap='kubectl apply -f'
alias kdel='kubectl delete -f'

# -- Aliases: Terraform -------------------------------------------------------
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfaa='terraform apply -auto-approve'
alias tfd='terraform destroy'
alias tfv='terraform validate'
alias tff='terraform fmt -recursive'
alias tfw='terraform workspace'

# -- Aliases: Docker ----------------------------------------------------------
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dex='docker exec -it'
alias dlogs='docker logs -f'
alias dprune='docker system prune -af'

# -- Aliases: AWS -------------------------------------------------------------
alias awsid='aws sts get-caller-identity'
alias awsctx='aws configure list'

# -- Aliases: GCP -------------------------------------------------------------
alias gcpid='gcloud auth list'
alias gcpproj='gcloud config get-value project'

# -- PATH ---------------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"

# Powerlevel10k config
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

setopt aliases  # p10k/gitstatus sets no_aliases internally and can leak it
# -- end mac-setup ------------------------------------------------------------
ZSHRC_BLOCK

  success "~/.zshrc updated"
fi

# =============================================================================
section "Powerlevel10k Config"
# =============================================================================
P10K="$HOME/.p10k.zsh"

if [[ -f "$P10K" ]]; then
  success "~/.p10k.zsh already exists - skipping"
else
  log "Writing ~/.p10k.zsh..."
  cat > "$P10K" << 'P10K_BLOCK'
'builtin' 'local' '-a' 'p10k_config_opts'
[[ ! -o 'aliases'         ]] || p10k_config_opts+=('aliases')
[[ ! -o 'sh_glob'         ]] || p10k_config_opts+=('sh_glob')
[[ ! -o 'no_brace_expand' ]] || p10k_config_opts+=('no_brace_expand')
'builtin' 'setopt' 'no_aliases' 'no_sh_glob' 'brace_expand'

() {
  emulate -L zsh -o extended_glob
  unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'

  typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    dir vcs newline prompt_char
  )
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    status command_execution_time background_jobs
    direnv aws gcloud kubecontext terraform context time
  )

  typeset -g POWERLEVEL9K_MODE=nerdfont-v3
  typeset -g POWERLEVEL9K_ICON_PADDING=moderate
  typeset -g POWERLEVEL9K_BACKGROUND=
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_{LEFT,RIGHT}_WHITESPACE=
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SUBSEGMENT_SEPARATOR=' '
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SEGMENT_SEPARATOR=
  typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true

  typeset -g POWERLEVEL9K_DIR_FOREGROUND=blue
  typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=true
  typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
  typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=40

  typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND=green
  typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=yellow
  typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=cyan
  typeset -g POWERLEVEL9K_VCS_CONFLICTED_FOREGROUND=red

  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=green
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=red
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='>'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VICMD_CONTENT_EXPANSION='<'

  typeset -g POWERLEVEL9K_STATUS_OK=false
  typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=red

  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=1
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=yellow
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FORMAT='d h m s'

  typeset -g POWERLEVEL9K_AWS_SHOW_ON_COMMAND='aws|awsid|awsctx|terraform|tf|sam|cdk'
  typeset -g POWERLEVEL9K_AWS_DEFAULT_FOREGROUND=208
  typeset -g POWERLEVEL9K_AWS_prod_FOREGROUND=red
  typeset -g POWERLEVEL9K_AWS_production_FOREGROUND=red
  typeset -g POWERLEVEL9K_AWS_staging_FOREGROUND=yellow
  typeset -g POWERLEVEL9K_AWS_dev_FOREGROUND=green
  typeset -g POWERLEVEL9K_AWS_development_FOREGROUND=green

  typeset -g POWERLEVEL9K_GCLOUD_SHOW_ON_COMMAND='gcloud|gsutil|bq|gcpid|gcpproj'
  typeset -g POWERLEVEL9K_GCLOUD_FOREGROUND=32
  typeset -g POWERLEVEL9K_GCLOUD_PARTIAL_CONTENT_EXPANSION='${P9K_GCLOUD_PROJECT_ID//\%/%%}'
  typeset -g POWERLEVEL9K_GCLOUD_COMPLETE_CONTENT_EXPANSION='${P9K_GCLOUD_PROJECT_NAME//\%/%%}'
  typeset -g POWERLEVEL9K_GCLOUD_REFRESH_PROJECT_NAME_SECONDS=60

  typeset -g POWERLEVEL9K_KUBECONTEXT_SHOW_ON_COMMAND='kubectl|helm|helmfile|k9s|kubectx|kubens|stern|k'
  typeset -g POWERLEVEL9K_KUBECONTEXT_CLASSES=(
    '*prod*'    PROD
    '*staging*' STAGING
    '*dev*'     DEV
    '*'         DEFAULT
  )
  typeset -g POWERLEVEL9K_KUBECONTEXT_PROD_FOREGROUND=red
  typeset -g POWERLEVEL9K_KUBECONTEXT_STAGING_FOREGROUND=yellow
  typeset -g POWERLEVEL9K_KUBECONTEXT_DEV_FOREGROUND=green
  typeset -g POWERLEVEL9K_KUBECONTEXT_DEFAULT_FOREGROUND=cyan
  typeset -g POWERLEVEL9K_KUBECONTEXT_DEFAULT_CONTENT_EXPANSION='${P9K_KUBECONTEXT_CLOUD_CLUSTER:-${P9K_KUBECONTEXT_NAME}}${${P9K_KUBECONTEXT_NAMESPACE:#default}:+  ${P9K_KUBECONTEXT_NAMESPACE}}'

  typeset -g POWERLEVEL9K_TERRAFORM_SHOW_ON_COMMAND='terraform|tf|terragrunt'
  typeset -g POWERLEVEL9K_TERRAFORM_CLASSES=(
    '*prod*'    PROD
    '*staging*' STAGING
    '*dev*'     DEV
    '*'         DEFAULT
  )
  typeset -g POWERLEVEL9K_TERRAFORM_PROD_FOREGROUND=red
  typeset -g POWERLEVEL9K_TERRAFORM_STAGING_FOREGROUND=yellow
  typeset -g POWERLEVEL9K_TERRAFORM_DEV_FOREGROUND=green
  typeset -g POWERLEVEL9K_TERRAFORM_DEFAULT_FOREGROUND=105

  typeset -g POWERLEVEL9K_DIRENV_FOREGROUND=3

  typeset -g POWERLEVEL9K_CONTEXT_SSH_FOREGROUND=yellow
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND=red
  typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_CONTENT_EXPANSION=

  typeset -g POWERLEVEL9K_TIME_FOREGROUND=66
  typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%H:%M}'
  typeset -g POWERLEVEL9K_TIME_UPDATE_ON_COMMAND=false

  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_VERBOSE=false
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND=cyan

  typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
  typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true

  (( ${#p10k_config_opts} )) && setopt ${p10k_config_opts[@]}
}
'builtin' 'unset' 'p10k_config_opts'
P10K_BLOCK

  success "~/.p10k.zsh written"
fi

# =============================================================================
section "Terminal Fonts"
# =============================================================================
NERD_FONT="MesloLGS Nerd Font Mono"

# Warp
WARP_PREFS="$HOME/.warp/user_preferences.yaml"
if [[ -d "$HOME/.warp" ]] || command -v warp-terminal &>/dev/null; then
  mkdir -p "$HOME/.warp"
  if [[ -f "$WARP_PREFS" ]] && grep -q "^font_name:" "$WARP_PREFS"; then
    sed -i '' "s/^font_name:.*/font_name: \"$NERD_FONT\"/" "$WARP_PREFS"
  elif [[ -f "$WARP_PREFS" ]]; then
    echo "font_name: \"$NERD_FONT\"" >> "$WARP_PREFS"
  else
    echo "font_name: \"$NERD_FONT\"" > "$WARP_PREFS"
  fi
  success "Warp font set to $NERD_FONT"
fi

# VSCode / Cursor — set terminal.integrated.fontFamily in settings.json
set_editor_font() {
  local settings="$1" app="$2"
  if [[ ! -d "$(dirname "$settings")" ]]; then return; fi
  if [[ ! -f "$settings" ]]; then
    echo "{\"terminal.integrated.fontFamily\": \"$NERD_FONT\"}" > "$settings"
    success "$app terminal font set to $NERD_FONT"
  elif grep -q "terminal.integrated.fontFamily" "$settings"; then
    success "$app terminal font already configured"
  else
    python3 -c "
import json
with open('$settings') as f: s = json.load(f)
s['terminal.integrated.fontFamily'] = '$NERD_FONT'
with open('$settings', 'w') as f: json.dump(s, f, indent=4)
"
    success "$app terminal font set to $NERD_FONT"
  fi
}

set_editor_font "$HOME/Library/Application Support/Code/User/settings.json"   "VSCode"
set_editor_font "$HOME/Library/Application Support/Cursor/User/settings.json" "Cursor"

# =============================================================================
section "Cleanup"
# =============================================================================
brew cleanup --prune=all -q
brew autoremove -q

# =============================================================================
echo ""
echo -e "${GREEN}${BOLD}=================================================${RESET}"
echo -e "${GREEN}${BOLD}  Setup complete - restart your terminal         ${RESET}"
echo -e "${GREEN}${BOLD}=================================================${RESET}"
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo -e "  1. ${YELLOW}gcloud init${RESET}             - authenticate GCP"
echo -e "  2. ${YELLOW}aws configure${RESET}           - set AWS credentials"
echo -e "  3. ${YELLOW}gh auth login${RESET}           - authenticate GitHub CLI"
echo -e "  4. ${YELLOW}colima start${RESET}            - start Docker daemon"
echo -e "  5. ${YELLOW}gt auth${RESET}                 - authenticate Graphite CLI"
echo -e "  6. See README for Claude Code skill install (Bureau + Caveman)"
echo ""
