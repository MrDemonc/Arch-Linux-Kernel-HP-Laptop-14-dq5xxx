#!/usr/bin/env python3
"""
Limine Bootloader Configuration Updater for linux-hp
Ensures linux-hp is registered and set as default primary entry in Limine.
Compatible with standard Arch Linux, Omarchy, and other distributions.
"""

import sys
import os
import re
import shutil
import argparse

def find_limine_configs():
    candidates = [
        "/boot/EFI/BOOT/limine.conf",
        "/boot/limine/limine.conf",
        "/boot/limine.conf",
        "/boot/efi/EFI/BOOT/limine.conf",
        "/boot/efi/limine/limine.conf",
        "/boot/efi/limine.conf",
        "/efi/EFI/BOOT/limine.conf",
        "/efi/limine/limine.conf",
        "/efi/limine.conf",
    ]
    found = set()
    for c in candidates:
        if os.path.isfile(c):
            found.add(os.path.realpath(c))

    for base in ["/boot", "/efi"]:
        if os.path.isdir(base):
            for root, dirs, files in os.walk(base):
                for f in files:
                    if f in ("limine.conf", "limine.cfg"):
                        found.add(os.path.realpath(os.path.join(root, f)))
    return sorted(list(found))

def find_file_in_boot(filename):
    for base in ["/boot", "/efi", "/boot/efi"]:
        if not os.path.isdir(base):
            continue
        p = os.path.join(base, filename)
        if os.path.isfile(p):
            return p
        for root, dirs, files in os.walk(base):
            if filename in files:
                return os.path.join(root, filename)
    return None

