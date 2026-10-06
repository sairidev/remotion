#!/bin/bash
#
# Remotion egg · menu bernomor
#
# Semua pilihan memakai angka + Enter (tanpa tombol panah), jadi bisa dipakai
# dari console Pterodactyl / Pelican maupun terminal biasa.
#
#   remotion-menu            tampilkan menu
#   remotion-menu studio     langsung jalankan Remotion Studio, lalu kembali ke menu
#
# Environment:
#   SERVER_PORT / PORT        port Remotion Studio                    (default 3000)
#   AUTO_ACTION               studio | menu. Aksi otomatis kalau menu utama
#                             tidak dijawab dalam MENU_TIMEOUT detik   (default studio)
#   MENU_TIMEOUT              detik menunggu sebelum AUTO_ACTION, 0 = tunggu terus (default 30)
#   REMOTION_ENTRY            entry point project, kosong = deteksi otomatis
#   RENDER_CONCURRENCY        jumlah tab Chrome saat render, kosong = otomatis
#   RENDER_EXTRA_ARGS         flag tambahan untuk `remotion render`
#   REMOTION_BROWSER_EXECUTABLE  path Chrome sendiri, kosong = bawaan Remotion
#   PLAIN_OUTPUT              1 = log baris per baris (cocok untuk panel), 0 = progress bar

# shellcheck source=lib.sh
. /usr/local/lib/remotion/lib.sh

cd "$PROJECT_DIR" 2>/dev/null || { echo "Folder project $PROJECT_DIR tidak ada."; exit 1; }
export PATH="$PROJECT_DIR/node_modules/.bin:$PATH"

BIN="$PROJECT_DIR/node_modules/.bin/remotion"
OUT_DIR="$PROJECT_DIR/out"
AUTO_ACTION="${AUTO_ACTION:-studio}"
MENU_TIMEOUT="${MENU_TIMEOUT:-30}"
[[ "$MENU_TIMEOUT" =~ ^[0-9]+$ ]] || MENU_TIMEOUT=30
PLAIN_OUTPUT="${PLAIN_OUTPUT:-1}"

STDIN_OPEN=1     # 0 setelah stdin ditutup (docker run -d tanpa -i)
CHILD=""         # pid (= process group) pekerjaan yang sedang berjalan
PICK=0
ANSWER=""

# ============================================================ proses anak ===

alive() {
    [ -n "$1" ] && [ -d "/proc/$1" ] && ! grep -q '^State:[[:space:]]*Z' "/proc/$1/status" 2>/dev/null
}

stop_child() {
    [ -n "$CHILD" ] || return 0
    local pid=$CHILD i
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
    for i in $(seq 1 50); do
        alive "$pid" || break
        sleep 0.1
    done
    kill -KILL -- "-$pid" 2>/dev/null   # sapu sisa proses (Chrome, ffmpeg)
    wait "$pid" 2>/dev/null
    CHILD=""
}

on_signal() {
    echo
    warn "Menghentikan server..."
    stop_child
    exit 0
}
# Bash sebagai PID 1 mengabaikan sinyal tanpa handler, jadi wajib di-trap
# supaya tombol Stop di panel (SIGINT) langsung bekerja.
trap on_signal INT TERM

