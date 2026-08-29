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
        # Gaming & Latency optimizations:
        "CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y": "# CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS is not set\nCONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y",
        "CONFIG_TCP_CONG_BBR=m": "CONFIG_TCP_CONG_BBR=y",
        "CONFIG_DEFAULT_CUBIC=y": "# CONFIG_DEFAULT_CUBIC is not set\nCONFIG_DEFAULT_BBR=y",
        'CONFIG_DEFAULT_TCP_CONG="cubic"': 'CONFIG_DEFAULT_TCP_CONG="bbr"',
    }

    for target, rep in replacements.items():
        content = content.replace(target, rep)

    lines = [
        l for l in content.splitlines()
        if l.strip() not in [
            "# CONFIG_HZ_300 is not set",
            "# CONFIG_PCIEASPM_POWER_SUPERSAVE is not set",
            "# CONFIG_TRANSPARENT_HUGEPAGE_MADVISE is not set",
        ]
    ]

    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("   [OK] config.x86_64 optimized (300Hz, Native CPU, ASPM Supersave, Audio 1s, BBR, THP Madvise).")

def optimize_pkgbuild():
    if not os.path.exists(PKGBUILD_PATH):
        print(f"Error: {PKGBUILD_PATH} not found.")
        sys.exit(1)

    print(">> Optimizing PKGBUILD...")
    with open(PKGBUILD_PATH, "r", encoding="utf-8") as f:
        c = f.read()

    # 1. Set package base & description
    c = re.sub(r"^pkgbase=linux.*$", "pkgbase=linux-hp", c, flags=re.MULTILINE)
    c = re.sub(
        r"^pkgdesc='Linux'",
        "pkgdesc='Linux kernel tailored and optimized for HP Laptop (Alder Lake, Battery & Power Saving)'",
        c,
        flags=re.MULTILINE
    )

    # 2. Remove docs and rust makedepends
    for dep in [
        r"\s*rust\n", r"\s*rust-bindgen\n", r"\s*rust-src\n",
        r"\s*graphviz\n", r"\s*imagemagick\n", r"\s*python-sphinx\n",
        r"\s*python-yaml\n", r"\s*texlive-latexextra\n", r"\s*# htmldocs\n"
    ]:
        c = re.sub(dep, "\n", c)

    # 3. Clean signature files from source array
    c = re.sub(r"\.tar\.\{xz,sign\}", ".tar.xz", c)
    c = re.sub(r"\.patch\.zst\{,\.sig\}", ".patch.zst", c)
    c = re.sub(r"\n\s*.*?\.(?:sign|sig)\n?", "\n", c)

    # 4. Remove validpgpkeys and sha256sums arrays cleanly line-by-line
    # This avoids regex pitfalls with comments containing parens like '# Jan Alexander Steffens (heftig)'
    lines = c.splitlines(keepends=True)
    new_lines = []
    skip_array = None
    for line in lines:
        if skip_array is None:
            m = re.match(r"^\s*(validpgpkeys|sha256sums)=\(", line)
            if m:
                skip_array = m.group(1)
                code_part = line.split("#")[0]
                if ")" in code_part.split("=", 1)[1]:
                    skip_array = None
                continue
            if line.strip().startswith("# https://www.kernel.org/pub/linux/kernel/"):
                continue
            new_lines.append(line)
        else:
            code_part = line.split("#")[0]
            if ")" in code_part:
                skip_array = None

    c = "".join(new_lines)

    # 5. Format b2sums array to only include actual file hashes (drop SKIPs)
    m = re.search(r"b2sums=\((.*?)\)", c, flags=re.DOTALL)
    if m:
        hashes = re.findall(r"'([0-9a-fA-F]{128})'", m.group(1))
        formatted_b2sums = "b2sums=(\n" + "\n".join(f"  '{h}'" for h in hashes) + "\n)"
        c = c[:m.start()] + formatted_b2sums + c[m.end():]

    # 6. Remove htmldocs building
    c = re.sub(r"\s*make htmldocs[^\n]*\n", "\n", c)
    c = re.sub(r"\s*local pid_docs=\$!\n", "\n", c)
    c = re.sub(r"\s*wait \$pid_docs\n", "\n", c)

    # 7. Add localmodconfig support using hp-modules.list or temp file
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

    # 8. Remove docs package definition
    c = re.sub(r"^_package-docs\(\) \{.*?^\}\n", "", c, flags=re.DOTALL | re.MULTILINE)
    c = re.sub(r"^\s*\"\$pkgbase-docs\"\n?", "", c, flags=re.MULTILINE)

    # 9. Recalculate b2sum for config.x86_64
    b2 = subprocess.check_output(["b2sum", CONFIG_PATH]).decode().split()[0]
    c = re.sub(r"b2sums_x86_64=\('[0-9a-fA-F]+'\)", f"b2sums_x86_64=('{b2}')", c)

    with open(PKGBUILD_PATH, "w", encoding="utf-8") as f:
        f.write(c)
    print("   [OK] PKGBUILD configured with updated b2sums.")

if __name__ == "__main__":
    optimize_config()
    optimize_pkgbuild()
