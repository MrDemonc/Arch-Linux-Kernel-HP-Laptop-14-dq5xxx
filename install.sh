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
    echo ">> Applying optimizations to PKGBUILD and config.x86_64..."
    python3 - << 'EOF'
import os
import re
import subprocess

script_dir = os.getcwd()
pkgbuild_path = os.path.join(script_dir, "PKGBUILD")
config_path = os.path.join(script_dir, "config.x86_64")

# 1. Optimize config.x86_64
if os.path.exists(config_path):
    with open(config_path, "r", encoding="utf-8") as f:
        content = f.read()

    replacements = {
        "# CONFIG_X86_NATIVE_CPU is not set": "CONFIG_X86_NATIVE_CPU=y",
        "CONFIG_CPU_SUP_AMD=y": "# CONFIG_CPU_SUP_AMD is not set",
        "CONFIG_CPU_SUP_HYGON=y": "# CONFIG_CPU_SUP_HYGON is not set",
        "CONFIG_CPU_SUP_CENTAUR=y": "# CONFIG_CPU_SUP_CENTAUR is not set",
        "CONFIG_CPU_SUP_ZHAOXIN=y": "# CONFIG_CPU_SUP_ZHAOXIN is not set",
        "CONFIG_HZ_1000=y": "# CONFIG_HZ_1000 is not set\nCONFIG_HZ_300=y",
        "CONFIG_HZ=1000": "CONFIG_HZ=300",
        "CONFIG_PCIEASPM_DEFAULT=y": "# CONFIG_PCIEASPM_DEFAULT is not set\nCONFIG_PCIEASPM_POWER_SUPERSAVE=y",
        "CONFIG_SND_HDA_POWER_SAVE_DEFAULT=10": "CONFIG_SND_HDA_POWER_SAVE_DEFAULT=1",
        "CONFIG_RUST=y": "# CONFIG_RUST is not set",
    }
    for target, rep in replacements.items():
        content = content.replace(target, rep)

    lines = [l for l in content.splitlines() if l.strip() not in ["# CONFIG_HZ_300 is not set", "# CONFIG_PCIEASPM_POWER_SUPERSAVE is not set"]]
    with open(config_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("   [OK] config.x86_64 optimized (300Hz, Native CPU, ASPM Supersave, Audio 1s).")

# 2. Optimize PKGBUILD
if os.path.exists(pkgbuild_path):
    with open(pkgbuild_path, "r", encoding="utf-8") as f:
        c = f.read()

    c = re.sub(r"^pkgbase=linux\b", "pkgbase=linux-hp", c, flags=re.MULTILINE)
    c = re.sub(r"^pkgdesc='Linux'", "pkgdesc='Linux kernel tailored and optimized for HP Laptop (Alder Lake, Battery & Power Saving)'", c, flags=re.MULTILINE)

    for dep in [r"\s*rust\n", r"\s*rust-bindgen\n", r"\s*rust-src\n", r"\s*graphviz\n", r"\s*imagemagick\n", r"\s*python-sphinx\n", r"\s*python-yaml\n", r"\s*texlive-latexextra\n", r"\s*# htmldocs\n"]:
        c = re.sub(dep, "\n", c)

    c = re.sub(r"\.sign\}", "", c)
    c = re.sub(r"\.sig\}", "", c)
    c = re.sub(r"\.tar\.\{xz,sign\}", ".tar.xz", c)
    c = re.sub(r"\.patch\.zst\{,\.sig\}", ".patch.zst", c)
    c = re.sub(r"validpgpkeys=\([^)]*\)\n?", "", c)
    c = re.sub(r"\s*make htmldocs[^\n]*\n", "\n", c)
    c = re.sub(r"\s*local pid_docs=\$!\n", "\n", c)
    c = re.sub(r"\s*wait \$pid_docs\n", "\n", c)

    if "localmodconfig" not in c:
        c = c.replace("cp ../config.$CARCH .config\n", "cp ../config.$CARCH .config\n  if [[ -f ../.use_localmodconfig || \"${USE_LOCALMODCONFIG:-0}\" == \"1\" || -n \"${CI:-}\" ]]; then\n    if [[ -f ../hp-modules.list ]]; then\n      echo \"Applying localmodconfig using hp-modules.list...\"\n      yes \"\" | make LSMOD=../hp-modules.list localmodconfig\n    else\n      echo \"Applying localmodconfig (streamlining for HP laptop hardware)...\"\n      yes \"\" | make LSMOD=<(lsmod) localmodconfig\n    fi\n  fi\n")

    c = re.sub(r"_package-docs\(\) \{.*?^\}\n", "", c, flags=re.DOTALL | re.MULTILINE)
    c = re.sub(r'"\$pkgbase-docs"\n?', "", c)
    c = re.sub(r"\n\s*'SKIP'", "", c)

    # Recalculate hash for config.x86_64
    b2 = subprocess.check_output(["b2sum", config_path]).decode().split()[0]
    c = re.sub(r"b2sums_x86_64=\('[0-9a-fA-F]+'\)", f"b2sums_x86_64=('{b2}')", c)

    with open(pkgbuild_path, "w", encoding="utf-8") as f:
        f.write(c)
    print("   [OK] PKGBUILD configured with updated b2sums.")
EOF
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
    RELEASE_API="https://api.github.com/repos/$USER_REPO/releases/latest"
    RELEASE_DATA=$(curl -sL "$RELEASE_API")

    TAG_NAME=$(echo "$RELEASE_DATA" | grep -o '"tag_name": "[^"]*"' | head -n1 | cut -d'"' -f4)
    if [ -z "$TAG_NAME" ]; then
        echo "❌ Error: No release found at https://github.com/$USER_REPO/releases"
        echo "Please make sure to publish a release with .pkg.tar.zst assets attached."
        exit 1
    fi

    echo ">> Found Release: $TAG_NAME"
    
    # Extract asset URLs ending in .pkg.tar.zst
    ASSET_URLS=($(echo "$RELEASE_DATA" | grep -o '"browser_download_url": "[^"]*\.pkg\.tar\.zst"' | cut -d'"' -f4))

    if [ ${#ASSET_URLS[@]} -eq 0 ]; then
        echo "❌ Error: Release $TAG_NAME does not contain any .pkg.tar.zst packages."
        exit 1
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
    sudo pacman -U --needed ./*.pkg.tar.zst
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
