#!/usr/bin/env bash
#
# install-nvidia-hashcat.sh
#
# Installs NVIDIA open kernel modules (nvidia-open-dkms) + CUDA/OpenCL
# stack on Arch Linux, and verifies GPU acceleration works in hashcat.
#
# Author:  bxploit (Bhavan RBN) - github.com/BHAVAN-RBN
# License: MIT
#
# Usage:
#   chmod +x install-nvidia-hashcat.sh
#   sudo ./install-nvidia-hashcat.sh
#
# Safe to re-run: every step checks current state before acting.

set -euo pipefail

# ---------------------------------------------------------------------------
# Config / constants
# ---------------------------------------------------------------------------
LOG_FILE="/var/log/nvidia-hashcat-installer.log"
KERNEL="$(uname -r)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
C_RESET='\033[0m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_BLUE='\033[1;34m'

log()   { echo -e "${C_BLUE}[*]${C_RESET} $*" | tee -a "$LOG_FILE"; }
ok()    { echo -e "${C_GREEN}[OK]${C_RESET} $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${C_YELLOW}[!]${C_RESET} $*" | tee -a "$LOG_FILE"; }
fail()  { echo -e "${C_RED}[FAIL]${C_RESET} $*" | tee -a "$LOG_FILE"; exit 1; }

banner() {
    echo -e "${C_GREEN}"
    cat <<'EOF'
                    -`
                   .o+`
                  `ooo/
                 `+oooo:
                `+oooooo:
                -+oooooo+:
              `/:-:++oooo+:
             `/++++/+++++++:
            `/++++++++++++++:
           `/+++o oooooooo/`      NVIDIA-HASHCAT-ARCH-INSTALLER
          ./ooosssso++osssssso+`
         .oossssso-````/ossssss+`
        -osssssso.      :ssssssso.
       :osssssss/        osssso+++.
      /ossssssss/        +ssssooo/-
    `/ossssso+/:-        -:/+osssso+-
   `+sso+:-`                 `.-/+oso:
  `++:.                           `-/+/
  .`                                 `/
EOF
    echo -e "${C_RESET}"
    echo -e "  ${C_GREEN}⚡ NVIDIA driver + CUDA/OpenCL, verified against hashcat 💀${C_RESET}"
    echo -e "  ${C_GREEN}🖥️  by bxploit (Bhavan RBN)  —  github.com/BHAVAN-RBN${C_RESET}"
    echo
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        fail "Run this script with sudo: sudo ./install-nvidia-hashcat.sh"
    fi
}

require_arch() {
    if ! command -v pacman &>/dev/null; then
        fail "pacman not found. This script targets Arch Linux and Arch-based systems only."
    fi
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

detect_gpu() {
    log "Detecting NVIDIA GPU..."
    if ! lspci | grep -qi nvidia; then
        fail "No NVIDIA GPU detected via lspci. Aborting."
    fi
    GPU_NAME="$(lspci | grep -i nvidia | grep -i vga | head -n1 || true)"
    ok "Found: ${GPU_NAME:-NVIDIA device present}"
}

check_existing_driver() {
    log "Checking for an already-working driver..."
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        ok "nvidia-smi already works. Driver is loaded and functional."
        SKIP_DRIVER_INSTALL=1
    else
        SKIP_DRIVER_INSTALL=0
    fi
}

blacklist_nouveau() {
    if lsmod | grep -q '^nouveau'; then
        warn "nouveau is currently loaded — it conflicts with the NVIDIA driver."
        log "Blacklisting nouveau..."
        echo "blacklist nouveau" > /etc/modprobe.d/blacklist-nouveau.conf
        NEEDS_REBUILD=1
        warn "nouveau will remain loaded until you reboot."
    else
        ok "nouveau is not loaded. Nothing to blacklist."
    fi
}

install_headers() {
    log "Installing matching kernel headers for ${KERNEL}..."
    if [[ "$KERNEL" == *lts* ]]; then
        pacman -S --needed --noconfirm linux-lts-headers
    else
        pacman -S --needed --noconfirm linux-headers
    fi
    ok "Kernel headers installed/up to date."
}

install_driver_packages() {
    log "Installing NVIDIA open kernel modules (DKMS) + userspace utils..."
    # Arch has moved to nvidia-open / nvidia-open-dkms as the maintained
    # line for recent driver branches — the old plain "nvidia" package is
    # version-locked to one exact kernel and frequently unavailable.
    local dkms_pkg="nvidia-open-dkms"
    if [[ "$KERNEL" == *lts* ]]; then
        dkms_pkg="nvidia-open-lts"
    fi

    pacman -S --needed --noconfirm \
        "$dkms_pkg" \
        nvidia-utils \
        nvidia-settings \
        opencl-nvidia

    ok "Driver packages installed."
}

install_cuda() {
    log "Installing CUDA toolkit (required for full hashcat GPU performance)..."
    pacman -S --needed --noconfirm cuda
    ok "CUDA installed."
}

build_dkms_module() {
    log "Building DKMS module for kernel ${KERNEL}..."

    local pkgver
    pkgver="$(pacman -Q nvidia-open-dkms 2>/dev/null | awk '{print $2}' | cut -d- -f1 || true)"
    if [[ -z "$pkgver" ]]; then
        pkgver="$(pacman -Q nvidia-open-lts 2>/dev/null | awk '{print $2}' | cut -d- -f1 || true)"
    fi
    if [[ -z "$pkgver" ]]; then
        fail "Could not determine installed nvidia-open-dkms version."
    fi

    # IMPORTANT: do NOT pass --no-depmod here. Skipping depmod is what
    # leaves the built module out of modules.dep, causing
    # "modprobe: FATAL: Module nvidia not found" even after a
    # successful-looking build.
    if dkms status | grep -q "nvidia/${pkgver}.*${KERNEL}.*installed"; then
        ok "DKMS module already built and installed for this kernel."
    else
        log "Running: dkms install nvidia/${pkgver} -k ${KERNEL}"
        if ! dkms install "nvidia/${pkgver}" -k "$KERNEL"; then
            fail "DKMS build failed. Check /var/lib/dkms/nvidia/${pkgver}/build/make.log"
        fi
        ok "DKMS module built and installed."
    fi

    # Always re-run depmod explicitly. This is the fix for the case where
    # a prior manual run used --no-depmod and left modules.dep stale.
    log "Refreshing modules.dep with depmod..."
    depmod -a "$KERNEL"

    if grep -q "nvidia\.ko" "/usr/lib/modules/${KERNEL}/modules.dep" 2>/dev/null \
       || grep -rq "nvidia\.ko" "/lib/modules/${KERNEL}/modules.dep" 2>/dev/null; then
        ok "nvidia module registered in modules.dep."
    else
        fail "nvidia module still missing from modules.dep after depmod. Check DKMS build log."
    fi
}

rebuild_initramfs() {
    log "Regenerating initramfs..."
    mkinitcpio -P
    ok "initramfs rebuilt."
}

load_module_now() {
    log "Attempting to load the nvidia module without reboot..."
    if modprobe nvidia 2>>"$LOG_FILE"; then
        ok "nvidia module loaded successfully."
    else
        warn "Could not hot-load the module (common if nouveau was just blacklisted). A reboot is required."
        NEEDS_REBOOT=1
    fi
}

verify_driver() {
    log "Verifying with nvidia-smi..."
    if nvidia-smi &>/dev/null; then
        nvidia-smi
        ok "Driver is working."
    else
        warn "nvidia-smi did not succeed yet. If nouveau was blacklisted or the module was hot-loaded, reboot now and re-run this script to verify."
        NEEDS_REBOOT=1
    fi
}

verify_hashcat() {
    if ! command -v hashcat &>/dev/null; then
        warn "hashcat is not installed. Install it with: sudo pacman -S hashcat"
        return
    fi
    log "Checking hashcat device detection..."
    hashcat -I || warn "hashcat -I failed to run cleanly."
}

summary() {
    echo
    echo "======================================================================"
    if [[ "${NEEDS_REBOOT:-0}" -eq 1 || "${NEEDS_REBUILD:-0}" -eq 1 ]]; then
        warn "A REBOOT IS REQUIRED to finish loading the driver."
        echo "    After reboot, run: nvidia-smi   and   hashcat -I"
    else
        ok "Setup complete. GPU should be visible to nvidia-smi and hashcat."
    fi
    echo "Full log: ${LOG_FILE}"
    echo "======================================================================"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    : > "$LOG_FILE"
    banner
    require_root
    require_arch
    detect_gpu
    check_existing_driver

    if [[ "$SKIP_DRIVER_INSTALL" -eq 0 ]]; then
        install_headers
        install_driver_packages
        blacklist_nouveau
        build_dkms_module
        rebuild_initramfs
        load_module_now
    else
        log "Driver already functional — skipping install, just verifying CUDA/hashcat."
    fi

    install_cuda
    verify_driver
    verify_hashcat
    summary
}

main "$@"
