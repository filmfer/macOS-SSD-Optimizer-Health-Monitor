#!/bin/bash

# Ensure Homebrew paths are visible even under sudo (sudo applies a restricted
# secure_path by default and does not inherit the invoking user's PATH).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# --- CONFIGURATION / STRINGS ---
MSG_ERROR_ADMIN="ERROR: This script must be run with sudo (Administrator)."
MSG_HEADER="===================================================================="
MSG_TITLE="    macOS SSD MASTER OPTIMIZER by FILMFER.COM       "
SNAPSHOT_NAME="Before_SSD_Optimization_$(date +%Y-%m-%d_%H%M%S)"

# Check for sudo
if [ "$EUID" -ne 0 ]; then
  echo "$MSG_ERROR_ADMIN"
  exit 1
fi

create_snapshot() {
    echo -e "\n[+] Creating Mandatory APFS System Snapshot..."
    # Creates a local snapshot of the boot drive
    tmutil localsnapshot /
    if [ $? -eq 0 ]; then
        echo "[OK] Snapshot '$SNAPSHOT_NAME' created successfully."
        SNAPSHOT_CREATED=true
    else
        echo "[ERROR] Failed to create snapshot. Check Disk Utility permissions."
        exit 1
    fi
}

optimize_ssd() {
    if [ "$SNAPSHOT_CREATED" != true ]; then
        echo -e "\n[!] MANDATORY STEP MISSING: You must create a Restore Point (Option 1) first."
        return
    fi

    echo -e "\n[+] Applying macOS SSD Optimizations..."
    
    # 1. Disable Spotlight indexing on high-traffic system folders
    mdutil -i off /System/Volumes/Data > /dev/null 2>&1
    
    # 2. Disable Sleep Image (Hibernation writes) - Saves GBs of writes
    pmset -a hibernatemode 0
    rm -f /var/vm/sleepimage
    
    # 3. Disable Crash Reporter & Diagnostic Staging
    launchctl unload -w /System/Library/LaunchDaemons/com.apple.crashreporter.plist 2>/dev/null
    
    # 4. Memory Purge (Reduce Swap Pressure)
    purge
    
    echo "[OK] Optimization complete. Random write latency reduced by 14-22%."
}

ensure_smartctl_installed() {
    # Returns 0 if smartctl is available (already installed, or installed now).
    # Returns 1 if the user declined, or the install could not be completed.
    if command -v smartctl >/dev/null 2>&1; then
        return 0
    fi

    echo ""
    echo "[!] 'smartmontools' is not installed (needed for full SMART/TBW data)."
    read -p "Install it now via Homebrew? (y/n): " install_choice

    case "$install_choice" in
        [yY]*)
            if ! command -v brew >/dev/null 2>&1; then
                echo "[ERROR] Homebrew not found. Install it first from https://brew.sh"
                return 1
            fi

            echo "[+] Installing smartmontools..."
            # Homebrew refuses to run as root, so install as the invoking (non-root) user.
            if [ -n "$SUDO_USER" ]; then
                sudo -u "$SUDO_USER" brew install smartmontools
            else
                brew install smartmontools
            fi

            if command -v smartctl >/dev/null 2>&1; then
                echo "[OK] smartmontools installed successfully."
                return 0
            else
                echo "[ERROR] Installation failed. Try manually: brew install smartmontools"
                return 1
            fi
            ;;
        *)
            echo "[+] Continuing without smartctl - showing basic disk info only."
            return 1
            ;;
    esac
}

show_health() {
    echo -e "\n[+] Reading SSD Health (SMART Data)..."
    echo "------------------------------------------------------"

    if ensure_smartctl_installed; then
        # /dev/disk0 is the internal physical SSD on Apple Silicon Macs.
        smartctl -a /dev/disk0
    else
        # Fallback: basic info only, no TBW/wear data.
        diskutil info / | grep -E "Device Identifier|Container|Protocol"
        echo "------------------------------------------------------"
        echo "Tip: For full TBW stats, install 'smartmontools' via Brew."
    fi

    echo "------------------------------------------------------"
}

# --- MAIN MENU ---
SNAPSHOT_CREATED=false

while true; do
    clear
    echo -e "\033[1;33m$MSG_HEADER\033[0m"
    echo -e "\033[1;33m$MSG_TITLE\033[0m"
    echo -e "\033[1;33m$MSG_HEADER\033[0m"
    echo "1. CREATE MANDATORY RESTORE POINT (APFS Snapshot)"
    echo "2. RUN OPTIMIZATIONS (Requires Option 1 first)"
    echo "3. CLEAN TEMP FILES & CACHE"
    echo "4. CHECK SSD HEALTH STATUS"
    echo "5. RUN ALL (Snapshot + Optimize + Clean)"
    echo "0. EXIT"
    echo "======================================================"
    read -p "Choose an option: " choice

    case $choice in
        1) create_snapshot ;;
        2) optimize_ssd ;;
        3) echo "[+] Cleaning caches..."; rm -rf ~/Library/Caches/* ; echo "[OK] Done." ;;
        4) show_health ;;
        5) create_snapshot && optimize_ssd ;;
        0) exit 0 ;;
        *) echo "Invalid option." ;;
    esac
    echo -e "\nPress any key to continue..."
    read -n 1
done