# Jalankan perintah di background (session sendiri) dan tunggu sampai selesai.
# Selama berjalan, ketik 0 + Enter untuk menghentikannya dan kembali ke menu.
run_job() {
    local line rc
    if [ "$PLAIN_OUTPUT" = "1" ]; then
        setsid "$@" < /dev/null > >(cat) 2>&1 &
    else
        setsid "$@" < /dev/null &
    fi
    CHILD=$!

    while alive "$CHILD"; do
        if [ "$STDIN_OPEN" = "1" ]; then
            if read -r -t 1 line; then
                line="${line//[[:space:]]/}"
                case "${line,,}" in
                    0|q|stop|batal)
                        warn "Dihentikan."
                        stop_child
                        return 130
                        ;;
                    "") ;;
                    *) echo -e "${GRAY}Sedang berjalan. Ketik 0 + Enter untuk berhenti dan kembali ke menu.${RESET}" ;;
                esac
            else
                rc=$?
                [ "$rc" -le 128 ] && STDIN_OPEN=0     # EOF, bukan timeout
            fi
        else
            sleep 1
        fi
    done

    wait "$CHILD" 2>/dev/null
    rc=$?
    kill -KILL -- "-$CHILD" 2>/dev/null
    CHILD=""
    [ "$PLAIN_OUTPUT" = "1" ] && sleep 0.3      # beri waktu sisa log tercetak
    return "$rc"
}

# ================================================================= input ===

