# Meister

**macOS Maintenance, Self-Healing & Dotfiles Sync**

One command to keep your Mac healthy, your configs synced, and your network monitored.

```
brew tap maf4711/meister
brew install meister
```

---

## How It Works

Meister runs in three modes:

1. **Auto-Detect** (default) — analyzes your Mac and enables only the modules that are needed
2. **Manual Flags** — force specific modules with `-X`, `-T`, `-C`, etc.
3. **Interactive Tools** — standalone commands like `meister sniff`, `meister speed`, `meister wifi`

Every maintenance run produces a summary report with SUCCESS, FIXED, WARN, and ERROR counts. All output is logged to `~/.meister/meister.log`.

---

## Maintenance Modules

Run with `meister` (auto-detect) or `meister -a` (all modules).

### Homebrew

Updates Homebrew, upgrades outdated formulae and casks, runs `brew cleanup` and `brew autoremove`. Detects broken installs and attempts repair.

### App Store

Checks for available macOS App Store updates via `mas`. Lists outdated apps and reports update status.

### Ollama Models

Manages local Ollama LLM models. Updates installed models, removes unused ones (configurable keep-list), and ensures the AI-Heal model is available.

### macOS System

Checks for pending macOS software updates. Reports disk usage and Time Machine snapshot status.

### Cleanup (`-T` Trash, `-C` Caches, `-X` Xcode)

- **Trash**: Empties user trash when above configurable thresholds
- **Caches**: Clears user and system caches (npm, pip, yarn, gem, Homebrew, CocoaPods, SPM)
- **Xcode**: Removes DerivedData when above threshold (default: 500 MB)

### Deep Clean

14 sub-tasks including:

- Package manager caches (npm, pip, yarn, gem, Homebrew)
- Development caches (CocoaPods, SPM, Carthage)
- Parallels VM logs
- Font and QuickLook cache rebuild
- Docker cleanup (images, volumes, build cache)
- Orphaned preference files (backed up before removal)

### Spotlight Fix

Automatic Spotlight health diagnosis and repair:

- Detects stuck or high-CPU `mds` processes (threshold: 30%)
- Rebuilds Spotlight index on error
- Excludes development directories from indexing
- All thresholds configurable via `~/.meister/config`

### iCloud Fix

Automatic iCloud sync diagnosis and repair:

- Detects and removes empty ghost folders in `$HOME`
- Scans for corrupt iCloud stubs (65535 hardlink count)
- Restarts `bird` daemon on sync issues
- Reports orphaned CloudKit containers
- Configurable safety switch for stub deletion

### Performance Tuning (`-P`)

8 optimizations including:

- Spotlight exclusions for development directories
- Disable unnecessary user LaunchAgents (configurable pattern list)
- Clean unused Ollama models
- All operations respect dry-run mode

### Git Repository Management (`-G`)

- Scans `~/Documents` and `~/Developer` for Git repos (configurable paths/depth)
- Auto-pushes unpushed commits to remote
- Reports dirty working trees
- Detects repos with no remote configured

### Security Suite

Three-layer security audit:

- **XProtect**: Verifies XProtect, Gatekeeper, SIP, and FileVault status. Auto-enables Firewall and Gatekeeper when possible.
- **Persistence Audit**: Scans LaunchAgents and LaunchDaemons for unsigned or suspicious entries.
- **TCC Audit**: Checks privacy permission grants (Full Disk Access, Camera, Microphone, etc.)

### Benchmark

System benchmark and security audit (runs once per day):

- **CPU**: Pi calculation (1000 digits)
- **Disk I/O**: Sequential write and read (256 MB)
- **Network**: Latency, DNS resolution, download speed
- **Memory**: Usage, pressure level, swap
- **Security**: FileVault, Firewall, Gatekeeper, SIP status with auto-fix
- **System Info**: Uptime, load average, thermal, battery health
- Results stored as JSON in `~/.meister/benchmarks/`

### Sudo Tasks (`-S`)

Runs macOS periodic maintenance scripts (`daily`, `weekly`, `monthly`) and flushes the DNS cache.

