#!/usr/bin/env bash
# =============================================================================
#  cleanup.sh — Remove formulae no longer in the Brewfile
#
#  Run this whenever you remove something from the Brewfile and want to
#  actually uninstall it from your machine.
#
#  Usage:
#    ./cleanup.sh              → dry run (shows what would be removed)
#    ./cleanup.sh --apply      → actually uninstall
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'

log()     { echo -e "${CYAN}${BOLD}[cleanup]${RESET} $*"; }
success() { echo -e "${GREEN}\u2713${RESET} $*"; }
warn()    { echo -e "${YELLOW}\u26a0${RESET}  $*"; }
removed() { echo -e "${RED}\u2717${RESET} $*"; }

DRY_RUN=true
[[ "${1:-}" == "--apply" ]] && DRY_RUN=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="$SCRIPT_DIR/Brewfile"

[[ -f "$BREWFILE" ]] || { warn "Brewfile not found at $BREWFILE"; exit 1; }

# Packages that should never be removed regardless of Brewfile contents
ALWAYS_KEEP=(
  git
  curl
  wget
  gnupg
  zsh
  ca-certificates
  openssl
)

echo ""
echo -e "${BOLD}Brewfile:${RESET} $BREWFILE"
if $DRY_RUN; then
  echo -e "${YELLOW}${BOLD}Dry run — nothing will be changed. Pass --apply to uninstall.${RESET}"
fi
echo ""

# ── Build a set of packages the Brewfile wants ────────────────────────────────
declare -A wanted_formulae
declare -A wanted_casks

while IFS= read -r line; do
  # Skip blanks and comments
  [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue

  if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
    pkg="${BASH_REMATCH[1]}"
    short="${pkg##*/}"   # strip tap prefix
    wanted_formulae["$short"]=1
  fi

  if [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
    wanted_casks["${BASH_REMATCH[1]}"]=1
  fi
done < "$BREWFILE"

# ── Check installed formulae against the Brewfile ─────────────────────────────
echo -e "${BOLD}Checking formulae...${RESET}"

stale_formulae=()

while IFS= read -r pkg; do
  # Skip if in the Brewfile
  [[ "${wanted_formulae[$pkg]+_}" ]] && continue

  # Skip always-keep list
  keep=false
  for k in "${ALWAYS_KEEP[@]}"; do
    [[ "$pkg" == "$k" ]] && keep=true && break
  done
  $keep && continue

  # Skip formulae that are dependencies of other installed packages
  # (brew will handle these via autoremove)
  if brew uses --installed "$pkg" &>/dev/null 2>&1; then
    dependents=$(brew uses --installed "$pkg" 2>/dev/null | tr '\n' ' ')
    if [[ -n "$dependents" ]]; then
      warn "$pkg is a dependency of: ${dependents}— skipping (autoremove will handle it)"
      continue
    fi
  fi

  stale_formulae+=("$pkg")
done < <(brew list --formula)

if [[ ${#stale_formulae[@]} -eq 0 ]]; then
  success "No stale formulae found"
else
  echo ""
  echo -e "${BOLD}Stale formulae (installed but not in Brewfile):${RESET}"
  for pkg in "${stale_formulae[@]}"; do
    if $DRY_RUN; then
      removed "would remove: $pkg"
    else
      log "Removing $pkg..."
      brew uninstall "$pkg" --ignore-dependencies 2>/dev/null \
        && removed "removed: $pkg" \
        || warn "Could not remove $pkg (may be needed as a dependency)"
    fi
  done
fi

# ── Check installed casks against the Brewfile ────────────────────────────────
echo ""
echo -e "${BOLD}Checking casks...${RESET}"

stale_casks=()

while IFS= read -r cask; do
  [[ "${wanted_casks[$cask]+_}" ]] && continue
  stale_casks+=("$cask")
done < <(brew list --cask 2>/dev/null || true)

if [[ ${#stale_casks[@]} -eq 0 ]]; then
  success "No stale casks found"
else
  echo ""
  echo -e "${BOLD}Stale casks (installed but not in Brewfile):${RESET}"
  for cask in "${stale_casks[@]}"; do
    if $DRY_RUN; then
      removed "would remove: $cask"
    else
      log "Removing cask $cask..."
      brew uninstall --cask "$cask" 2>/dev/null \
        && removed "removed: $cask" \
        || warn "Could not remove cask $cask"
    fi
  done
fi

# ── Autoremove orphaned dependencies ──────────────────────────────────────────
echo ""
echo -e "${BOLD}Orphaned dependencies...${RESET}"
if $DRY_RUN; then
  orphans=$(brew autoremove --dry-run 2>/dev/null || true)
  if [[ -n "$orphans" ]]; then
    warn "Would autoremove orphaned deps:"
    echo "$orphans" | sed 's/^/  /'
  else
    success "No orphaned dependencies"
  fi
else
  brew autoremove 2>/dev/null || true
  brew cleanup --prune=all -q 2>/dev/null || true
  success "Orphaned dependencies removed"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
total_stale=$(( ${#stale_formulae[@]} + ${#stale_casks[@]} ))
if $DRY_RUN; then
  if [[ $total_stale -gt 0 ]]; then
    echo -e "${YELLOW}${BOLD}$total_stale package(s) would be removed.${RESET}"
    echo -e "Run ${CYAN}./brew-cleanup.sh --apply${RESET} to uninstall them."
  else
    echo -e "${GREEN}${BOLD}Everything is clean.${RESET}"
  fi
else
  echo -e "${GREEN}${BOLD}Cleanup complete.${RESET}"
fi
echo ""
