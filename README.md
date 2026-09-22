# NVIDIA-Hashcat-Installer-for-Arch-Linux

A single Bash script that installs the NVIDIA open kernel modules (DKMS), CUDA/OpenCL stack, and verifies GPU acceleration in **hashcat** on Arch Linux and Arch-based distros.

Built after hitting (and fixing) the usual chain of failures: missing `nvidia` package, DKMS build errors, `modprobe: FATAL: Module nvidia not found`, and nouveau conflicts.

## What it does

1. Detects your NVIDIA GPU via `lspci`
2. Skips reinstall if a working driver is already loaded
3. Installs matching kernel headers (`linux-headers` or `linux-lts-headers`)
4. Installs `nvidia-open-dkms` (or `nvidia-open-lts`), `nvidia-utils`, `nvidia-settings`, `opencl-nvidia`
5. Blacklists `nouveau` if it's loaded
6. Builds the DKMS module for your **exact** running kernel
7. Runs `depmod` explicitly — this fixes the common case where the module builds and installs successfully but never gets registered, because `--no-depmod` was used at some point
8. Rebuilds the initramfs
9. Attempts to hot-load the module, falling back to "reboot required" if needed
10. Installs the CUDA toolkit
11. Verifies with `nvidia-smi`
12. Verifies GPU detection with `hashcat -I`

Every step checks current state first, so the script is safe to re-run if something fails partway through (e.g. after a reboot).

## Requirements

- Arch Linux or an Arch-based distro (uses `pacman`)
- An NVIDIA GPU, Turing generation (RTX 20-series) or newer — required for the open kernel modules
- `sudo` privileges

## Usage

```bash
git clone https://github.com/BHAVAN-RBN/NVIDIA-Hashcat-Installer-for-Arch-Linux.git
cd NVIDIA-Hashcat-Installer-for-Arch-Linux
chmod +x install-nvidia-hashcat.sh
sudo ./install-nvidia-hashcat.sh
```

If the script reports that a reboot is required, reboot and run it again — it will detect the working driver and skip straight to CUDA install and verification.

## Manual verification

```bash
nvidia-smi
hashcat -I
hashcat -b -m 0    # benchmark MD5 to confirm GPU is actually cracking, not falling back to CPU
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `error: target not found: nvidia` | Arch has moved to the open kernel module line; no plain `nvidia` package for recent driver branches | Script uses `nvidia-open-dkms` instead |
| DKMS build fails with no `make.log` | Log gets wiped between runs when a fresh build starts | Script builds once, cleanly, per kernel |
| `modprobe: FATAL: Module nvidia not found` | Module built and installed, but `depmod` was skipped (commonly via a `--no-depmod` flag) | Script always runs `depmod -a` explicitly after install |
| `nvidia-smi` fails after driver install | nouveau still loaded, or reboot needed | Script blacklists nouveau and flags when a reboot is required |

## License

MIT

## Author

[bxploit (Bhavan RBN)](https://github.com/BHAVAN-RBN)