# pick "Judul" "label untuk 0" item1 item2 ...   -> PICK = 0..n
# return 1 kalau stdin tertutup.
pick() {
    local title=$1 zero=$2 n i=1 ans item
    shift 2
    n=$#
    echo
    echo -e "${PINK}${BOLD}${title}${RESET}"
    for item in "$@"; do
        printf "  ${GREEN}%${#n}d)${RESET} %b\n" "$i" "$item"
        i=$(( i + 1 ))
    done
    printf "  ${GRAY}%${#n}d) %s${RESET}\n" 0 "$zero"
    while true; do
        echo -e "${GRAY}Ketik nomor (0-${n}) lalu Enter:${RESET}"
        if ! read -r ans; then
            STDIN_OPEN=0; PICK=0
            return 1
        fi
        ans="${ans//[[:space:]]/}"
        if [[ "$ans" =~ ^[0-9]{1,4}$ ]] && [ "$((10#$ans))" -le "$n" ]; then
            PICK=$((10#$ans))
            return 0
        fi
        echo -e "${YELLOW}Pilihan \"${ans}\" tidak ada. Masukkan angka 0 sampai ${n}.${RESET}"
    done
}

# ask "Pertanyaan" "default"   -> ANSWER
ask() {
    local prompt=$1 default=$2
    if [ -n "$default" ]; then
        echo -e "${PINK}${BOLD}${prompt}${RESET} ${GRAY}[Enter = ${default}]${RESET}"
    else
        echo -e "${PINK}${BOLD}${prompt}${RESET}"
    fi
    if ! read -r ANSWER; then
        STDIN_OPEN=0; ANSWER="$default"
        return 1
    fi
    ANSWER="${ANSWER#"${ANSWER%%[![:space:]]*}"}"
    ANSWER="${ANSWER%"${ANSWER##*[![:space:]]}"}"
    [ -z "$ANSWER" ] && ANSWER="$default"
    return 0
}

human_size() {
    local f=$1 bytes
    bytes=$(stat -c %s "$f" 2>/dev/null || echo 0)
    numfmt --to=iec --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B"
}

# =============================================================== project ===

copy_tree() {   # copy_tree <src-dir> <dst-dir>
    cp -dR --preserve=mode,timestamps "$1"/. "$2"/
}

install_template() {
    if [ ! -d "$REMOTION_TEMPLATE" ]; then
        fail "Template tidak ditemukan di $REMOTION_TEMPLATE."
        return 1
    fi
    info "Memasang project template ke $PROJECT_DIR (±1 menit, sekali saja)..."
    if copy_tree "$REMOTION_TEMPLATE" "$PROJECT_DIR"; then
        ok "Template terpasang. Edit file di ${PROJECT_DIR}/src untuk membuat video."
    else
        fail "Gagal menyalin template. Cek sisa disk server."
        return 1
    fi
}

ensure_project() {
    if [ ! -f "$PROJECT_DIR/package.json" ]; then
        install_template || return 1
    fi
    if [ ! -x "$BIN" ]; then
        if [ -d "$REMOTION_TEMPLATE/node_modules" ] \
            && cmp -s "$PROJECT_DIR/package.json" "$REMOTION_TEMPLATE/package.json"; then
            info "node_modules belum ada, menyalin dari image..."
            mkdir -p "$PROJECT_DIR/node_modules"
            copy_tree "$REMOTION_TEMPLATE/node_modules" "$PROJECT_DIR/node_modules"
        else
            info "node_modules belum ada, menjalankan npm install..."
            run_job npm install || true
            # pakai Chrome dari image supaya tidak perlu download lagi
            if [ -d "$REMOTION_TEMPLATE/node_modules/.remotion" ] \
                && [ -d "$PROJECT_DIR/node_modules" ] \
                && [ ! -d "$PROJECT_DIR/node_modules/.remotion" ]; then
                mkdir -p "$PROJECT_DIR/node_modules/.remotion"
                copy_tree "$REMOTION_TEMPLATE/node_modules/.remotion" "$PROJECT_DIR/node_modules/.remotion"
            fi
        fi
    fi
    if [ ! -x "$BIN" ]; then
        fail "Remotion belum terpasang di project ini (@remotion/cli tidak ada di node_modules)."
        echo -e "${GRAY}Buka menu \"Kelola project\" lalu pilih \"Install dependencies\".${RESET}"
        return 1
    fi
    mkdir -p "$OUT_DIR"
    return 0
}

find_entry() {
    local f
    if [ -n "$REMOTION_ENTRY" ]; then
        if [ -f "$PROJECT_DIR/$REMOTION_ENTRY" ]; then
            ENTRY="$REMOTION_ENTRY"; return 0
        fi
        fail "REMOTION_ENTRY=$REMOTION_ENTRY tidak ditemukan di project."
        return 1
    fi
    for f in src/index.ts src/index.tsx src/index.js src/index.jsx \
             remotion/index.ts remotion/index.tsx src/remotion/index.ts src/remotion/index.tsx; do
        if [ -f "$PROJECT_DIR/$f" ]; then
            ENTRY="$f"; return 0
        fi
    done
    fail "Entry point tidak ditemukan (dicari: src/index.ts dan sejenisnya)."
    echo -e "${GRAY}Isi variabel REMOTION_ENTRY dengan path file yang memanggil registerRoot().${RESET}"
    return 1
}

browser_args() {
    BROWSER_ARGS=()
    [ -n "$REMOTION_BROWSER_EXECUTABLE" ] && BROWSER_ARGS=(--browser-executable "$REMOTION_BROWSER_EXECUTABLE")
}

# Isi COMP_IDS / COMP_LABELS dari `remotion compositions`.
load_compositions() {
    local raw id fps size frames rest
    COMP_IDS=(); COMP_LABELS=()
    browser_args
    info "Membaca daftar komposisi (bisa ±30 detik saat pertama kali)..."
    raw=$("$BIN" compositions "$ENTRY" "${BROWSER_ARGS[@]}" < /dev/null 2>&1)
    while read -r id fps size frames rest; do
        [[ "$size" =~ ^[0-9]+x[0-9]+$ ]] || continue
        [[ "$frames" =~ ^[0-9]+$ ]] || continue
        COMP_IDS+=("$id")
        COMP_LABELS+=("$(printf '%-22s %-10s %5s fps  %s' "$id" "$size" "$fps" "$rest")")
    done <<< "$raw"
    if [ "${#COMP_IDS[@]}" -eq 0 ]; then
        fail "Tidak ada komposisi yang terbaca. Output Remotion:"
        echo "$raw" | tail -n 25
        return 1
    fi
}

choose_composition() {
    load_compositions || return 1
    pick "Pilih komposisi" "Kembali" "${COMP_LABELS[@]}" || return 1
    [ "$PICK" -eq 0 ] && return 1
    COMP_ID="${COMP_IDS[$((PICK - 1))]}"
}

# ================================================================== aksi ===

action_studio() {
    ensure_project || return 1
    find_entry || return 1
    browser_args
    local port; port=$(server_port)
    echo -e "$LINE"
    ok "Menjalankan Remotion Studio di port ${port}"
    echo -e "  Buka di browser : ${BOLD}http://IP-SERVER:${port}${RESET}"
    echo -e "  ${YELLOW}Studio tidak punya login.${RESET} Siapa pun yang tahu alamatnya bisa membuka dan mengubah project."
    echo -e "  ${GRAY}Ketik 0 + Enter untuk mematikan Studio dan kembali ke menu.${RESET}"
    echo -e "$LINE"
    run_job "$BIN" studio "$ENTRY" --port "$port" --ipv4 --no-open "${BROWSER_ARGS[@]}"
}

action_render() {
    ensure_project || return 1
    find_entry || return 1
    choose_composition || return 1

    local codec ext
    pick "Format output untuk ${COMP_ID}" "Batal" \
        "MP4  (H.264)   paling umum, cocok untuk semua platform" \
        "MP4  (H.265)   ukuran lebih kecil" \
        "WebM (VP9)     untuk web" \
        "GIF            tanpa suara" \
        "MOV  (ProRes)  untuk diedit lagi, ukuran besar" || return 1
    case "$PICK" in
        1) codec=h264;   ext=mp4 ;;
        2) codec=h265;   ext=mp4 ;;
        3) codec=vp9;    ext=webm ;;
        4) codec=gif;    ext=gif ;;
        5) codec=prores; ext=mov ;;
        *) return 1 ;;
    esac

    local rel="out/${COMP_ID}-$(date +%Y%m%d-%H%M%S).${ext}"
    local args=(render "$ENTRY" "$COMP_ID" "$rel" --codec "$codec")
    [[ "$RENDER_CONCURRENCY" =~ ^[0-9]+%?$ ]] && args+=(--concurrency "$RENDER_CONCURRENCY")
    local extra=()
    [ -n "$RENDER_EXTRA_ARGS" ] && read -r -a extra <<< "$RENDER_EXTRA_ARGS"

    echo -e "$LINE"
    info "Render ${COMP_ID} -> ${rel}"
    echo -e "  ${GRAY}Ketik 0 + Enter untuk membatalkan.${RESET}"
    echo -e "$LINE"
    if run_job "$BIN" "${args[@]}" "${extra[@]}" "${BROWSER_ARGS[@]}" && [ -f "$PROJECT_DIR/$rel" ]; then
        ok "Selesai: ${PROJECT_DIR}/${rel} ($(human_size "$PROJECT_DIR/$rel"))"
        echo -e "  ${GRAY}Unduh lewat File Manager atau SFTP panel, folder out/.${RESET}"
    else
        fail "Render tidak selesai. Lihat pesan di atas."
        rm -f "$PROJECT_DIR/$rel" 2>/dev/null
        return 1
    fi
}

