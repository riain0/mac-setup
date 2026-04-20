# mac-setup

Idempotent bootstrap for a platform engineer's Mac. Safe to re-run — skips anything already installed.

## Usage

```bash
./setup.sh           # install everything
./setup.sh teardown  # remove everything installed by this script
```

## What gets installed

| Section | Tools |
|---------|-------|
| Xcode CLI tools | git, clang, make |
| Homebrew packages | see `Brewfile` |
| AWS CLI v2 | installed via native pkg (brew version lags) |
| Claude Code | CLI + global config (`~/.claude/CLAUDE.md`) |
| Zsh + Oh My Zsh | powerlevel10k, plugins, aliases |
| macOS defaults | developer-friendly system settings |
| Git global config | user, delta pager, lg alias |
| Terminal fonts | MesloLGS NF (required for p10k) |

### Key tools in Brewfile

- **Shell**: `eza`, `bat`, `fzf`, `zoxide`, `direnv`
- **Cloud**: `aws-vault`, `gcloud-cli`, `azure-cli`
- **IaC**: `tfenv`, `terragrunt`, `tflint`, `tfsec`, `infracost`
- **Kubernetes**: `kubectl`, `kubectx`, `helm`, `helmfile`, `k9s`, `krew`
- **VCS**: `gh`, `graphite`
- **Containers**: `docker`, `colima` (no Docker Desktop needed)

## Customization

Edit `Brewfile` to add or remove packages before running setup. Comment out any line to skip it — no changes to `setup.sh` needed.

## After setup

```bash
gcloud init       # authenticate GCP
aws configure     # set AWS credentials
gh auth login     # authenticate GitHub CLI
gt auth           # authenticate Graphite CLI
colima start      # start Docker daemon
```

## Claude Code config

`CLAUDE.md` in this repo is installed to `~/.claude/CLAUDE.md` — the global Claude Code config applied across all projects. It configures:

- **Caveman mode** — terse, low-token communication style
- **Commits** — Conventional Commits via `/caveman-commit`
- **Git workflow** — Graphite (`gt`) for all branch/PR operations
- **Bureau** — Claude Code agent package manager

Re-running `setup.sh` updates `~/.claude/CLAUDE.md` if the file has changed (backs up the existing one first).

### Installing Claude Code skills

**Bureau** (agent package manager):

```
claude plugin marketplace add riain0/bureau
claude plugin install bureau
```

**Caveman** (terse communication mode):

```
claude plugin marketplace add JuliusBrussee/caveman && claude plugin install caveman@caveman
```

| Feature | Tool | Installed by |
|---------|------|-------------|
| Caveman mode | Claude Code plugin | above |
| Graphite workflow | `gt` CLI | Brewfile |
| Bureau | Claude Code plugin | above |