def update_limine(remove=False, dry_run=False):
    conf_files = find_limine_configs()
    if not conf_files:
        print("⚠️  No limine.conf or limine.cfg found on this system.")
        return 1

    template_file = None
    template_content = ""
    for cf in conf_files:
        try:
            with open(cf, "r", encoding="utf-8", errors="replace") as f:
                c = f.read()
                if "/" in c:
                    template_file = cf
                    template_content = c
                    break
        except Exception:
            continue

    if not template_file:
        template_file = conf_files[0]
        with open(template_file, "r", encoding="utf-8", errors="replace") as f:
            template_content = f.read()

    lines = template_content.splitlines()

    global_lines = []
    entries = []
    current_title = None
    current_entry_lines = []

    for line in lines:
        if line.startswith("/") and not line.startswith("//"):
            if current_title is not None:
                while current_entry_lines and not current_entry_lines[-1].strip():
                    current_entry_lines.pop()
                entries.append((current_title, current_entry_lines))
            current_title = line
            current_entry_lines = []
        elif current_title is not None:
            current_entry_lines.append(line)
        else:
            global_lines.append(line)

    if current_title is not None:
        while current_entry_lines and not current_entry_lines[-1].strip():
            current_entry_lines.pop()
        entries.append((current_title, current_entry_lines))

    while global_lines and not global_lines[-1].strip():
        global_lines.pop()

    # Filter out existing linux-hp entries
    filtered_entries = [
        (title, elines) for title, elines in entries
        if "linux-hp" not in title.lower()
    ]

    has_kernel = find_file_in_boot("vmlinuz-linux-hp") is not None

    if remove or not has_kernel:
        if remove:
            print(">> Removing linux-hp from Limine bootloader...")
        else:
            print(">> vmlinuz-linux-hp not found. Cleaning up any existing linux-hp entries...")
        all_entries = filtered_entries
    else:
        print(">> Configuring linux-hp in Limine bootloader...")

        ref_title = None
        ref_lines = []
        for title, elines in filtered_entries:
            is_linux = any("protocol: linux" in l for l in elines) or any("vmlinuz" in l for l in elines)
            if is_linux and "fallback" not in title.lower():
                ref_title = title
                ref_lines = elines
                break

        if not ref_lines and filtered_entries:
            ref_title, ref_lines = filtered_entries[0]

        # Determine distro / OS title base
        ref_base = "Arch Linux"
        if ref_title:
            cleaned = re.sub(r'^[/:#\s]+', '', ref_title)
            ref_base = re.sub(r'\s*\([^)]*\)', '', cleaned).strip() or "Arch Linux"

        main_title = f"/{ref_base} (linux-hp)"
        fallback_title = f"/{ref_base} (linux-hp fallback)"

        protocol = "linux"
        path_prefix = "boot():/"
        ucode_line = None
        cmdline = None

        for l in ref_lines:
            s = l.strip()
            if s.startswith("protocol:"):
                protocol = s.split(":", 1)[1].strip()
            elif s.startswith("path:"):
                p = s.split(":", 1)[1].strip()
                m = re.match(r'^(.*?)[^/:\s]*vmlinuz', p)
                if m:
                    path_prefix = m.group(1)
                else:
                    path_prefix = "boot():/"
            elif s.startswith("module_path:") and ("ucode" in s.lower() or "microcode" in s.lower()):
                ucode_line = l
            elif s.startswith("cmdline:"):
                cmdline = s.split(":", 1)[1].strip()

        if not ucode_line:
            if find_file_in_boot("intel-ucode.img"):
                ucode_line = f"    module_path: {path_prefix}intel-ucode.img"
            elif find_file_in_boot("amd-ucode.img"):
                ucode_line = f"    module_path: {path_prefix}amd-ucode.img"

        if not cmdline and os.path.exists("/proc/cmdline"):
            try:
                with open("/proc/cmdline", "r") as pf:
                    cmdline = pf.read().strip()
            except Exception:
                pass

        # Ensure stability parameters for Alder Lake hybrid C-states & Realtek PCIe Wi-Fi:
        # 1. pcie_aspm=default: Prevents Realtek RTL8821CE PCIe Bus Error (AER) interrupt storms.
        # 2. intel_idle.max_cstate=4: Prevents Alder Lake E-core deep C-state wake timeouts during MCE broadcast.
        stability_flags = ["pcie_aspm=default", "intel_idle.max_cstate=4"]
        cmdline_tokens = cmdline.split() if cmdline else []
        for flag in stability_flags:
            key = flag.split("=")[0]
            if not any(t.startswith(key + "=") or t == key for t in cmdline_tokens):
                cmdline_tokens.append(flag)
        hp_cmdline = " ".join(cmdline_tokens)

        new_hp_entries = []

        # Primary entry: Arch Linux (linux-hp)
        hp_entry_lines = [
            f"    protocol: {protocol}",
            f"    path: {path_prefix}vmlinuz-linux-hp"
        ]
        if ucode_line:
            hp_entry_lines.append(ucode_line)
        hp_entry_lines.append(f"    module_path: {path_prefix}initramfs-linux-hp.img")
        if hp_cmdline:
            hp_entry_lines.append(f"    cmdline: {hp_cmdline}")

        new_hp_entries.append((main_title, hp_entry_lines))

        # Fallback entry if initramfs fallback exists
        if find_file_in_boot("initramfs-linux-hp-fallback.img"):
            hp_fb_lines = [
                f"    protocol: {protocol}",
                f"    path: {path_prefix}vmlinuz-linux-hp"
            ]
            if ucode_line:
                hp_fb_lines.append(ucode_line)
            hp_fb_lines.append(f"    module_path: {path_prefix}initramfs-linux-hp-fallback.img")
            if hp_cmdline:
                hp_fb_lines.append(f"    cmdline: {hp_cmdline}")
            new_hp_entries.append((fallback_title, hp_fb_lines))

        all_entries = new_hp_entries + filtered_entries

    new_globals = []
    has_default_entry = False
    for gl in global_lines:
        if gl.strip().startswith("default_entry:"):
            new_globals.append("default_entry: 1")
            has_default_entry = True
        else:
            new_globals.append(gl)

    if not has_default_entry:
        idx = -1
        for i, gl in enumerate(new_globals):
            if gl.strip().startswith("timeout:"):
                idx = i + 1
                break
        if idx >= 0:
            new_globals.insert(idx, "default_entry: 1")
        else:
            new_globals.insert(0, "default_entry: 1")

    out_lines = list(new_globals)
    for title, elines in all_entries:
        out_lines.append("")
        out_lines.append(title)
        out_lines.extend(elines)

    final_text = "\n".join(out_lines).strip() + "\n"

    if dry_run:
        print("=== DRY RUN: Resulting limine.conf ===")
        print(final_text)
        print(f"Would write to {len(conf_files)} file(s): {', '.join(conf_files)}")
        return 0

    for cf in conf_files:
        try:
            bak = cf + ".bak"
            if not os.path.exists(bak):
                shutil.copy2(cf, bak)
            with open(cf, "w", encoding="utf-8") as f:
                f.write(final_text)
            print(f"✅ Updated: {cf}")
        except Exception as e:
            print(f"❌ Failed to write {cf}: {e}")
            return 1

    print("✅ Limine bootloader successfully configured with linux-hp as primary default entry.")
    return 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Update Limine bootloader entries for linux-hp")
    parser.add_argument("--remove", action="store_true", help="Remove linux-hp entries from limine.conf")
    parser.add_argument("--dry-run", action="store_true", help="Show proposed changes without writing")
    args = parser.parse_args()
    sys.exit(update_limine(remove=args.remove, dry_run=args.dry_run))
