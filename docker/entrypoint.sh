#!/bin/bash
#
# Remotion egg · entrypoint
#
# 1. menyiapkan environment (HOME, TMPDIR, IP internal)
# 2. menampilkan banner sistem
# 3. menjalankan:
#      - argumen diberikan         -> jalankan apa adanya   (docker run image bash)
#      - Pterodactyl (STARTUP)     -> jalankan startup command dari panel
#      - selain itu                -> menu bernomor (remotion-menu)

cd /home/container 2>/dev/null || cd "${HOME:-/}" || true
export HOME="${HOME:-/home/container}"
export PROJECT_DIR="${PROJECT_DIR:-/home/container}"
export INTERNAL_IP
INTERNAL_IP=$(ip route get 1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n1)

# /tmp di Pterodactyl adalah tmpfs kecil (default 100 MB). Bundle Remotion,
# frame sementara dan profil Chrome bisa jauh lebih besar, jadi dipindah ke disk server.
export TMPDIR="${TMPDIR:-$PROJECT_DIR/.tmp}"
mkdir -p "$TMPDIR" 2>/dev/null && find "$TMPDIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null

export NPM_CONFIG_UPDATE_NOTIFIER=false
export NPM_CONFIG_FUND=false
export NPM_CONFIG_AUDIT=false

# shellcheck source=lib.sh
. /usr/local/lib/remotion/lib.sh

show_banner
# Penanda "server sudah menyala" untuk panel (lihat config.startup.done di egg).
echo "[remotion] ready"

# 1) perintah eksplisit (docker run image bash)
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

# 2) Pterodactyl / Pelican: panel mengirim startup command lewat $STARTUP
if [ -n "${STARTUP}" ]; then
    # ubah {{VAR}} menjadi ${VAR} lalu expand (cara yang sama dengan yolks resmi)
    PARSED=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")
    # shellcheck disable=SC2086
    exec env ${PARSED}
fi

# 3) Docker biasa: langsung ke menu
exec /usr/local/bin/remotion-menu
