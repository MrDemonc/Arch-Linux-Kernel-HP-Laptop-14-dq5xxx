## 🚀 linux-hp Kernel Release: {{TARGET_TAG}}

Tailored Linux kernel build optimized for **HP Laptop 14-dq5xxx (Intel Core i3-1215U Alder Lake)** for maximum battery endurance, reduced thermal throttling, and quiet fan operation.

### 📦 Version Information
* **Upstream Arch Linux Kernel:** `{{UPSTREAM_VER}}`
* **Package Base:** `linux-hp`
* **Architecture:** `x86_64` (Optimized for 12th Gen Alder Lake)
* **Target Laptop:** HP Laptop 14-dq5xxx

### ⚡ Key Optimizations Included
* **300 Hz Timer Frequency (`CONFIG_HZ_300=y`):** 70% fewer CPU wake-up interruptions compared to standard 1000 Hz, maintaining deeper package C-States (`C10`).
* **Native CPU Instruction Tuning (`CONFIG_X86_NATIVE_CPU=y`):** Native instruction set optimization for Alder Lake Golden Cove & Gracemont cores; non-Intel CPU vendor routines removed.
* **PCIe ASPM Supersave (`CONFIG_PCIEASPM_POWER_SUPERSAVE=y`):** Forces PCIe links (Realtek RTL8821CE Wi-Fi and Samsung NVMe PM9B1) into low-power states (`L1 sub-states`).
* **Intel Hybrid Scheduler & Energy Model (`CONFIG_INTEL_HFI_THERMAL=y`):** Routes background and low-priority tasks to the 4 Efficient Cores (E-cores).
* **Audio Codec Power-Down (`CONFIG_SND_HDA_POWER_SAVE_DEFAULT=1`):** Lowers audio hardware sleep delay from 10s to 1s.
* **Hardware-Tailored Drivers (`localmodconfig`):** Compiled specifically with all active hardware modules required by the HP Laptop 14-dq5xxx.

### 📥 Installation Instructions

#### Method 1: Using `install.sh` (Recommended)
Run `install.sh` and select **Option 1**:
```bash
./install.sh
```

#### Method 2: Manual pacman installation
Download the attached `.pkg.tar.zst` assets and install:
```bash
sudo pacman -U linux-hp-*.pkg.tar.zst
```
Reboot and select **`linux-hp`** in the Limine bootloader menu.
