#!/usr/bin/env bash
# ==============================================================================
# Instalador y Gestor Unificado: linux-hp
# Equipo: HP Laptop 14-dq5xxx (Intel Core i3-1215U Alder Lake)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PKGBUILD_FILE="$SCRIPT_DIR/PKGBUILD"
CONFIG_FILE="$SCRIPT_DIR/config.x86_64"
CONFIG_REPO_FILE="$SCRIPT_DIR/.github_repo"

# ------------------------------------------------------------------------------
# Función: Aplicar optimizaciones para Alder Lake y ahorro de batería
# ------------------------------------------------------------------------------
apply_optimizations() {
    echo ">> Aplicando optimizaciones en PKGBUILD y config.x86_64..."
    python3 - << 'EOF'
import os
import re
import subprocess

script_dir = os.getcwd()
pkgbuild_path = os.path.join(script_dir, "PKGBUILD")
config_path = os.path.join(script_dir, "config.x86_64")

# 1. Optimizar config.x86_64
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
    print("   [OK] config.x86_64 optimizado (300Hz, Native CPU, ASPM Supersave, Audio 1s).")

# 2. Optimizar PKGBUILD
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
        c = c.replace("cp ../config.$CARCH .config\n", "cp ../config.$CARCH .config\n  if [[ -f ../.use_localmodconfig || \"${USE_LOCALMODCONFIG:-0}\" == \"1\" ]]; then\n    echo \"Applying localmodconfig (streamlining for HP laptop hardware)...\"\n    yes \"\" | make LSMOD=<(lsmod) localmodconfig\n  fi\n")

    c = re.sub(r"_package-docs\(\) \{.*?^\}\n", "", c, flags=re.DOTALL | re.MULTILINE)
    c = re.sub(r'"\$pkgbase-docs"\n?', "", c)
    c = re.sub(r"\n\s*'SKIP'", "", c)

    # Recalcular hash de config.x86_64
    b2 = subprocess.check_output(["b2sum", config_path]).decode().split()[0]
    c = re.sub(r"b2sums_x86_64=\('[0-9a-fA-F]+'\)", f"b2sums_x86_64=('{b2}')", c)

    with open(pkgbuild_path, "w", encoding="utf-8") as f:
        f.write(c)
    print("   [OK] PKGBUILD configurado con b2sums actualizados.")
EOF
}

