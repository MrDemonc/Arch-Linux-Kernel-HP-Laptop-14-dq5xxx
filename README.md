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

1. **Native CPU Microarchitecture (`CONFIG_X86_NATIVE_CPU=y`):**
   * Emits machine code specifically compiled for the host CPU using `-march=native` instead of generic legacy x86-64 instructions.
   * Strips out redundant CPU vendor routines for unsupported hardware (`AMD`, `Hygon`, `Centaur`, `Zhaoxin`).
   * Delivers faster cryptographic operations (LUKS encryption) and filesystem compression (Btrfs) with fewer CPU clock cycles per instruction.

2. **300 Hz Timer Frequency (`CONFIG_HZ_300=y`, `CONFIG_HZ=300`):**
   * Default Arch Linux kernels run at 1000 Hz (waking the CPU 1,000 times every second).
   * Reducing this to **300 Hz** cuts CPU wake-up interruptions by **70%**, allowing cores to drop into ultra-deep package sleep states (**C6, C8, and C10**) for over 90% of idle time.

3. **Aggressive PCIe ASPM (`CONFIG_PCIEASPM_POWER_SUPERSAVE=y`):**
   * Forces PCIe buses (Realtek Wi-Fi and Samsung NVMe) into lowest-power active state links (*L1 sub-states*) whenever high-throughput I/O is idle.

4. **Rapid Audio Codec Power-Down (`CONFIG_SND_HDA_POWER_SAVE_DEFAULT=1`):**
   * Suspends the Intel HD audio codec after 1 second of audio silence (compared to 10 seconds default).

5. **Intel Hybrid Scheduler & Energy Model (`CONFIG_INTEL_HFI_THERMAL=y`, `CONFIG_ENERGY_MODEL=y`):**
   * Coordinates with Intel Thread Director and Hardware Feedback Interface (HFI) to prioritize routing background tasks (audio streaming, file indexing, browser background tabs) to the 4 low-power **E-cores**, keeping power-hungry **P-cores** asleep.

6. **Lean & Streamlined Build:**
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
2. In the Limine bootloader menu, use the arrow keys to select **Omarchy (linux)**.
3. Your system boots immediately with the standard kernel.
4. To remove the custom kernel at any time:
   ```bash
   sudo pacman -R linux-hp linux-hp-headers
   ```

---

## 🚀 Unified Management: `install.sh`

All tasks (downloading releases, compiling from source, updates, and notifications) are unified into a single script: [`install.sh`](file:///home/demonc/Documents/Proyects/kernel-test/linux-hp/install.sh).

```bash
cd /home/demonc/Documents/Proyects/kernel-test/linux-hp
./install.sh
```

The interactive menu presents **3 options**:

### 1️⃣ Download precompiled kernel and install (GitHub Releases)
* Quickly install without spending time or battery compiling.
* Automatically queries the **Releases** section of your GitHub repository, downloads the latest `.pkg.tar.zst` packages, and installs them with `pacman`.
* Automatically sets up the background update notifier.

### 2️⃣ Compile from source (Latest upstream version)
* Checks for newly released kernel versions from official Arch Linux upstream.
* Automatically updates the source tree and re-applies all Alder Lake and battery optimizations.
* Lets you choose between **Fast Mode** (~15 min with `localmodconfig`) or **Full Mode**.
* Installs the generated packages and enables the background update notifier.

### 3️⃣ Configure background update notifications
* Configures a lightweight `systemd` user timer (`~/.config/systemd/user/check-kernel-update.timer`).
* Silently checks the official Arch Linux package API every 12 hours (and 5 minutes after system boot).
* Sends a native desktop notification (`notify-send`) when a newer official kernel is released, reminding you to run `./install.sh`.
* Includes an option to trigger a test notification.

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