---

## AI Self-Healing

When a module fails and no known fix exists, Meister asks a local Ollama LLM for a repair suggestion:

```
Module failed → Known fix? → Yes → Apply → Retry
                           → No  → Ask Ollama → Safety check → Apply → Retry
```

- Default model: `qwen3-coder:30b` (configurable)
- Fallback model: `llama3:latest`
- **Safety check** blocks dangerous commands (`rm -rf /`, `mkfs`, `dd`, etc.)
- All AI-suggested fixes are logged to `~/.meister/heal.log`
- Ollama is auto-started if offline and auto-stopped if Meister started it

---

## Interactive Tools

Standalone commands that run independently of the maintenance pipeline.

### `meister sniff [interval]`

Live terminal network monitor. Refreshes every N seconds (default: 3).

- Bandwidth IN/OUT on physical interface (en0/en1), with VPN detection
- Established and listening connection counts
- Top 10 processes by connection count
- Top 8 remote hosts by connection count

### `meister disk [directory]`

Disk space analyzer with proportional bar chart. Defaults to `$HOME`.

- Top 25 directories sorted by size
- Visual bar chart scaled relative to the largest entry
- Total disk usage summary

### `meister ports`

Lists all open ports with the process that owns them.

- Port number, protocol, process name, PID
- Known port labels (SSH, HTTP, Postgres, Redis, etc.)
- Total listening port count

### `meister dns`

DNS leak test and resolver diagnostics.

- Configured DNS servers
- Resolution test against 4 domains with response time
- VPN leak detection (checks if DNS goes through private range)
- External IP display

### `meister battery`

Battery health report for MacBooks.

- Charge level, remaining time, charging status
- Maximum capacity, cycle count, condition
- Battery temperature (from SMC)
- Health assessment based on cycle count

### `meister startup`

Audit of login items, LaunchAgents, and LaunchDaemons.

- User login items (from System Events)
- User LaunchAgents with loaded/unloaded status
- System LaunchAgents (third-party highlighted)
- System LaunchDaemons (third-party only, Apple filtered out)
- Summary count

### `meister wifi`

Wi-Fi diagnostics using `system_profiler`.

- SSID, PHY mode (802.11ax/be), channel, TX rate, MCS index
- Security type (WPA2/WPA3)
- Signal strength (RSSI), noise floor, SNR
- Signal quality bar (Excellent/Good/Fair/Weak)
- Nearby networks with channel and signal info

### `meister top [interval]`

Live process monitor. Refreshes every N seconds (default: 3).

- System load average, total CPU usage, memory pressure
- Top 10 processes by CPU usage
- Top 10 processes by memory (RSS in MB)
- Top 5 energy consumers

### `meister certs [host ...]`

SSL certificate checker. Defaults to github.com, google.com, apple.com, localhost.

- Days until expiration for each host
- Certificate issuer
- Status: OK, EXPIRING (<30 days), EXPIRED, UNREACHABLE
- Local keychain scan for certificates expiring within 30 days

### `meister thermal [interval]`

Live temperature and fan monitor. Refreshes every N seconds (default: 2).

- Battery temperature (Apple Silicon)
- Thermal throttle status
- Fan speed (RPM) or passive cooling indicator
- CPU load and core count
- Memory pressure

### `meister speed`

Network speed test using Cloudflare endpoints.

- Latency to 1.1.1.1, 8.8.8.8, apple.com
- Download: 3 runs of 10 MB, reports best result
- Upload: 10 MB to Cloudflare
- Summary in Mbps

---

## Dotfiles Sync

Manages dotfiles across machines via a private GitHub repository.

### `meister setup`

Full first-time setup for a new Mac:

1. Installs Homebrew (if missing)
2. Installs `gh` CLI
3. Generates ED25519 SSH key
4. Authenticates with GitHub (SSH + signing key)
5. Clones dotfiles repo
6. Creates symlinks for all managed configs

### `meister push`

Collects config changes, commits, and pushes to GitHub.

