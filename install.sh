#!/usr/bin/env bash
# ==============================================================================
# Unified Installer & Manager: linux-hp
# Target Device: HP Laptop 14-dq5xxx (Intel Core i3-1215U Alder Lake)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PKGBUILD_FILE="$SCRIPT_DIR/PKGBUILD"
CONFIG_FILE="$SCRIPT_DIR/config.x86_64"
CONFIG_REPO_FILE="$SCRIPT_DIR/.github_repo"

# ------------------------------------------------------------------------------
# Function: Apply optimizations for Alder Lake and battery efficiency
# ------------------------------------------------------------------------------
apply_optimizations() {
    python3 "$SCRIPT_DIR/apply-optimizations.py"
}

# ------------------------------------------------------------------------------
# Function: Set up background update notification service
# ------------------------------------------------------------------------------
setup_background_notifier() {
    echo ""
    echo ">> Configuring background kernel update notifier..."
    
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.config/systemd/user"

    # 1. Script that checks official Arch Linux repositories for a newer kernel
    cat << 'EOF' > "$HOME/.local/bin/check-kernel-update.sh"
#!/usr/bin/env bash
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# Query latest version available in official Arch Linux package API
LATEST_JSON=$(curl -s --connect-timeout 10 https://archlinux.org/packages/core/x86_64/linux/json/ 2>/dev/null || true)
UPSTREAM_VER=$(echo "$LATEST_JSON" | grep -o '"pkgver": "[^"]*"' | head -n1 | cut -d'"' -f4)

[ -z "$UPSTREAM_VER" ] && exit 0

# Query currently installed kernel version
INSTALLED_VER=$(pacman -Q linux-hp 2>/dev/null | awk '{print $2}' | cut -d'-' -f1)
[ -z "$INSTALLED_VER" ] && INSTALLED_VER=$(pacman -Q linux 2>/dev/null | awk '{print $2}' | cut -d'-' -f1)

NOTIF_FILE="$HOME/.config/linux-hp-last-notified"
LAST_NOTIFIED=""
[ -f "$NOTIF_FILE" ] && LAST_NOTIFIED=$(cat "$NOTIF_FILE")

# Notify only if a new version is released and not yet notified
if [ -n "$INSTALLED_VER" ] && [ "$UPSTREAM_VER" != "$INSTALLED_VER" ] && [ "$UPSTREAM_VER" != "$LAST_NOTIFIED" ]; then
    notify-send -u normal -i system-software-update \
        "Arch Linux Kernel Update Available" \
        "A new official Linux version ($UPSTREAM_VER) is available. Open your linux-hp project and run ./install.sh to update."
    echo "$UPSTREAM_VER" > "$NOTIF_FILE"
fi
EOF
    chmod +x "$HOME/.local/bin/check-kernel-update.sh"

    # 2. Systemd user service
    cat << EOF > "$HOME/.config/systemd/user/check-kernel-update.service"
[Unit]
Description=Arch Linux kernel update checker
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$HOME/.local/bin/check-kernel-update.sh
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
EOF

    # 3. Systemd user timer (triggers 5 min after boot and every 12 hours)
    cat << EOF > "$HOME/.config/systemd/user/check-kernel-update.timer"
[Unit]
Description=Kernel update check timer
After=network-online.target

[Timer]
OnBootSec=5min
OnUnitActiveSec=12h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now check-kernel-update.timer
    echo "✅ Background notifier successfully configured:"
    echo "   * Script: $HOME/.local/bin/check-kernel-update.sh"
    echo "   * Schedule: Every 12 hours and 5 minutes after session login."
}

# ------------------------------------------------------------------------------
# OPTION 1: Download and install precompiled kernel from GitHub Releases
# ------------------------------------------------------------------------------
option_download_release() {
    echo "============================================================"
    echo "  DOWNLOAD & INSTALL PRECOMPILED KERNEL (GitHub Releases)"
    echo "============================================================"
    echo ""

    # Determine GitHub repository
    DEFAULT_REPO=""
    if [ -f "$CONFIG_REPO_FILE" ]; then
        DEFAULT_REPO=$(cat "$CONFIG_REPO_FILE")
    else
        ORIGIN_URL=$(git remote get-url origin 2>/dev/null || true)
        if [[ "$ORIGIN_URL" =~ github\.com[:/]([^/]+/[^/\.]+)(\.git)?$ ]]; then
            DEFAULT_REPO="${BASH_REMATCH[1]}"
        fi
    fi

    if [ -n "$DEFAULT_REPO" ]; then
        read -rp "GitHub Repository [$DEFAULT_REPO]: " USER_REPO
        USER_REPO=${USER_REPO:-$DEFAULT_REPO}
    else
        read -rp "Enter your GitHub repository (e.g. user/repo): " USER_REPO
    fi

    if [ -z "$USER_REPO" ]; then
        echo "❌ Error: GitHub repository is required."
        exit 1
    fi
    echo "$USER_REPO" > "$CONFIG_REPO_FILE"

    echo ">> Fetching latest release from github.com/$USER_REPO..."
    RELEASE_INFO=$(python3 - "$USER_REPO" << 'EOF'
import urllib.request, json, sys, os, subprocess

repo = sys.argv[1]
token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
if not token:
    try:
        token = subprocess.check_output(["gh", "auth", "token"], stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        token = ""

headers = {
    "User-Agent": "linux-hp-installer",
    "Accept": "application/vnd.github+json",
    "Cache-Control": "no-cache"
}
if token:
    headers["Authorization"] = f"token {token}"

def get_json(endpoint):
    url = f"https://api.github.com/repos/{repo}/{endpoint}"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            return json.load(resp)
    except Exception:
        return None

# 1. Primary: Query GitHub latest release endpoint
data = get_json("releases/latest")
assets = []
if data and isinstance(data, dict):
    assets = [a["browser_download_url"] for a in data.get("assets", []) if a.get("browser_download_url", "").endswith(".pkg.tar.zst")]

# 2. Fallback: Query releases list in case latest is not tagged or is a pre-release
if not assets:
    releases = get_json("releases?per_page=10")
    if releases and isinstance(releases, list):
        for rel in releases:
            rel_assets = [a["browser_download_url"] for a in rel.get("assets", []) if a.get("browser_download_url", "").endswith(".pkg.tar.zst")]
            if rel_assets:
                data = rel
                assets = rel_assets
                break

if not data or not assets:
    sys.exit(1)

tag = data.get("tag_name", "")
title = data.get("name", "") or tag
published = data.get("published_at", "")
print(f"{tag}\t{title}\t{published}\t{' '.join(assets)}")
EOF
)

    if [ -z "$RELEASE_INFO" ]; then
        echo "❌ Error: Could not find any valid release with .pkg.tar.zst packages in $USER_REPO."
        echo "Please verify https://github.com/$USER_REPO/releases"
        exit 1
    fi

    IFS=$'\t' read -r TAG_NAME RELEASE_TITLE PUBLISHED_DATE ASSETS_RAW <<< "$RELEASE_INFO"
    IFS=' ' read -r -a ASSET_URLS <<< "$ASSETS_RAW"

    echo ">> Found Release: $TAG_NAME ($RELEASE_TITLE)"
    [ -n "$PUBLISHED_DATE" ] && echo "   Published at: $PUBLISHED_DATE"
    INSTALLED_VER=$(pacman -Q linux-hp 2>/dev/null || true)
    if [ -n "$INSTALLED_VER" ]; then
        echo "   Currently installed: $INSTALLED_VER"
    fi

    mkdir -p "$SCRIPT_DIR/downloads"
    cd "$SCRIPT_DIR/downloads"
    rm -f *.pkg.tar.zst

    for url in "${ASSET_URLS[@]}"; do
        file_name=$(basename "$url")
        echo ">> Downloading $file_name..."
        curl -L --progress-bar -o "$file_name" "$url"
    done

    echo ""
    echo ">> Installing downloaded packages with pacman..."
    sudo pacman -U ./*.pkg.tar.zst
    cd "$SCRIPT_DIR"

    # Set up background update notifier
    setup_background_notifier

    echo ""
    echo "============================================================"
    echo "  ✅ KERNEL INSTALLED SUCCESSFULLY FROM GITHUB RELEASES"
    echo "  Reboot your laptop ('reboot') and select linux-hp in Limine."
    echo "============================================================"
}

# ------------------------------------------------------------------------------
# OPTION 2: Compile from source (latest version)
# ------------------------------------------------------------------------------
option_compile_source() {
    echo "============================================================"
    echo "  COMPILE KERNEL FROM SOURCE (Latest Version)"
    echo "============================================================"
    echo ""

    # 1. Check required build tools
    MISSING_DEPS=()
    for dep in bc pahole; do
        if ! pacman -Q "$dep" &>/dev/null; then
            MISSING_DEPS+=("$dep")
        fi
    done
    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
        echo ">> Installing required build tools (${MISSING_DEPS[*]})..."
        sudo pacman -S --needed "${MISSING_DEPS[@]}"
    fi

    # 2. Check for newer upstream Arch Linux kernel releases
    echo ">> Checking for official Arch Linux updates..."
    git fetch https://gitlab.archlinux.org/archlinux/packaging/packages/linux.git main 2>/dev/null || true
    
    UPSTREAM_HASH=$(git rev-parse FETCH_HEAD 2>/dev/null || echo "")
    if [ -n "$UPSTREAM_HASH" ]; then
        UPSTREAM_VER=$(git show "$UPSTREAM_HASH:PKGBUILD" 2>/dev/null | grep -E '^pkgver=' | cut -d= -f2 || true)
        CURRENT_VER=$(grep -E '^pkgver=' PKGBUILD 2>/dev/null | cut -d= -f2 || true)
        
        if [ -n "$UPSTREAM_VER" ] && [ "$UPSTREAM_VER" != "$CURRENT_VER" ]; then
            echo "🔔 New official version available in Arch Linux ($UPSTREAM_VER)!"
            echo ">> Updating base tree..."
            git checkout "$UPSTREAM_HASH" -- PKGBUILD config.x86_64 2>/dev/null || true
            rm -f linux-hp-*.pkg.tar.zst
            rm -rf pkg src
        else
            echo "ℹ️  Source tree is up to date ($CURRENT_VER)."
        fi
    fi

    # 3. Apply hardware optimizations
    apply_optimizations

    # 4. Compilation mode selection
    echo ""
    echo "Select compilation mode:"
    echo "  1) Fast (Recommended): Uses 'localmodconfig' tailored to your"
    echo "     HP laptop's active hardware (Wi-Fi, Bluetooth, Intel GPU, NVMe, Audio, etc.)."
    echo "     -> Estimated time: ~15 to 25 minutes."
    echo ""
    echo "  2) Full: Compiles all upstream modules with full driver coverage."
    echo "     -> Estimated time: ~1.5 to 2 hours."
    echo ""
    read -rp "Choice [1 or 2] (default 1): " MODE_CHOICE
    MODE_CHOICE=${MODE_CHOICE:-1}

    if [ "$MODE_CHOICE" = "1" ]; then
        echo ">> Mode: FAST (localmodconfig)"
        touch .use_localmodconfig
    else
        echo ">> Mode: FULL (all modules)"
        rm -f .use_localmodconfig
    fi

    # 5. Compilation using all CPU threads
    CORES=$(nproc)
    export MAKEFLAGS="-j${CORES}"
    echo ">> Compiling using ${CORES} threads..."
    makepkg -s --force

    echo ""
    echo "============================================================"
    echo "  ✅ BUILD COMPLETED SUCCESSFULLY!"
    echo "============================================================"
    echo ""
    ls -lh linux-hp-*.pkg.tar.zst 2>/dev/null || true
    echo ""
    read -rp "Install the compiled packages now? [Y/n]: " INSTALL_NOW
    INSTALL_NOW=${INSTALL_NOW:-Y}

    if [[ "$INSTALL_NOW" =~ ^[Yy]$ ]]; then
        sudo pacman -U linux-hp-*.pkg.tar.zst
        setup_background_notifier
        echo ""
        echo "Reboot your laptop ('reboot') to run the new kernel."
    else
        echo "You can install the packages manually whenever you want using:"
        echo "   sudo pacman -U linux-hp-*.pkg.tar.zst"
    fi
}

# ------------------------------------------------------------------------------
# Function: Completely remove background notifier from the system
# ------------------------------------------------------------------------------
remove_background_notifier() {
    echo ">> Stopping and disabling background notifier..."
    systemctl --user stop check-kernel-update.timer check-kernel-update.service 2>/dev/null || true
    systemctl --user disable check-kernel-update.timer 2>/dev/null || true

    echo ">> Removing notification script and systemd units..."
    rm -f "$HOME/.local/bin/check-kernel-update.sh"
    rm -f "$HOME/.config/systemd/user/check-kernel-update.service"
    rm -f "$HOME/.config/systemd/user/check-kernel-update.timer"
    rm -f "$HOME/.config/linux-hp-last-notified"

    systemctl --user daemon-reload
    systemctl --user reset-failed 2>/dev/null || true
    echo "✅ Background notifier completely removed from the system."
}

# ------------------------------------------------------------------------------
# OPTION 3: Manage background update notifications
# ------------------------------------------------------------------------------
option_manage_notifier() {
    echo "============================================================"
    echo "  BACKGROUND UPDATE NOTIFICATION MANAGER"
    echo "============================================================"
    echo ""
    echo "  1) Install / Enable background notifier (systemd user timer)"
    echo "  2) Send a test desktop notification right now"
    echo "  3) Disable background notifier (keep files)"
    echo "  4) Remove background notifier completely from system"
    echo ""
    read -rp "Select an option [1-4]: " NOTIF_CHOICE

    case "$NOTIF_CHOICE" in
        1)
            setup_background_notifier
            ;;
        2)
            echo ">> Sending test notification..."
            notify-send -u normal -i system-software-update \
                "linux-hp Notifier Test" \
                "The background update notification service is working properly."
            echo "✅ Test notification sent. Check your desktop screen."
            ;;
        3)
            echo ">> Disabling timer..."
            systemctl --user disable --now check-kernel-update.timer 2>/dev/null || true
            echo "✅ Background notifier disabled."
            ;;
        4)
            remove_background_notifier
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
}

# ------------------------------------------------------------------------------
# MAIN MENU
# ------------------------------------------------------------------------------
echo "============================================================"
echo "       OPTIMIZED KERNEL MANAGER: linux-hp"
echo "  HP Laptop 14-dq5xxx (Intel Core i3-1215U Alder Lake)"
echo "============================================================"
echo ""
echo "  1) Download precompiled kernel and install (GitHub Releases)"
echo "  2) Compile from source (latest optimized version)"
echo "  3) Configure background update notifications"
echo ""
read -rp "Select an option [1, 2, or 3]: " MAIN_CHOICE

case "$MAIN_CHOICE" in
    1)
        option_download_release
        ;;
    2)
        option_compile_source
        ;;
    3)
        option_manage_notifier
        ;;
    *)
        echo "Invalid option. Please run ./install.sh again."
        exit 1
        ;;
esac