action_still() {
    ensure_project || return 1
    find_entry || return 1
    choose_composition || return 1

    local frame
    while true; do
        ask "Frame ke berapa?" "0" || return 1
        if [[ "$ANSWER" =~ ^[0-9]{1,7}$ ]]; then
            frame=$((10#$ANSWER)); break
        fi
        echo -e "${YELLOW}Masukkan angka, contoh 0 atau 45.${RESET}"
    done

    local rel="out/${COMP_ID}-frame${frame}-$(date +%Y%m%d-%H%M%S).png"
    info "Render gambar ${COMP_ID} frame ${frame} -> ${rel}"
    if run_job "$BIN" still "$ENTRY" "$COMP_ID" "$rel" --frame "$frame" "${BROWSER_ARGS[@]}" \
        && [ -f "$PROJECT_DIR/$rel" ]; then
        ok "Selesai: ${PROJECT_DIR}/${rel} ($(human_size "$PROJECT_DIR/$rel"))"
    else
        fail "Gambar tidak berhasil dibuat. Lihat pesan di atas."
        return 1
    fi
}

action_list() {
    ensure_project || return 1
    find_entry || return 1
    load_compositions || return 1
    echo
    echo -e "${PINK}${BOLD}Komposisi di project ini${RESET}"
    local i=1 label
    for label in "${COMP_LABELS[@]}"; do
        printf "  ${GREEN}%d)${RESET} %s\n" "$i" "$label"
        i=$(( i + 1 ))
    done
}

action_results() {
    local files=() labels=() f
    while true; do
        files=(); labels=()
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            files+=("$f")
            labels+=("$(printf '%-44s %8s  %s' "$(basename "$f")" "$(human_size "$f")" "$(date -r "$f" '+%d-%m-%Y %H:%M')")")
        done < <(ls -1t "$OUT_DIR"/* 2>/dev/null | head -n 40)

        if [ "${#files[@]}" -eq 0 ]; then
            info "Belum ada hasil render di ${OUT_DIR}."
            return 0
        fi
        pick "Hasil render (pilih nomor untuk menghapus file)" "Kembali" \
            "${labels[@]}" "${RED}Hapus SEMUA hasil render${RESET}" || return 1
        [ "$PICK" -eq 0 ] && return 0

        if [ "$PICK" -eq "$(( ${#files[@]} + 1 ))" ]; then
            ask "Hapus semua file di out/? Ketik YA untuk lanjut" "tidak" || return 1
            if [ "$ANSWER" = "YA" ]; then
                find "$OUT_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
                ok "Semua hasil render dihapus."
                return 0
            fi
            info "Dibatalkan."
        else
            f="${files[$((PICK - 1))]}"
            ask "Hapus $(basename "$f")? (y/n)" "n" || return 1
            case "${ANSWER,,}" in
                y|ya|yes) rm -rf "$f" && ok "Dihapus: $(basename "$f")" ;;
                *) info "Dibatalkan." ;;
            esac
        fi
    done
}

reset_template() {
    ask "Reset project ke template bawaan? File lama dipindah ke folder backup. Ketik YA untuk lanjut" "tidak" || return 1
    if [ "$ANSWER" != "YA" ]; then
        info "Dibatalkan."
        return 0
    fi
    local backup="$PROJECT_DIR/backup-$(date +%Y%m%d-%H%M%S)" item
    mkdir -p "$backup" || return 1
    for item in src public package.json package-lock.json remotion.config.ts tsconfig.json; do
        [ -e "$PROJECT_DIR/$item" ] && mv "$PROJECT_DIR/$item" "$backup/"
    done
    info "File lama disimpan di ${backup}"
    info "Menghapus node_modules lama..."
    rm -rf "$PROJECT_DIR/node_modules"
    install_template
}

action_project() {
    while true; do
        pick "Kelola project" "Kembali" \
            "Install dependencies        (npm install)" \
            "Tambah package npm" \
            "Upgrade Remotion ke versi terbaru" \
            "Reset ke template bawaan" || return 1
        case "$PICK" in
            0) return 0 ;;
            1)
                if [ ! -f "$PROJECT_DIR/package.json" ]; then
                    install_template
                else
                    run_job npm install && ok "Dependencies terpasang." || fail "npm install gagal."
                fi
                ;;
            2)
                ensure_project || continue
                ask "Nama package (contoh: @remotion/transitions atau lodash)" "" || return 1
                if [ -z "$ANSWER" ]; then
                    info "Dibatalkan."
                elif [[ "$ANSWER" =~ ^[@A-Za-z0-9._/~^-]+$ ]]; then
                    run_job npm install "$ANSWER" && ok "Package $ANSWER terpasang." || fail "Gagal memasang $ANSWER."
                else
                    fail "Nama package tidak valid."
                fi
                ;;
            3)
                ensure_project || continue
                run_job "$BIN" upgrade && ok "Remotion sekarang versi $(remotion_version)." || fail "Upgrade gagal."
                ;;
            4) reset_template ;;
        esac
    done
}

action_shell() {
    echo -e "${PINK}${BOLD}Silahkan masukan perintah.${RESET} ${GRAY}Ketik exit untuk kembali ke menu.${RESET}"
    echo -e "${GRAY}Contoh: remotion render src/index.ts Hello out/video.mp4${RESET}"
    PS1='\[\e[1;32m\]container\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ ' /bin/bash --norc -i
    cd "$PROJECT_DIR" 2>/dev/null || true
}

# ============================================================ menu utama ===

main_menu() {
    local first=1 ans n=8 port
    while true; do
        port=$(server_port)
        echo
        echo -e "${PINK}${BOLD}Menu Remotion${RESET}"
        echo -e "  ${GREEN}1)${RESET} Jalankan Remotion Studio   ${GRAY}(web editor, port ${port})${RESET}"
        echo -e "  ${GREEN}2)${RESET} Render video"
        echo -e "  ${GREEN}3)${RESET} Render gambar (still)"
        echo -e "  ${GREEN}4)${RESET} Lihat daftar komposisi"
        echo -e "  ${GREEN}5)${RESET} Hasil render"
        echo -e "  ${GREEN}6)${RESET} Kelola project            ${GRAY}(install, upgrade, reset)${RESET}"
        echo -e "  ${GREEN}7)${RESET} Info sistem"
        echo -e "  ${GREEN}8)${RESET} Buka shell"
        echo -e "  ${GRAY}0) Keluar (matikan server)${RESET}"

        if [ "$STDIN_OPEN" != "1" ]; then
            return 0
        fi

        if [ "$first" = "1" ] && [ "$AUTO_ACTION" = "studio" ] && [ "$MENU_TIMEOUT" -gt 0 ]; then
            echo -e "${GRAY}Ketik nomor (0-${n}) lalu Enter. Tanpa jawaban dalam ${MENU_TIMEOUT} detik = 1 (Studio).${RESET}"
            read -r -t "$MENU_TIMEOUT" ans
            local rc=$?
            if [ "$rc" -gt 128 ]; then
                info "Tidak ada jawaban, menjalankan Studio otomatis."
                ans=1
            elif [ "$rc" -ne 0 ]; then
                STDIN_OPEN=0
                return 0
            fi
        else
            echo -e "${GRAY}Ketik nomor (0-${n}) lalu Enter:${RESET}"
            if ! read -r ans; then
                STDIN_OPEN=0
                return 0
            fi
        fi
        first=0

        ans="${ans//[[:space:]]/}"
        case "$ans" in
            1) action_studio ;;
            2) action_render ;;
            3) action_still ;;
            4) action_list ;;
            5) action_results ;;
            6) action_project ;;
            7) NO_CLEAR=1 show_banner ;;
            8) action_shell ;;
            0) ok "Sampai jumpa."; exit 0 ;;
            "") ;;
            *) echo -e "${YELLOW}Pilihan \"${ans}\" tidak ada. Masukkan angka 0 sampai ${n}.${RESET}" ;;
        esac
    done
}

# ==================================================================== go ===

case "${1:-menu}" in
    studio)
        action_studio
        rc=$?
        [ "$STDIN_OPEN" = "1" ] || exit "$rc"
        ;;
    menu|"")
        ;;
    *)
        echo "Pemakaian: remotion-menu [menu|studio]"
        exit 2
        ;;
esac

main_menu

# Sampai di sini berarti stdin tertutup (mis. docker run -d): tidak ada yang
# bisa memilih menu, jadi jalankan aksi otomatis lalu keluar bersama prosesnya.
if [ "$AUTO_ACTION" = "studio" ]; then
    info "Tidak ada input (stdin tertutup), menjalankan Studio."
    action_studio
    exit $?
fi
warn "Tidak ada input (stdin tertutup) dan AUTO_ACTION bukan studio. Keluar."
exit 0
