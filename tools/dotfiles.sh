#!/bin/bash
# meister dotfiles — Dev environment sync across machines
# Install: brew install maf4711/meister/meister
#
# First time (new machine):  meister setup
# Daily use:                 meister push / pull / status

set -euo pipefail

VERSION="1.0.0"
CONF_DIR="$HOME/.meister"
CONF_FILE="$CONF_DIR/dotfiles.conf"
DOTFILES="${MEISTER_DOTFILES:-$HOME/dotfiles}"
BACKUP_DIR="$DOTFILES/.backups/$(date +%Y%m%d-%H%M%S)"

# Colors
R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' B='\033[0;34m' C='\033[0;36m' D='\033[2m' N='\033[0m'

# ─── Config ───

load_conf() {
  [ -f "$CONF_FILE" ] && source "$CONF_FILE"
  DOTFILES="${MEISTER_DOTFILES:-${dotfiles_path:-$HOME/dotfiles}}"
}

save_conf() {
  mkdir -p "$CONF_DIR"
  cat > "$CONF_FILE" << EOF
# meister dotfiles config
dotfiles_repo="$1"
dotfiles_path="$2"
EOF
}

# ─── Helpers ───

log()  { echo -e "${B}[meister]${N} $*"; }
ok()   { echo -e "  ${G}✓${N} $1"; }
lnk()  { echo -e "  ${C}→${N} $1"; }
bak()  { echo -e "  ${Y}↗${N} $1 (backed up)"; }
skip() { echo -e "  ${D}· $1${N}"; }
fail() { echo -e "  ${R}✗${N} $1"; }
die()  { echo -e "${R}[meister] $1${N}" >&2; exit 1; }

safe_link() {
  local src="$DOTFILES/$1" dst="$2"
  [ -e "$src" ] || { skip "$1 (not in dotfiles)"; return; }
  mkdir -p "$(dirname "$dst")"

  if [ -L "$dst" ]; then
    [ "$(readlink "$dst")" = "$src" ] && { ok "$dst"; return; }
    rm "$dst"
  elif [ -e "$dst" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$dst" "$BACKUP_DIR/$(basename "$dst").$(date +%s)"
    bak "$dst"
  fi

  ln -s "$src" "$dst"
  lnk "$dst"
}

safe_copy() {
  local src="$1" dst="$DOTFILES/$2"
  [ -e "$src" ] || return
  local real_src real_dst
  real_src="$(readlink -f "$src" 2>/dev/null || echo "$src")"
  real_dst="$(readlink -f "$DOTFILES/$2" 2>/dev/null || echo "$DOTFILES/$2")"
  [ "$real_src" = "$real_dst" ] && return
  mkdir -p "$(dirname "$dst")"
  if [ -d "$real_src" ]; then
    rsync -a --delete "$real_src/" "$dst/"
  else
    cp "$real_src" "$dst"
  fi
}

need_dotfiles() {
  [ -d "$DOTFILES/.git" ] || die "No dotfiles repo at $DOTFILES. Run: meister setup"
}

# ─── Symlink Map ───
# Discovered automatically from dotfiles/manifest.txt
# Format per line: dotfiles_relative_path|target_path
# Lines starting with # are ignored

MANIFEST_FILE="$DOTFILES/manifest.txt"

read_manifest() {
  [ -f "$MANIFEST_FILE" ] || return
  while IFS='|' read -r src dst; do
    [[ "$src" =~ ^#.*$ ]] && continue
    [ -z "$src" ] && continue
    # Expand ~ and $HOME
    dst="${dst/\~/$HOME}"
    dst="${dst/\$HOME/$HOME}"
    echo "$src|$dst"
  done < "$MANIFEST_FILE"
}

# ─── Commands ───

cmd_init() {
  if [ -d "$DOTFILES/.git" ]; then
    if git -C "$DOTFILES" remote get-url origin &>/dev/null; then
      log "Already initialized: $(git -C "$DOTFILES" remote get-url origin)"
      return
    fi
  fi

  command -v gh &>/dev/null || die "gh CLI required. Install: brew install gh"
  gh auth status &>/dev/null 2>&1 || { log "Logging in to GitHub..."; gh auth login; }

  local user repo_name
  user=$(gh api user --jq .login)
  repo_name="${1:-dotfiles}"

  if [ ! -d "$DOTFILES/.git" ]; then
    mkdir -p "$DOTFILES"
    git -C "$DOTFILES" init
  fi

  log "Creating private repo ${user}/${repo_name}..."
  gh repo create "$repo_name" --private --source="$DOTFILES" --remote=origin 2>/dev/null || true

  # SSH URL
  git -C "$DOTFILES" remote set-url origin "git@github.com:${user}/${repo_name}.git" 2>/dev/null \
    || git -C "$DOTFILES" remote add origin "git@github.com:${user}/${repo_name}.git"
  git -C "$DOTFILES" push -u origin main 2>/dev/null || git -C "$DOTFILES" push -u origin main --force

  save_conf "git@github.com:${user}/${repo_name}.git" "$DOTFILES"
  log "${G}Done: github.com/${user}/${repo_name} (private)${N}"
}

cmd_setup() {
  local repo_url="${1:-}"

  # Already set up?
  if [ -d "$DOTFILES/.git" ]; then
    log "Dotfiles already at $DOTFILES"
    cmd_pull
    return
  fi

  # Get repo URL
  if [ -z "$repo_url" ]; then
    # Try to detect from gh
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
      local user
      user=$(gh api user --jq .login 2>/dev/null || true)
      if [ -n "$user" ]; then
        local detected="git@github.com:${user}/dotfiles.git"
        if git ls-remote "$detected" &>/dev/null 2>&1; then
          repo_url="$detected"
          log "Detected: $repo_url"
        fi
      fi
    fi
  fi

  [ -z "$repo_url" ] && die "Could not detect dotfiles repo. Pass URL: meister setup git@github.com:user/dotfiles.git"

  log "Cloning $repo_url → $DOTFILES"
  git clone "$repo_url" "$DOTFILES"

  save_conf "$repo_url" "$DOTFILES"

  # Generate manifest if missing
  if [ ! -f "$MANIFEST_FILE" ]; then
    cmd_scan
  fi

  cmd_pull
  log "${G}Setup complete.${N}"
}

cmd_scan() {
  log "Scanning for configs to sync..."
  need_dotfiles

  local manifest="$MANIFEST_FILE"

  cat > "$manifest" << 'HEADER'
# meister dotfiles manifest
# Format: dotfiles_path|target_path
# Lines starting with # are skipped
# Edit this file to add/remove sync targets

# ─── Claude Code ───
HEADER

  local -a found=()

  # Claude Code
  for item in CLAUDE.md settings.json skills hooks commands agents statusline-command.sh package.json; do
    [ -e "$HOME/.claude/$item" ] && echo "claude/$item|\$HOME/.claude/$item" >> "$manifest" && found+=("claude/$item")
  done

  # Claude Plugins manifest
  if [ -f "$HOME/.claude/plugins/installed_plugins.json" ]; then
    echo "claude-plugins/installed_plugins.json|\$HOME/.claude/plugins/installed_plugins.json" >> "$manifest"
    found+=("claude-plugins")
  fi

  # Agent Skills
  echo "" >> "$manifest"; echo "# ─── Agent Skills ───" >> "$manifest"
  [ -d "$HOME/.agents/skills" ] && echo "agents/skills|\$HOME/.agents/skills" >> "$manifest" && found+=("agents/skills")
  [ -f "$HOME/.agents/.skill-lock.json" ] && echo "agents/.skill-lock.json|\$HOME/.agents/.skill-lock.json" >> "$manifest"

  # Gemini
  echo "" >> "$manifest"; echo "# ─── Gemini CLI ───" >> "$manifest"
  for item in GEMINI.md settings.json; do
    [ -e "$HOME/.gemini/$item" ] && echo "gemini/$item|\$HOME/.gemini/$item" >> "$manifest" && found+=("gemini/$item")
  done

  # Codex
  echo "" >> "$manifest"; echo "# ─── OpenAI Codex ───" >> "$manifest"
  [ -f "$HOME/.codex/config.toml" ] && echo "codex/config.toml|\$HOME/.codex/config.toml" >> "$manifest" && found+=("codex")

  # Git
  echo "" >> "$manifest"; echo "# ─── Git ───" >> "$manifest"
  [ -f "$HOME/.gitconfig" ] && echo "git/.gitconfig|\$HOME/.gitconfig" >> "$manifest" && found+=("gitconfig")

  # SSH (config only!)
  echo "" >> "$manifest"; echo "# ─── SSH (config only, NOT keys) ───" >> "$manifest"
  [ -f "$HOME/.ssh/config" ] && echo "ssh/config|\$HOME/.ssh/config" >> "$manifest" && found+=("ssh/config")

  # Shell
  echo "" >> "$manifest"; echo "# ─── Shell ───" >> "$manifest"
  [ -f "$HOME/.zshrc" ] && echo "zsh/.zshrc|\$HOME/.zshrc" >> "$manifest" && found+=("zshrc")
  [ -f "$HOME/.bashrc" ] && echo "bash/.bashrc|\$HOME/.bashrc" >> "$manifest" && found+=("bashrc")

  # Terminal
  echo "" >> "$manifest"; echo "# ─── Terminal ───" >> "$manifest"
  [ -f "$HOME/.config/ghostty/config" ] && echo "ghostty/config|\$HOME/.config/ghostty/config" >> "$manifest" && found+=("ghostty")
  [ -f "$HOME/.config/alacritty/alacritty.yml" ] && echo "alacritty/alacritty.yml|\$HOME/.config/alacritty/alacritty.yml" >> "$manifest" && found+=("alacritty")
  [ -f "$HOME/.config/starship.toml" ] && echo "starship/starship.toml|\$HOME/.config/starship.toml" >> "$manifest" && found+=("starship")

  # Atuin
  [ -f "$HOME/.config/atuin/config.toml" ] && echo "atuin/config.toml|\$HOME/.config/atuin/config.toml" >> "$manifest" && found+=("atuin")

  # LaunchAgents (user-defined only)
  echo "" >> "$manifest"; echo "# ─── LaunchAgents ───" >> "$manifest"
  if [ -d "$HOME/Library/LaunchAgents" ]; then
    for plist in "$HOME/Library/LaunchAgents"/*.plist; do
      [ -f "$plist" ] || continue
      local name
      name=$(basename "$plist")
      # Skip Apple/system/app-managed plists
      [[ "$name" == com.apple.* ]] && continue
      [[ "$name" == ai.perplexity.* ]] && continue
      [[ "$name" == com.bluebubbles.* ]] && continue
      [[ "$name" == homebrew.mxcl.* ]] && continue
      echo "launchagents/$name|\$HOME/Library/LaunchAgents/$name" >> "$manifest"
      found+=("$name")
    done
  fi

  log "Found ${#found[@]} configs."

  # ── Auto-generate clone-repos.sh from ~/Developer ──
  log "Scanning repos in ~/Developer..."
  local dev="$HOME/Developer"
  local clone_script="$DOTFILES/clone-repos.sh"
  local repo_count=0

  cat > "$clone_script" << 'CLONEHEAD'
#!/bin/bash
# clone-repos.sh — auto-generated by meister scan
# Recreates ~/Developer repo structure

set -euo pipefail

DEV="$HOME/Developer"
G='\033[0;32m' C='\033[0;36m' N='\033[0m'

clone() {
  local dir="$1" repo="$2"
  local target="$DEV/$dir"
  if [ -d "$target/.git" ]; then
    echo -e "  ${G}EXISTS${N} $dir"
  else
    mkdir -p "$(dirname "$target")"
    echo -e "  ${C}CLONE${N}  $dir"
    git clone "$repo" "$target"
  fi
}

echo "=== Recreating ~/Developer ==="
echo
CLONEHEAD

  # Find all git repos (up to 3 levels deep), group by top-level dir
  local current_group=""
  while IFS= read -r gitdir; do
    local repo_path="${gitdir%/.git}"
    local rel="${repo_path#$dev/}"
    local remote
    remote=$(git -C "$repo_path" remote get-url origin 2>/dev/null || true)
    [ -z "$remote" ] && continue

    # Group header
    local group="${rel%%/*}"
    if [ "$group" != "$current_group" ]; then
      current_group="$group"
      echo "" >> "$clone_script"
      echo "echo \"[$group]\"" >> "$clone_script"
    fi

    # Detect archived repos → only clone with --all
    if [[ "$rel" == _archived/* ]]; then
      # Collect archived separately
      echo "# archived: clone \"$rel\" \"$remote\"" >> "$clone_script"
    else
      echo "clone \"$rel\" \"$remote\"" >> "$clone_script"
    fi
    ((repo_count++))
  done < <(find "$dev" -maxdepth 4 -name .git -type d 2>/dev/null | sort)

  # Add --all block for archived
  local has_archived=false
  if grep -q "^# archived:" "$clone_script" 2>/dev/null; then
    has_archived=true
    cat >> "$clone_script" << 'ARCHBLOCK'

echo
if [ "${1:-}" = "--all" ]; then
  echo "[Archived]"
ARCHBLOCK
    grep "^# archived:" "$clone_script" | sed 's/^# archived: /  /' >> "$clone_script"
    echo "fi" >> "$clone_script"
    # Remove the comment lines
    sed -i '' '/^# archived:/d' "$clone_script"
  fi

  # Non-git dirs to recreate
  cat >> "$clone_script" << 'DIRSBLOCK'

echo
echo "[Directories]"
DIRSBLOCK
  for d in "$dev"/*/; do
    [ -d "$d" ] || continue
    local dirname
    dirname=$(basename "$d")
    [[ "$dirname" == .* ]] && continue  # skip hidden
    [ -d "$d/.git" ] && continue        # already a repo
    echo "mkdir -p \"\$DEV/$dirname\"" >> "$clone_script"
  done

  $has_archived && echo 'echo -e "\nRun with --all to include archived repos."' >> "$clone_script"

  chmod +x "$clone_script"
  log "Found $repo_count repos. Generated clone-repos.sh"
}

cmd_push() {
  need_dotfiles
  log "Collecting configs..."

  # Read manifest and copy sources
  while IFS='|' read -r rel target; do
    target="${target/\~/$HOME}"
    target="${target/\$HOME/$HOME}"
    if [ -e "$target" ]; then
      safe_copy "$target" "$rel"
      ok "$rel"
    fi
  done <<< "$(read_manifest)"

  # Extras: Brewfile
  if command -v brew &>/dev/null; then
    log "Dumping Brewfile (15s timeout)..."
    mkdir -p "$DOTFILES/homebrew"
    if timeout 30 brew bundle dump --file="$DOTFILES/homebrew/Brewfile" --force 2>/dev/null; then
      ok "homebrew/Brewfile"
    else
      skip "Brewfile (timed out)"
    fi
  fi

  # npm globals
  if command -v npm &>/dev/null; then
    mkdir -p "$DOTFILES/npm"
    npm list -g --depth=0 --json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for name in sorted(data.get('dependencies', {})):
    if name not in ('npm', 'corepack'): print(name)
" > "$DOTFILES/npm/globals.txt" 2>/dev/null && ok "npm/globals.txt"
  fi

  # macOS defaults
  mkdir -p "$DOTFILES/macos"
  {
    echo "#!/bin/bash"
    echo "# macOS defaults — generated $(date +%Y-%m-%d)"
    echo "defaults write NSGlobalDomain KeyRepeat -int $(defaults read NSGlobalDomain KeyRepeat 2>/dev/null || echo 2)"
    echo "defaults write NSGlobalDomain InitialKeyRepeat -int $(defaults read NSGlobalDomain InitialKeyRepeat 2>/dev/null || echo 15)"
    echo "defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool $(defaults read NSGlobalDomain ApplePressAndHoldEnabled 2>/dev/null || echo true)"
    echo "defaults write com.apple.dock autohide -bool $(defaults read com.apple.dock autohide 2>/dev/null || echo false)"
    echo "defaults write com.apple.dock show-recents -bool $(defaults read com.apple.dock show-recents 2>/dev/null || echo true)"
    echo "defaults write com.apple.finder AppleShowAllFiles -bool $(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo false)"
    echo "defaults write com.apple.finder ShowPathbar -bool $(defaults read com.apple.finder ShowPathbar 2>/dev/null || echo false)"
    echo "killall Dock Finder 2>/dev/null || true"
  } > "$DOTFILES/macos/defaults.sh"
  ok "macos/defaults.sh"

  # crontab
  crontab -l > "$DOTFILES/macos/crontab.txt" 2>/dev/null && ok "macos/crontab.txt"

  # Font list
  mkdir -p "$DOTFILES/fonts"
  ls ~/Library/Fonts/ 2>/dev/null > "$DOTFILES/fonts/installed.txt" && ok "fonts/installed.txt"

  # Re-scan repos → keep clone-repos.sh up to date
  cmd_scan 2>/dev/null

  # Git commit + push
  cd "$DOTFILES"
  if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    log "Nothing changed."
    return
  fi

  log "Changes:"
  git status --short
  git add -A
  git commit -m "sync $(date +%Y-%m-%d\ %H:%M) from $(hostname -s)"

  if git remote get-url origin &>/dev/null; then
    log "Pushing..."
    git push
    log "${G}Pushed.${N}"
  else
    log "${Y}No remote. Run: meister init${N}"
  fi
}

cmd_pull() {
  need_dotfiles
  cd "$DOTFILES"

  if git remote get-url origin &>/dev/null; then
    log "Pulling latest..."
    git pull --rebase 2>/dev/null || log "${Y}Pull failed (offline?)${N}"
  fi

  [ -f "$MANIFEST_FILE" ] || { log "${Y}No manifest.txt — run: meister scan${N}"; return; }

  log "Linking configs..."
  while IFS='|' read -r rel target; do
    target="${target/\~/$HOME}"
    target="${target/\$HOME/$HOME}"
    safe_link "$rel" "$target"
  done <<< "$(read_manifest)"

  # SSH safety
  [ -d "$HOME/.ssh" ] && chmod 700 "$HOME/.ssh"
  mkdir -p "$HOME/.ssh/sockets" 2>/dev/null

  # Homebrew check
  if [ -f "$DOTFILES/homebrew/Brewfile" ] && command -v brew &>/dev/null; then
    log "Checking Homebrew..."
    local missing
    missing=$(brew bundle check --file="$DOTFILES/homebrew/Brewfile" 2>&1 | grep -c "not installed" || true)
    [ "$missing" -gt 0 ] && log "${Y}$missing packages missing. Run: brew bundle --file=$DOTFILES/homebrew/Brewfile${N}"
  fi

  log "${G}Done.${N}"
}

cmd_clone() {
  need_dotfiles
  [ -f "$DOTFILES/clone-repos.sh" ] || die "No clone-repos.sh in dotfiles"
  bash "$DOTFILES/clone-repos.sh" "${1:-}"
}

cmd_bootstrap() {
  log "Full bootstrap..."
  echo

  cmd_pull
  echo

  # Homebrew
  if [ -f "$DOTFILES/homebrew/Brewfile" ]; then
    if command -v brew &>/dev/null; then
      log "Installing Homebrew packages..."
      brew bundle --file="$DOTFILES/homebrew/Brewfile" --force
    else
      log "${Y}Install Homebrew first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${N}"
    fi
  fi
  echo

  # npm globals
  if [ -f "$DOTFILES/npm/globals.txt" ] && command -v npm &>/dev/null; then
    log "Installing npm globals..."
    while IFS= read -r pkg; do
      [ -n "$pkg" ] && npm list -g "$pkg" &>/dev/null || npm install -g "$pkg"
    done < "$DOTFILES/npm/globals.txt"
  fi
  echo

  # Clone repos
  [ -f "$DOTFILES/clone-repos.sh" ] && cmd_clone "${1:-}"
  echo

  # macOS defaults
  if [ -f "$DOTFILES/macos/defaults.sh" ]; then
    log "Applying macOS defaults..."
    bash "$DOTFILES/macos/defaults.sh"
    ok "macOS defaults"
  fi

  # Crontab
  if [ -f "$DOTFILES/macos/crontab.txt" ]; then
    crontab "$DOTFILES/macos/crontab.txt"
    ok "Crontab restored"
  fi

  echo
  log "${G}Bootstrap complete.${N}"
}

cmd_status() {
  need_dotfiles
  [ -f "$MANIFEST_FILE" ] || { log "${Y}No manifest.txt${N}"; return; }

  log "Checking symlinks..."
  local ok_count=0 fail_count=0

  while IFS='|' read -r rel target; do
    target="${target/\~/$HOME}"
    target="${target/\$HOME/$HOME}"
    if [ -L "$target" ]; then
      local actual
      actual=$(readlink "$target")
      if [ "$actual" = "$DOTFILES/$rel" ]; then
        ok "$target"
        ((ok_count++))
      else
        fail "$target → $actual (expected $DOTFILES/$rel)"
        ((fail_count++))
      fi
    elif [ -e "$target" ]; then
      fail "$target (not a symlink)"
      ((fail_count++))
    else
      skip "$target (missing)"
      ((fail_count++))
    fi
  done <<< "$(read_manifest)"

  echo
  log "${G}$ok_count linked${N}, ${R}$fail_count issues${N}"

  echo
  cd "$DOTFILES"
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    log "${Y}Uncommitted:${N}"
    git status --short
  else
    log "Git clean."
  fi
}

cmd_edit() {
  need_dotfiles
  "${EDITOR:-nano}" "$MANIFEST_FILE"
}

# ─── Main ───

load_conf

case "${1:-help}" in
  setup|s)            cmd_setup "${2:-}" ;;
  init|i)             cmd_init "${2:-}" ;;
  scan)               cmd_scan ;;
  push|up|u)          cmd_push ;;
  pull|down|d)        cmd_pull ;;
  clone|c)            cmd_clone "${2:-}" ;;
  bootstrap|boot|b)   cmd_bootstrap "${2:-}" ;;
  status|st)          cmd_status ;;
  edit|e)             cmd_edit ;;
  version|v|-v|--version) echo "meister $VERSION" ;;
  *)
    cat << EOF
meister $VERSION — Dev environment sync

  ${C}First time:${N}
    setup [url]     Clone dotfiles + link (auto-detects repo from gh)
    init [name]     Create private GitHub repo + push
    scan            Auto-detect configs and generate manifest

  ${C}Daily:${N}
    push            Collect configs, commit, push
    pull            Pull latest, create symlinks
    status          Check what's linked

  ${C}New machine:${N}
    bootstrap       Full setup: pull + brew + npm + clone + defaults
    clone [--all]   Clone ~/Developer repos from clone-repos.sh

  ${C}Config:${N}
    edit            Open manifest.txt in \$EDITOR

  Aliases: setup=s init=i push=up=u pull=down=d clone=c bootstrap=boot=b status=st edit=e
  Config:  $CONF_FILE
  Dotfiles: $DOTFILES
EOF
    ;;
esac
