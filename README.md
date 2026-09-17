# Optimized Linux Kernel for HP Laptop 14-dq5xxx (Alder Lake)

A custom, tailored Linux kernel build (`linux-hp`) engineered for **maximum battery life, power efficiency, reduced thermal output, and quiet fan operation** on HP laptops powered by Intel 12th Gen Alder Lake hybrid processors.

---

## 💻 Hardware Target & Specifications

* **Laptop:** HP Laptop 14-dq5xxx
* **CPU:** Intel Core i3-1215U (12th Gen Alder Lake)
  * **2 Performance Cores (Golden Cove)** with Hyper-Threading (4 high-performance threads).
  * **4 Efficient Cores (Gracemont)** single-threaded (4 ultra-low-power threads).
  * Native instruction set support for `x86-64-v3` (AVX2, FMA3, BMI2, VAES, VPCLMULQDQ).
* **Graphics:** Intel Alder Lake-UP3 GT1 UHD Graphics (`i915` driver).
* **Wireless:** Realtek RTL8821CE 802.11ac PCIe Wi-Fi (`rtw88_8821ce`).
* **Storage:** Samsung PM9B1 NVMe SSD (supports autonomous power-state transitions / APST).

---

## ⚡ Applied Kernel Optimizations

1. **Targeted Alder Lake Microarchitecture (`-march=alderlake`):**
   * Compiles machine code specifically tuned for Intel 12th Gen Golden Cove (P-cores) and Gracemont (E-cores).
   * Strips out redundant CPU vendor routines for unsupported hardware (`AMD`, `Hygon`, `Centaur`, `Zhaoxin`).
   * Delivers faster cryptographic operations (LUKS encryption) and filesystem compression (Btrfs) with fewer CPU clock cycles per instruction.

2. **1000 Hz Hybrid Scheduler & Intel Thread Director (`CONFIG_HZ_1000=y`):**
   * Rapid 1 ms timer ticks provide optimal coordination with Intel Thread Director and Hardware Feedback Interface (HFI).
   * Ensures smooth, instant thread migration between P-cores and E-cores without scheduling stalls or deep C-state wake timeouts during heavy multithreaded compilation.

3. **Balanced PCIe ASPM Stability (`CONFIG_PCIEASPM_DEFAULT=y`):**
   * Prevents PCIe bus desynchronization and AER errors on the Realtek RTL8821CE Wi-Fi card, while maintaining NVMe autonomous power-state transitions (APST).

4. **Rapid Audio Codec Power-Down (`CONFIG_SND_HDA_POWER_SAVE_DEFAULT=1`):**
   * Suspends the Intel HD audio codec after 1 second of audio silence (compared to 10 seconds default).

5. **Intel Hybrid Scheduler & Energy Model (`CONFIG_INTEL_HFI_THERMAL=y`, `CONFIG_ENERGY_MODEL=y`):**
   * Coordinates with Intel Thread Director and Hardware Feedback Interface (HFI) to prioritize routing background tasks (audio streaming, file indexing, browser background tabs) to the 4 low-power **E-cores**, keeping power-hungry **P-cores** asleep.

6. **Gaming & Low-Latency Enhancements:**
   * **TCP BBRv3 as Default (`CONFIG_TCP_CONG_BBR=y`, `CONFIG_DEFAULT_BBR=y`):** Replaces legacy Cubic with Google's BBR congestion control, reducing ping fluctuations and bufferbloat in online gaming.
   * **Transparent Huge Pages on Madvise (`CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y`):** Eliminates `kcompactd` memory compaction stuttering during gameplay while granting 2 MB huge pages to Proton and Wine on demand.
   * **Windows NT Fast Synchronization (`CONFIG_NTSYNC=m`):** In-kernel Windows NT synchronization primitives that dramatically lower CPU locking overhead in multi-threaded games running through Steam Proton.
   * **Dynamic Extensible Schedulers (`CONFIG_SCHED_CLASS_EXT=y`):** Out-of-the-box support for cutting-edge BPF gaming schedulers like `scx_lavd`.

7. **Lean & Streamlined Build:**
   * Documentation building (Sphinx/LaTeX) is stripped to eliminate bloated build dependencies.
   * Optional **Fast Mode (`localmodconfig`)** trims unneeded enterprise and server drivers, compiling in **~15–25 minutes** instead of 2 hours.

---

## 🛡️ Coexistence & Safety Guarantee (Instant Rollback)