### `meister pull`

Pulls latest changes and recreates symlinks.

### `meister bootstrap`

Full machine setup: pull + Homebrew bundle + npm globals + clone repos + macOS defaults.

### `meister status`

Checks all symlinks, SSH key presence, and GitHub auth status.

### Managed Configs

| Config | Path |
|--------|------|
| Claude Code | `~/.claude/CLAUDE.md`, `settings.json`, `skills/`, `hooks/`, `commands/`, `agents/` |
| Gemini | `~/.gemini/GEMINI.md`, `settings.json` |
| Codex | `~/.codex/config.toml` |
| Git | `~/.gitconfig` |
| SSH | `~/.ssh/config` |
| Zsh | `~/.zshrc` |
| Ghostty | `~/.config/ghostty/config` |
| Atuin | `~/.config/atuin/config.toml` |

---

## Configuration

All settings are configurable via `~/.meister/config`. Example:

```ini
# Thresholds
DISK_USAGE_THRESHOLD=80
LARGE_FILE_SIZE_MB=1000
AUTO_XCODE_THRESHOLD_MB=500
AUTO_TRASH_THRESHOLD_ITEMS=50
AUTO_CACHE_THRESHOLD_MB=5000

# Deep Clean toggles
CLEAN_PKG_CACHES=true
CLEAN_DEV_CACHES=true
CLEAN_DOCKER=true
CLEAN_FONT_CACHE=true

# Spotlight
SPOTLIGHT_FIX_ENABLED=true
SPOTLIGHT_MDS_CPU_THRESHOLD=30

# iCloud
ICLOUD_FIX_ENABLED=true
ICLOUD_STUBS_DELETE=false

# Performance
PERF_SPOTLIGHT_EXCLUDE=true
PERF_DISABLE_AGENTS=true
PERF_CLEAN_OLLAMA=true
OLLAMA_KEEP_MODELS="qwen3-coder:30b llama3.2:latest"

# Security
SECURITY_PERSISTENCE_AUDIT=true
SECURITY_TCC_AUDIT=true

# Git
GIT_AUTO_PUSH=true
GIT_REPO_SEARCH_PATHS="$HOME/Documents $HOME/Developer"
GIT_REPO_MAXDEPTH=5

# AI Self-Healing
OLLAMA_MODEL="qwen3-coder:30b"
OLLAMA_FALLBACK_MODEL="llama3:latest"

# LaunchAgent
LAUNCHAGENT_SCHEDULE=weekly
```

---

## Flags Reference

| Flag | Description |
|------|-------------|
| (none) | Auto-detect mode |
| `-a` | Force all modules |
| `-n` | Dry-run (no changes) |
| `-q` | Quiet (warnings and fixes only) |
| `-H` | Health dashboard |
| `-I` | Install LaunchAgent for scheduled runs |
| `-X` | Clean Xcode DerivedData |
| `-T` | Empty trash |
| `-S` | Run sudo tasks (periodic scripts, DNS flush) |
| `-C` | Clean user and system caches |
| `-L` | List large files (>1 GB) |
| `-P` | Performance tuning |
| `-G` | Git repository management |
| `-N` | Network sniff module in maintenance run |

---

## Scheduled Runs

Install a LaunchAgent for automatic maintenance:

```
meister -I
```

Runs on the configured schedule (default: weekly). The LaunchAgent is installed at `~/Library/LaunchAgents/com.meister.maintenance.plist`.

---

## Requirements

- macOS 13+ (Ventura or later)
- Homebrew
- Ollama (optional, for AI Self-Healing)

---

## Files

| Path | Purpose |
|------|---------|
| `~/.meister/config` | Configuration overrides |
| `~/.meister/meister.log` | Run log (rotated at 1 MB, 3 generations) |
| `~/.meister/heal.log` | AI Self-Healing log |
| `~/.meister/history.log` | Run history |
| `~/.meister/benchmarks/` | Benchmark results (JSON) |
| `~/.meister/patches/` | Self-healing patches |

---

## License

GPL-3.0
