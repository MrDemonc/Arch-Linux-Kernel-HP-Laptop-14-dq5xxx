#!/usr/bin/env python3
"""
Applies hardware optimizations for HP Laptop 14-dq5xxx (Intel Alder Lake)
onto Arch Linux official PKGBUILD and config.x86_64 files.
"""
import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(SCRIPT_DIR, "config.x86_64")
PKGBUILD_PATH = os.path.join(SCRIPT_DIR, "PKGBUILD")

def optimize_config():
    if not os.path.exists(CONFIG_PATH):
        print(f"Error: {CONFIG_PATH} not found.")
        sys.exit(1)

    print(">> Optimizing config.x86_64...")
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
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

    lines = [
        l for l in content.splitlines()
        if l.strip() not in ["# CONFIG_HZ_300 is not set", "# CONFIG_PCIEASPM_POWER_SUPERSAVE is not set"]
    ]

    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("   [OK] config.x86_64 optimized (300Hz, Native CPU, ASPM Supersave, Audio 1s).")

def optimize_pkgbuild():
    if not os.path.exists(PKGBUILD_PATH):
        print(f"Error: {PKGBUILD_PATH} not found.")
        sys.exit(1)

    print(">> Optimizing PKGBUILD...")
    with open(PKGBUILD_PATH, "r", encoding="utf-8") as f:
        c = f.read()

    # Set package base & description
    c = re.sub(r"^pkgbase=linux.*$", "pkgbase=linux-hp", c, flags=re.MULTILINE)
    c = re.sub(
        r"^pkgdesc='Linux'",
        "pkgdesc='Linux kernel tailored and optimized for HP Laptop (Alder Lake, Battery & Power Saving)'",
        c,
        flags=re.MULTILINE
    )

    # Remove docs and rust makedepends
    for dep in [
        r"\s*rust\n", r"\s*rust-bindgen\n", r"\s*rust-src\n",
        r"\s*graphviz\n", r"\s*imagemagick\n", r"\s*python-sphinx\n",
        r"\s*python-yaml\n", r"\s*texlive-latexextra\n", r"\s*# htmldocs\n"
    ]:
        c = re.sub(dep, "\n", c)

    # Remove signature requirements
    c = re.sub(r"\.sign\}", "", c)
    c = re.sub(r"\.sig\}", "", c)
    c = re.sub(r"\.tar\.\{xz,sign\}", ".tar.xz", c)
    c = re.sub(r"\.patch\.zst\{,\.sig\}", ".patch.zst", c)
    c = re.sub(r"validpgpkeys=\([^)]*\)\n?", "", c)

    # Remove htmldocs building
    c = re.sub(r"\s*make htmldocs[^\n]*\n", "\n", c)
    c = re.sub(r"\s*local pid_docs=\$!\n", "\n", c)
    c = re.sub(r"\s*wait \$pid_docs\n", "\n", c)

    # Add localmodconfig support using hp-modules.list or temp file
    if "localmodconfig" not in c:
        c = c.replace(
            "cp ../config.$CARCH .config\n",
            "cp ../config.$CARCH .config\n"
            "  if [[ -f ../.use_localmodconfig || \"${USE_LOCALMODCONFIG:-0}\" == \"1\" || -n \"${CI:-}\" ]]; then\n"
            "    local _modfile=\"${startdir:-..}/hp-modules.list\"\n"
            "    if [[ ! -f \"$_modfile\" ]]; then\n"
            "      _modfile=\"../hp-modules.list\"\n"
            "    fi\n"
            "    if [[ ! -f \"$_modfile\" ]]; then\n"
            "      _modfile=\"$(mktemp /tmp/lsmod.XXXXXX)\"\n"
            "      lsmod > \"$_modfile\" 2>/dev/null || true\n"
            "    fi\n"
            "    echo \"Applying localmodconfig using $_modfile...\"\n"
            "    yes \"\" | make LSMOD=\"$_modfile\" localmodconfig\n"
            "    [[ \"$_modfile\" == /tmp/* ]] && rm -f \"$_modfile\"\n"
            "  fi\n"
        )

    # Remove docs package definition
    c = re.sub(r"_package-docs\(\) \{.*?^\}\n", "", c, flags=re.DOTALL | re.MULTILINE)
    c = re.sub(r'"\$pkgbase-docs"\n?', "", c)
    c = re.sub(r"\n\s*'SKIP'", "", c)

    # Recalculate b2sum for config.x86_64
    b2 = subprocess.check_output(["b2sum", CONFIG_PATH]).decode().split()[0]
    c = re.sub(r"b2sums_x86_64=\('[0-9a-fA-F]+'\)", f"b2sums_x86_64=('{b2}')", c)

    with open(PKGBUILD_PATH, "w", encoding="utf-8") as f:
        f.write(c)
    print("   [OK] PKGBUILD configured with updated b2sums.")

if __name__ == "__main__":
    optimize_config()
    optimize_pkgbuild()