> [!IMPORTANT]
> **This kernel DOES NOT overwrite or replace your original kernel.**
> * It is packaged independently as **`linux-hp`** and **`linux-hp-headers`**.
> * The stock Arch Linux kernel (`linux` and `linux-fallback`) remains **100% untouched**.
> * The bootloader (**Limine**) automatically registers both kernels and displays them in the boot menu side-by-side.

### How to rollback if needed?
1. Reboot the laptop.
2. In the Limine bootloader menu, use the arrow keys to select **Arch Linux** (or your original kernel).
3. Your system boots immediately with the standard kernel.
4. To remove the custom kernel at any time:
   ```bash
   sudo pacman -R linux-hp linux-hp-headers
   ```

---

## 🚀 Unified Management: `install.sh`

All tasks (downloading releases, compiling from source, updates, notifications, and bootloader management) are unified into a single script: [`install.sh`](file:///home/demonc/Documentos/github/Arch-Linux-Kernel-HP-Laptop-14-dq5xxx/install.sh).

```bash
cd /home/demonc/Documentos/github/Arch-Linux-Kernel-HP-Laptop-14-dq5xxx
./install.sh
```

The interactive menu presents **4 options**:

### 1️⃣ Download precompiled kernel and install (GitHub Releases)
* Quickly install without spending time or battery compiling.
* Automatically queries the **Releases** section of your GitHub repository, downloads the latest `.pkg.tar.zst` packages, and installs them with `pacman`.
* Registers `linux-hp` in Limine as the default boot entry and synchronizes configurations.
* Automatically sets up the background update notifier.

### 2️⃣ Compile from source (Latest upstream version)
* Checks for newly released kernel versions from official Arch Linux upstream.
* Automatically updates the source tree and re-applies all Alder Lake and battery optimizations.
* Lets you choose between **Fast Mode** (~15 min with `localmodconfig`) or **Full Mode**.
* Installs the generated packages, configures Limine as default, and enables the background update notifier.

### 3️⃣ Configure background update notifications
* Configures a lightweight `systemd` user timer (`~/.config/systemd/user/check-kernel-update.timer`).
* Silently checks the official Arch Linux package API every 12 hours (and 5 minutes after system boot).
* Sends a native desktop notification (`notify-send`) when a newer official kernel is released, reminding you to run `./install.sh`.
* Includes options to:
  * **Install / Re-enable** the notification service (recreates all required files if missing).
  * **Test** sending an instant desktop notification.
  * **Disable** the timer temporarily.
  * **Completely remove** all notifier scripts, systemd units, and state files from your system.

### 4️⃣ Reconfigure Limine bootloader (set linux-hp as default)
* Automatically discovers and inspects all Limine configuration files on the system (`/boot/limine.conf`, `/boot/limine/limine.conf`, `/boot/EFI/BOOT/limine.conf`).
* Registers `linux-hp` as the primary (first) entry and sets `default_entry: 1`.
* Synchronizes all config copies so UEFI Limine boots it seamlessly.
* Installs an automatic libalpm pacman hook (`/etc/pacman.d/hooks/99-limine-linux-hp.hook`) to keep Limine updated on future kernel package upgrades.

---

## 🤖 Automated CI/CD (GitHub Actions)

This repository includes a fully automated GitHub Actions workflow ([`.github/workflows/build-kernel.yml`](file:///.github/workflows/build-kernel.yml)):

* **Daily Upstream Check:** Runs every day at 06:00 UTC (and on manual trigger via `workflow_dispatch`).
* **Change Detection:** Automatically checks if Arch Linux has released a newer kernel.
* **Cloud Compilation:** Runs inside a clean `archlinux:latest` container, injects all Alder Lake optimizations, and builds specifically for this HP laptop using [`hp-modules.list`](file:///hp-modules.list).
* **Automated GitHub Release:** Packages `linux-hp-*.pkg.tar.zst`, computes SHA256 checksums, writes detailed release notes, and attaches the binary assets to a new GitHub Release.
* **Instant Installation:** Once released, you can simply run `./install.sh` and pick **Option 1** on your laptop to download and install the precompiled kernel in seconds.

---

## 💡 Runtime Power Management Tips

For everyday use on battery, select the balanced or power-saver profile:

```bash
# Balanced profile (smooth desktop experience with great efficiency):
powerprofilesctl set balanced

# Power-saver profile (maximum battery life during travel):
powerprofilesctl set power-saver
```

To monitor power draw in real time:
```bash
# View discharge rate in Watts:
upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep -E 'energy-rate|time to empty'

# Interactive component inspection:
sudo powertop
```
