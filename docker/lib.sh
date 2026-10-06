#!/bin/bash
#
# Remotion egg · fungsi bersama untuk entrypoint.sh dan menu.sh
# (warna, banner, info sistem). File ini di-source, bukan dijalankan.

REMOTION_TEMPLATE="${REMOTION_TEMPLATE:-/opt/remotion/template}"
PROJECT_DIR="${PROJECT_DIR:-/home/container}"

# --- ANSI colors ------------------------------------------------------------
RESET='\033[0m'
BOLD='\033[1m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RED='\033[1;31m'
PINK='\033[38;5;212m'
GRAY='\033[0;90m'

LINE="${GRAY}$(printf '%.0s─' $(seq 1 60))${RESET}"

# --- helpers ----------------------------------------------------------------
info()  { echo -e "${CYAN}[remotion]${RESET} $*"; }
ok()    { echo -e "${GREEN}[remotion]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[remotion]${RESET} $*"; }
fail()  { echo -e "${RED}[remotion]${RESET} $*"; }

server_port() { echo "${SERVER_PORT:-${PORT:-3000}}"; }

make_bar() {
    local percent=$1 width=25
    [ "$percent" -gt 100 ] && percent=100
    [ "$percent" -lt 0 ] && percent=0
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))
    local bar=""
    [ "$filled" -gt 0 ] && bar+=$(printf '%0.s█' $(seq 1 "$filled"))
    [ "$empty" -gt 0 ] && bar+=$(printf '%0.s░' $(seq 1 "$empty"))
    echo -n "$bar"
}

# Memory as the container sees it (cgroup limit), falling back to the host numbers.
read_memory() {
    local host_total used_b total_b
    host_total=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}')
    MEM_TOTAL=${host_total:-0}
    MEM_USED=$(free -m 2>/dev/null | awk '/Mem:/ {print $3}')
    MEM_USED=${MEM_USED:-0}

    if [ -r /sys/fs/cgroup/memory.max ]; then                          # cgroup v2
        total_b=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
        used_b=$(cat /sys/fs/cgroup/memory.current 2>/dev/null)
    elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then      # cgroup v1
        total_b=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)
        used_b=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null)
    fi

    if [[ "$total_b" =~ ^[0-9]+$ ]] && [[ "$used_b" =~ ^[0-9]+$ ]]; then
        local total_mb=$(( total_b / 1024 / 1024 ))
        if [ "$total_mb" -gt 0 ] && { [ "$MEM_TOTAL" -eq 0 ] || [ "$total_mb" -lt "$MEM_TOTAL" ]; }; then
            MEM_TOTAL=$total_mb
            MEM_USED=$(( used_b / 1024 / 1024 ))
        fi
    fi
    [ "$MEM_TOTAL" -le 0 ] && MEM_TOTAL=1
    MEM_PERCENT=$(( MEM_USED * 100 / MEM_TOTAL ))
}

print_logo() {
    echo -e "${BLUE}${BOLD}"
    cat <<'ART'
 ___ ___ __  __  ___ _____ ___ ___  _  _
| _ \ __|  \/  |/ _ \_   _|_ _/ _ \| \| |
|   / _|| |\/| | (_) || |  | | (_) | .` |
|_|_\___|_|  |_|\___/ |_| |___\___/|_|\_|
ART
    echo -e "${RESET}"
}

# Versi Remotion yang terpasang di project (atau di template image).
remotion_version() {
    local dir
    for dir in "$PROJECT_DIR" "$REMOTION_TEMPLATE"; do
        if [ -f "$dir/node_modules/remotion/package.json" ]; then
            node -p "require('$dir/node_modules/remotion/package.json').version" 2>/dev/null && return
        fi
    done
    echo "belum terpasang"
}

show_banner() {
    read_memory
    local disk_used disk_total disk_percent
    disk_used=$(df -h "$PROJECT_DIR" 2>/dev/null | awk 'NR==2 {print $3}')
    disk_total=$(df -h "$PROJECT_DIR" 2>/dev/null | awk 'NR==2 {print $2}')
    disk_percent=$(df -h "$PROJECT_DIR" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
    [[ "$disk_percent" =~ ^[0-9]+$ ]] || disk_percent=0

    local os_name cpu_name cpu_cores location
    os_name=$(grep -oP '(?<=^PRETTY_NAME=).+' /etc/os-release 2>/dev/null | tr -d '"')
    cpu_name=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //')
    cpu_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null)
    location=$(curl -s --max-time 2 ipinfo.io/country 2>/dev/null | tr -d '\n')
    [[ "$location" =~ ^[A-Z]{2}$ ]] || location="Unknown"

    local project_state renders
    if [ -f "$PROJECT_DIR/package.json" ]; then
        project_state="${GREEN}ada${RESET}"
    else
        project_state="${YELLOW}belum ada${RESET} ${GRAY}(template dipasang otomatis)${RESET}"
    fi
    renders=$(find "$PROJECT_DIR/out" -maxdepth 1 -type f 2>/dev/null | wc -l)

    [ -t 1 ] && [ "${NO_CLEAR:-0}" != "1" ] && clear
    print_logo
    echo -e "$LINE"
    echo -e "${CYAN}Location${RESET}   : ${location}"
    if [[ "${SHOW_IP,,}" == "true" || "${SHOW_IP}" == "1" ]]; then
        local public_ip
        public_ip=$(curl -s --max-time 2 ipinfo.io/ip 2>/dev/null | tr -d '\n')
        [[ "$public_ip" =~ ^[0-9a-fA-F:.]+$ ]] || public_ip="Unknown"
        echo -e "${CYAN}IP Address${RESET} : ${public_ip}"
    fi
    echo -e "${CYAN}OS${RESET}         : ${os_name:-Unknown}"
    echo -e "${CYAN}CPU${RESET}        : ${cpu_name:-Unknown} (${cpu_cores:-?} Cores)"
    echo -e "${CYAN}Uptime${RESET}     : $(uptime -p 2>/dev/null | sed 's/up //')"
    echo -e "${CYAN}RAM${RESET}  ${YELLOW}${MEM_PERCENT}%${RESET}  ${GREEN}$(make_bar "$MEM_PERCENT")${RESET}  ${GRAY}${MEM_USED}/${MEM_TOTAL}MB${RESET}"
    echo -e "${CYAN}Disk${RESET} ${YELLOW}${disk_percent}%${RESET}  ${YELLOW}$(make_bar "$disk_percent")${RESET}  ${GRAY}${disk_used:-?}/${disk_total:-?}${RESET}"
    echo -e "$LINE"
    echo -e "${BLUE}Remotion${RESET}     : $(remotion_version)"
    echo -e "${BLUE}Node.js${RESET}      : $(node -v 2>/dev/null || echo 'Not Installed')"
    echo -e "${BLUE}Port Studio${RESET}  : $(server_port)"
    echo -e "${BLUE}Project${RESET}      : ${PROJECT_DIR} (${project_state})"
    echo -e "${BLUE}Hasil render${RESET} : ${renders} file di ${PROJECT_DIR}/out"
    echo -e "$LINE"
}