# ------------------------------------------------------------------------------
# Función: Instalar el notificador de actualizaciones en segundo plano
# ------------------------------------------------------------------------------
setup_background_notifier() {
    echo ""
    echo ">> Configurando notificador de actualizaciones del kernel en segundo plano..."
    
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.config/systemd/user"

    # 1. Script que verifica si Arch tiene un nuevo kernel
    cat << 'EOF' > "$HOME/.local/bin/check-kernel-update.sh"
#!/usr/bin/env bash
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# Obtener última versión disponible en el repositorio de Arch Linux (API pública oficial)
LATEST_JSON=$(curl -s --connect-timeout 10 https://archlinux.org/packages/core/x86_64/linux/json/ 2>/dev/null || true)
UPSTREAM_VER=$(echo "$LATEST_JSON" | grep -o '"pkgver": "[^"]*"' | head -n1 | cut -d'"' -f4)

[ -z "$UPSTREAM_VER" ] && exit 0

# Obtener versión instalada en el sistema
INSTALLED_VER=$(pacman -Q linux-hp 2>/dev/null | awk '{print $2}' | cut -d'-' -f1)
[ -z "$INSTALLED_VER" ] && INSTALLED_VER=$(pacman -Q linux 2>/dev/null | awk '{print $2}' | cut -d'-' -f1)

NOTIF_FILE="$HOME/.config/linux-hp-last-notified"
LAST_NOTIFIED=""
[ -f "$NOTIF_FILE" ] && LAST_NOTIFIED=$(cat "$NOTIF_FILE")

# Si la versión de Arch es más reciente y no hemos notificado antes:
if [ -n "$INSTALLED_VER" ] && [ "$UPSTREAM_VER" != "$INSTALLED_VER" ] && [ "$UPSTREAM_VER" != "$LAST_NOTIFIED" ]; then
    notify-send -u normal -i system-software-update \
        "Actualización de Kernel de Arch Linux" \
        "Hay una nueva versión oficial de Linux ($UPSTREAM_VER). Abre tu proyecto linux-hp y ejecuta ./install.sh para actualizar."
    echo "$UPSTREAM_VER" > "$NOTIF_FILE"
fi
EOF
    chmod +x "$HOME/.local/bin/check-kernel-update.sh"

    # 2. Servicio de systemd de usuario
    cat << EOF > "$HOME/.config/systemd/user/check-kernel-update.service"
[Unit]
Description=Comprobador de actualizaciones del kernel de Arch Linux
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$HOME/.local/bin/check-kernel-update.sh
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
EOF

    # 3. Temporizador de systemd (ejecuta a los 5 min de encender y cada 12 horas)
    cat << EOF > "$HOME/.config/systemd/user/check-kernel-update.timer"
[Unit]
Description=Temporizador de comprobación de actualizaciones de kernel
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
    echo "✅ Notificador configurado con éxito:"
    echo "   * Script: $HOME/.local/bin/check-kernel-update.sh"
    echo "   * Frecuencia: Cada 12 horas y 5 minutos tras iniciar sesión."
}

# ------------------------------------------------------------------------------
# OPCIÓN 1: Descargar e instalar kernel precompilado desde GitHub Releases
# ------------------------------------------------------------------------------
option_download_release() {
    echo "============================================================"
    echo "  DESCARGAR E INSTALAR KERNEL PRECOMPILADO (GitHub Releases)"
    echo "============================================================"
    echo ""

    # Determinar el repositorio de GitHub
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
        read -rp "Repositorio de GitHub [$DEFAULT_REPO]: " USER_REPO
        USER_REPO=${USER_REPO:-$DEFAULT_REPO}
    else
        read -rp "Introduce tu repositorio de GitHub (ejemplo: usuario/kernel-hp): " USER_REPO
    fi

    if [ -z "$USER_REPO" ]; then
        echo "❌ Error: Se requiere el nombre del repositorio de GitHub."
        exit 1
    fi
    echo "$USER_REPO" > "$CONFIG_REPO_FILE"

    echo ">> Consultando el último release en github.com/$USER_REPO..."
    RELEASE_API="https://api.github.com/repos/$USER_REPO/releases/latest"
    RELEASE_DATA=$(curl -sL "$RELEASE_API")

    TAG_NAME=$(echo "$RELEASE_DATA" | grep -o '"tag_name": "[^"]*"' | head -n1 | cut -d'"' -f4)
    if [ -z "$TAG_NAME" ]; then
        echo "❌ Error: No se encontró ningún release publicado en https://github.com/$USER_REPO/releases"
        echo "Asegúrate de subir el archivo .pkg.tar.zst a la sección Releases de tu repositorio."
        exit 1
    fi

    echo ">> Encontrado Release: $TAG_NAME"
    
    # Extraer URLs de los archivos .pkg.tar.zst
    ASSET_URLS=($(echo "$RELEASE_DATA" | grep -o '"browser_download_url": "[^"]*\.pkg\.tar\.zst"' | cut -d'"' -f4))

    if [ ${#ASSET_URLS[@]} -eq 0 ]; then
        echo "❌ Error: El release $TAG_NAME no contiene archivos .pkg.tar.zst"
        exit 1
    fi

    mkdir -p "$SCRIPT_DIR/downloads"
    cd "$SCRIPT_DIR/downloads"
    rm -f *.pkg.tar.zst

    for url in "${ASSET_URLS[@]}"; do
        file_name=$(basename "$url")
        echo ">> Descargando $file_name..."
        curl -L --progress-bar -o "$file_name" "$url"
    done

    echo ""
    echo ">> Instalando paquetes descargados con pacman..."
    sudo pacman -U --needed ./*.pkg.tar.zst
    cd "$SCRIPT_DIR"

    # Configurar el notificador en segundo plano
    setup_background_notifier

    echo ""
    echo "============================================================"
    echo "  ✅ KERNEL INSTALADO CON ÉXITO DESDE GITHUB RELEASES"
    echo "  Reinicia tu equipo ('reboot') y selecciona linux-hp en Limine."
    echo "============================================================"
}

# ------------------------------------------------------------------------------
# OPCIÓN 2: Compilar desde la fuente (última versión)
# ------------------------------------------------------------------------------
option_compile_source() {
    echo "============================================================"
    echo "  COMPILAR KERNEL DESDE LA FUENTE (Última versión)"
    echo "============================================================"
    echo ""

    # 1. Comprobar herramientas requeridas
    MISSING_DEPS=()
    for dep in bc pahole; do
        if ! pacman -Q "$dep" &>/dev/null; then
            MISSING_DEPS+=("$dep")
        fi
    done
    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
        echo ">> Instalando herramientas necesarias (${MISSING_DEPS[*]})..."
        sudo pacman -S --needed "${MISSING_DEPS[@]}"
    fi

    # 2. Comprobar si hay una versión más nueva en Arch Linux
    echo ">> Verificando actualizaciones oficiales de Arch Linux..."
    git fetch https://gitlab.archlinux.org/archlinux/packaging/packages/linux.git main 2>/dev/null || true
    
    UPSTREAM_HASH=$(git rev-parse FETCH_HEAD 2>/dev/null || echo "")
    if [ -n "$UPSTREAM_HASH" ]; then
        UPSTREAM_VER=$(git show "$UPSTREAM_HASH:PKGBUILD" 2>/dev/null | grep -E '^pkgver=' | cut -d= -f2 || true)
        CURRENT_VER=$(grep -E '^pkgver=' PKGBUILD 2>/dev/null | cut -d= -f2 || true)
        
        if [ -n "$UPSTREAM_VER" ] && [ "$UPSTREAM_VER" != "$CURRENT_VER" ]; then
            echo "🔔 ¡Nueva versión disponible en Arch Linux ($UPSTREAM_VER)!"
            echo ">> Actualizando base del árbol..."
            git checkout "$UPSTREAM_HASH" -- PKGBUILD config.x86_64 2>/dev/null || true
            rm -f linux-hp-*.pkg.tar.zst
            rm -rf pkg src
        else
            echo "ℹ️  El código fuente está al día ($CURRENT_VER)."
        fi
    fi

    # 3. Aplicar las optimizaciones de hardware
    apply_optimizations

    # 4. Modo de compilación
    echo ""
    echo "Selecciona el modo de compilación:"
    echo "  1) Rápido (Recomendado): Usa 'localmodconfig' basado en los drivers"
    echo "     de tu HP (Wi-Fi, Bluetooth, Intel GPU, NVMe, etc.)."
    echo "     -> Tiempo estimado: ~15 a 25 minutos."
    echo ""
    echo "  2) Completo: Compila todos los módulos del árbol oficial."
    echo "     -> Tiempo estimado: ~1.5 a 2 horas."
    echo ""
    read -rp "Opción [1 o 2] (predeterminado 1): " MODE_CHOICE
    MODE_CHOICE=${MODE_CHOICE:-1}

    if [ "$MODE_CHOICE" = "1" ]; then
        echo ">> Modo: RÁPIDO (localmodconfig)"
        touch .use_localmodconfig
    else
        echo ">> Modo: COMPLETO (todos los módulos)"
        rm -f .use_localmodconfig
    fi

    # 5. Compilación con todos los núcleos
    CORES=$(nproc)
    export MAKEFLAGS="-j${CORES}"
    echo ">> Compilando con ${CORES} hilos..."
    makepkg -s --force

    echo ""
    echo "============================================================"
    echo "  ✅ ¡COMPILACIÓN FINALIZADA CON ÉXITO!"
    echo "============================================================"
    echo ""
    ls -lh linux-hp-*.pkg.tar.zst 2>/dev/null || true
    echo ""
    read -rp "¿Deseas instalar los paquetes compilados ahora? [S/n]: " INSTALL_NOW
    INSTALL_NOW=${INSTALL_NOW:-S}

    if [[ "$INSTALL_NOW" =~ ^[Ss]$ ]]; then
        sudo pacman -U linux-hp-*.pkg.tar.zst
        setup_background_notifier
        echo ""
        echo "Reinicia tu equipo ('reboot') para cargar el nuevo kernel."
    else
        echo "Puedes instalarlos manualmente cuando desees con:"
        echo "   sudo pacman -U linux-hp-*.pkg.tar.zst"
    fi
}

# ------------------------------------------------------------------------------
# OPCIÓN 3: Configurar / Gestionar el notificador en segundo plano
# ------------------------------------------------------------------------------
option_manage_notifier() {
    echo "============================================================"
    echo "  NOTIFICADOR DE ACTUALIZACIONES EN SEGUNDO PLANO"
    echo "============================================================"
    echo ""
    echo "1) Instalar / Activar el notificador (systemd user timer)"
    echo "2) Probar notificación ahora en tu escritorio"
    echo "3) Desactivar notificador"
    echo ""
    read -rp "Selecciona una opción [1-3]: " NOTIF_CHOICE

    case "$NOTIF_CHOICE" in
        1)
            setup_background_notifier
            ;;
        2)
            echo ">> Enviando notificación de prueba..."
            notify-send -u normal -i system-software-update \
                "Prueba de Notificador linux-hp" \
                "El servicio de notificaciones está funcionando correctamente."
            echo "✅ Notificación enviada. Deberías verla en tu pantalla."
            ;;
        3)
            echo ">> Desactivando temporizador..."
            systemctl --user disable --now check-kernel-update.timer 2>/dev/null || true
            echo "✅ Notificador desactivado."
            ;;
        *)
            echo "Opción inválida."
            ;;
    esac
}

# ------------------------------------------------------------------------------
# MENÚ PRINCIPAL
# ------------------------------------------------------------------------------
echo "============================================================"
echo "       GESTOR DEL KERNEL OPTIMIZADO: linux-hp"
echo "  HP Laptop 14-dq5xxx (Intel Core i3-1215U Alder Lake)"
echo "============================================================"
echo ""
echo "  1) Descargar el kernel compilado e instalar (GitHub Releases)"
echo "  2) Compilar desde la fuente (última versión optimizada)"
echo "  3) Configurar notificaciones en segundo plano para nuevas versiones"
echo ""
read -rp "Selecciona una opción [1, 2 o 3]: " MAIN_CHOICE

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
        echo "Opción no válida. Ejecuta ./install.sh de nuevo."
        exit 1
        ;;
esac
