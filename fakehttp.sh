#!/bin/bash
# FakeHTTP 管理工具 v3.4.0 (final)
# - 自动清理旧进程/残留 PID
# - NFQUEUE 队列号占用自动避让 + 自动落盘到 config.conf
# - payload 自动转绝对路径（避免 -d/daemon 后相对路径失效）
# - 支持交互式菜单 + 命令行 start/stop/restart/status/run

set -euo pipefail

# ============================================================================
# 版本和路径
# ============================================================================
SCRIPT_VERSION="3.4.0"
FAKEHTTP_VERSION="0.9.18"
GITHUB_REPO="MikeWang000000/FakeHTTP"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
INSTALL_DIR="$SCRIPT_DIR"
FAKEHTTP_BIN="${INSTALL_DIR}/fakehttp-bin"
CONFIG_FILE="${INSTALL_DIR}/config.conf"
PID_FILE="${INSTALL_DIR}/.pid"
LOG_FILE="${INSTALL_DIR}/fakehttp.log"

SERVICE_NAME="fakehttp"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

umask 077

# ============================================================================
# 默认配置（会被 config.conf 覆盖）
# ============================================================================
INTERFACES=()
HOSTS=()
EXCLUDES=()
PAYLOADS=()
TTL="5"
IP_VERSION="4"

# NFQUEUE 队列号（会自动避让并落盘）
QUEUE_NUM="1000"

# 运行模式：
# - RUN_DAEMON=true  -> 让 fakehttp 自己 -d 守护化（脚本需用 pgrep 回收真实 PID）
# - RUN_DAEMON=false -> 脚本用 nohup & 后台托管（推荐，PID 可控、路径不易踩坑）
RUN_DAEMON="false"

# 是否默认开启静默（-s）
SILENT="false"

# 是否自动修复队列占用（true 时占用就自动向上找空闲队列并落盘）
AUTO_FIX_QUEUE="true"

GITHUB_MIRRORS=(
  "https://gh-proxy.com/"
  "https://ghproxy.net/"
  "https://mirror.ghproxy.com/"
)

NO_SYSTEMD=true

# ============================================================================
# 颜色
# ============================================================================
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# ============================================================================
# 工具函数
# ============================================================================
clear_screen() { printf "\033c"; }

print_header() {
  echo -e "${CYAN}${BOLD}"
  echo "╔═══════════════════════════════════════════════════════════╗"
  echo "║              FakeHTTP 管理工具 v${SCRIPT_VERSION}                  ║"
  echo "╚═══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

press_enter() {
  echo
  read -rp "按 Enter 继续..."
}

check_root() {
  if [[ ${EUID:-9999} -ne 0 ]]; then
    echo -e "${RED}[错误] 需要 root 权限${NC}"
    echo "请使用: sudo $0"
    exit 1
  fi
}

detect_systemd() {
  command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]] && NO_SYSTEMD=false || NO_SYSTEMD=true
}

detect_architecture() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)   echo "linux-x86_64" ;;
    i386|i686)      echo "linux-i386" ;;
    aarch64|arm64)  echo "linux-arm64" ;;
    armv7l)         echo "linux-arm" ;;
    *)              echo "" ;;
  esac
}

# ============================================================================
# 配置管理
# ============================================================================
parse_array() {
  local str="$1"
  local -n arr="$2"
  arr=()
  while [[ "$str" =~ \"([^\"]+)\" ]]; do
    arr+=("${BASH_REMATCH[1]}")
    str="${str#*\"${BASH_REMATCH[1]}\"}"
  done
}

load_config() {
  [[ -f "$CONFIG_FILE" ]] || return 1

  # reset
  INTERFACES=(); HOSTS=(); EXCLUDES=(); PAYLOADS=()
  TTL="5"; IP_VERSION="4"
  QUEUE_NUM="${QUEUE_NUM:-1000}"
  RUN_DAEMON="${RUN_DAEMON:-false}"
  SILENT="${SILENT:-false}"
  AUTO_FIX_QUEUE="${AUTO_FIX_QUEUE:-true}"

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # trim
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    if [[ "$line" =~ ^([A-Z_]+)=\"([^\"]*)\"$ ]]; then
      local key="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
      case "$key" in
        TTL) TTL="$value" ;;
        IP_VERSION) IP_VERSION="$value" ;;
        QUEUE_NUM) QUEUE_NUM="$value" ;;
        RUN_DAEMON) RUN_DAEMON="$value" ;;
        SILENT) SILENT="$value" ;;
        AUTO_FIX_QUEUE) AUTO_FIX_QUEUE="$value" ;;
      esac
    elif [[ "$line" =~ ^([A-Z_]+)=\((.+)\)$ ]]; then
      local key="${BASH_REMATCH[1]}" content="${BASH_REMATCH[2]}"
      case "$key" in
        INTERFACES) parse_array "$content" INTERFACES ;;
        HOSTS) parse_array "$content" HOSTS ;;
        EXCLUDES) parse_array "$content" EXCLUDES ;;
        PAYLOADS) parse_array "$content" PAYLOADS ;;
      esac
    elif [[ "$line" =~ ^([A-Z_]+)=(.+)$ ]]; then
      # 兼容未加引号的简单 kv
      local key="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
      value="${value%\"}"; value="${value#\"}"
      case "$key" in
        QUEUE_NUM) QUEUE_NUM="$value" ;;
        RUN_DAEMON) RUN_DAEMON="$value" ;;
        SILENT) SILENT="$value" ;;
        AUTO_FIX_QUEUE) AUTO_FIX_QUEUE="$value" ;;
      esac
    fi
  done < "$CONFIG_FILE"

  return 0
}

format_array() {
  local -n arr="$1"
  local result=""
  for item in "${arr[@]}"; do result+="\"$item\" "; done
  echo "(${result% })"
}

save_config() {
  cat > "$CONFIG_FILE" <<EOF
# FakeHTTP 配置文件
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
#
# -h : HTTP 域名 (可多个，轮换)
# -e : HTTPS/TLS 域名 (可多个，轮换)
# -b : 二进制 payload 文件 (可多个，轮换)
# -i : 网络接口 (可多个，留空=所有接口)
#
# 队列说明:
#   QUEUE_NUM 为 NFQUEUE 队列号；若被占用且 AUTO_FIX_QUEUE=true，会自动寻找空闲队列并写回该值。

INTERFACES=$(format_array INTERFACES)
HOSTS=$(format_array HOSTS)
EXCLUDES=$(format_array EXCLUDES)
PAYLOADS=$(format_array PAYLOADS)

TTL="$TTL"
IP_VERSION="$IP_VERSION"

QUEUE_NUM="$QUEUE_NUM"
AUTO_FIX_QUEUE="$AUTO_FIX_QUEUE"

RUN_DAEMON="$RUN_DAEMON"
SILENT="$SILENT"
EOF
  chmod 600 "$CONFIG_FILE"
}

# 原地更新（或追加）一个简单 KV（保持其它配置不变）
persist_kv() {
  local key="$1" value="$2"
  if [[ -f "$CONFIG_FILE" ]] && grep -qE "^${key}=" "$CONFIG_FILE"; then
    # 尽量保持引号风格
    if grep -qE "^${key}=\".*\"$" "$CONFIG_FILE"; then
      sed -i "s/^${key}=\".*\"$/${key}=\"${value}\"/" "$CONFIG_FILE"
    else
      sed -i "s/^${key}=.*$/${key}=\"${value}\"/" "$CONFIG_FILE"
    fi
  else
    echo "" >> "$CONFIG_FILE"
    echo "${key}=\"${value}\"" >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE" || true
  fi
}

# ============================================================================
# NFQUEUE 队列检测/避让
# ============================================================================
is_queue_in_use() {
  local q="$1"
  [[ -r /proc/net/netfilter/nfnetlink_queue ]] || return 1
  grep -qE "^[[:space:]]*${q}[[:space:]]" /proc/net/netfilter/nfnetlink_queue
}

find_free_queue() {
  local start="$1"
  local q="$start"
  local max=65535
  while (( q <= max )); do
    if ! is_queue_in_use "$q"; then
      echo "$q"
      return 0
    fi
    ((q++))
  done
  return 1
}

ensure_queue_available() {
  # sanitize
  if [[ ! "$QUEUE_NUM" =~ ^[0-9]+$ ]]; then
    echo -e "${YELLOW}[警告] QUEUE_NUM=$QUEUE_NUM 非数字，重置为 1000${NC}"
    QUEUE_NUM="1000"
    persist_kv "QUEUE_NUM" "$QUEUE_NUM"
  fi

  if is_queue_in_use "$QUEUE_NUM"; then
    if [[ "${AUTO_FIX_QUEUE,,}" == "true" ]]; then
      echo -e "${YELLOW}队列 $QUEUE_NUM 已被占用，正在查找可用队列...${NC}"
      local new_q
      new_q="$(find_free_queue "$QUEUE_NUM")" || {
        echo -e "${RED}无法找到可用 NFQUEUE 队列（从 $QUEUE_NUM 开始）${NC}"
        return 1
      }
      if [[ "$new_q" != "$QUEUE_NUM" ]]; then
        echo -e "${GREEN}使用新的 NFQUEUE 队列: $new_q${NC}"
        QUEUE_NUM="$new_q"
        persist_kv "QUEUE_NUM" "$QUEUE_NUM"
      fi
    else
      echo -e "${RED}队列 $QUEUE_NUM 已被占用（AUTO_FIX_QUEUE=false）${NC}"
      return 1
    fi
  fi
}

# ============================================================================
# 进程管理
# ============================================================================
strict_pgrep() {
  # 仅匹配以 fakehttp-bin 绝对路径开头的进程，避免误杀
  pgrep -f -- "^${FAKEHTTP_BIN}([[:space:]]|$)" 2>/dev/null || true
}

is_running() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null && return 0
  fi
  strict_pgrep | grep -qE '^[0-9]+$'
}

get_pid() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null && { echo "$pid"; return 0; }
  fi
  strict_pgrep | head -1
}

pre_start_cleanup() {
  # 尽量优雅释放 NFQUEUE
  [[ -x "$FAKEHTTP_BIN" ]] && "$FAKEHTTP_BIN" -k >/dev/null 2>&1 || true

  # 如果还有残留进程，逐个 TERM -> KILL
  local pids
  pids="$(strict_pgrep || true)"
  [[ -z "${pids:-}" ]] && { rm -f "$PID_FILE"; return 0; }

  echo -e "${YELLOW}检测到残留 fakehttp 进程，正在清理... (${pids//$'\n'/ })${NC}"
  while IFS= read -r pid; do
    [[ -z "${pid:-}" ]] && continue
    kill -TERM "$pid" 2>/dev/null || true
  done <<< "$pids"

  local i=0
  while (( i < 5 )); do
    sleep 1
    strict_pgrep | grep -qE '^[0-9]+$' || break
    ((i++))
  done

  pids="$(strict_pgrep || true)"
  if [[ -n "${pids:-}" ]]; then
    while IFS= read -r pid; do
      [[ -z "${pid:-}" ]] && continue
      kill -KILL "$pid" 2>/dev/null || true
    done <<< "$pids"
  fi

  rm -f "$PID_FILE"
}

# ============================================================================
# 命令构建
# ============================================================================
build_cmd_array() {
  local -a cmd
  cmd=("$FAKEHTTP_BIN")

  # interface
  if [[ ${#INTERFACES[@]} -eq 0 ]]; then
    cmd+=("-a")
  else
    for i in "${INTERFACES[@]}"; do cmd+=("-i" "$i"); done
  fi

  # hosts/excludes
  for h in "${HOSTS[@]}"; do cmd+=("-h" "$h"); done
  for e in "${EXCLUDES[@]}"; do cmd+=("-e" "$e"); done

  # payloads -> absolute path; missing -> warn
  for p in "${PAYLOADS[@]}"; do
    [[ -z "${p:-}" ]] && continue
    [[ "$p" != /* ]] && p="${INSTALL_DIR}/$p"
    if [[ -f "$p" ]]; then
      cmd+=("-b" "$p")
    else
      echo -e "${YELLOW}[警告] payload 不存在，已跳过: $p${NC}"
    fi
  done

  # ip version
  case "$IP_VERSION" in
    4)  cmd+=("-4") ;;
    6)  cmd+=("-6") ;;
    46) cmd+=("-4" "-6") ;;
    *)  echo -e "${YELLOW}[警告] IP_VERSION=$IP_VERSION 非法，默认 IPv4${NC}"; cmd+=("-4") ;;
  esac

  # ttl
  [[ "$TTL" =~ ^[0-9]+$ ]] || { echo -e "${YELLOW}[警告] TTL=$TTL 非数字，默认 5${NC}"; TTL="5"; }
  cmd+=("-t" "$TTL")

  # queue + log + silent
  cmd+=("-n" "$QUEUE_NUM")
  cmd+=("-w" "$LOG_FILE")
  [[ "${SILENT,,}" == "true" ]] && cmd+=("-s")

  # daemon
  [[ "${RUN_DAEMON,,}" == "true" ]] && cmd+=("-d")

  CMD_ARRAY=("${cmd[@]}")
}

# ============================================================================
# 运行控制
# ============================================================================
do_start() {
  load_config || { echo -e "${RED}配置文件不存在: $CONFIG_FILE${NC}"; return 1; }

  if is_running; then
    echo -e "${YELLOW}已在运行 (PID: $(get_pid))${NC}"
    return 0
  fi

  [[ -x "$FAKEHTTP_BIN" ]] || { echo -e "${RED}未安装 fakehttp: $FAKEHTTP_BIN${NC}"; return 1; }

  if [[ ${#HOSTS[@]} -eq 0 && ${#EXCLUDES[@]} -eq 0 && ${#PAYLOADS[@]} -eq 0 ]]; then
    echo -e "${RED}未配置任何 -h/-e/-b 参数${NC}"
    return 1
  fi

  # 确保日志权限
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE" || true

  # 清理残留进程/队列占用
  pre_start_cleanup

  # 队列占用自动避让 + 落盘
  ensure_queue_available

  # build cmd
  build_cmd_array
  echo "启动命令: ${CMD_ARRAY[*]}"

  if [[ "${RUN_DAEMON,,}" == "true" ]]; then
    # fakehttp 自己 daemonize，不能用 $! 取真实 PID
    "${CMD_ARRAY[@]}" >>"$LOG_FILE" 2>&1 || true
    sleep 1
    local pid
    pid="$(strict_pgrep | head -1 || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "$pid" > "$PID_FILE"
      echo -e "${GREEN}启动成功 (PID: $pid)${NC}"
      return 0
    fi
    echo -e "${RED}启动失败（daemon 模式未检测到进程），查看日志: $LOG_FILE${NC}"
    return 1
  else
    # 脚本托管后台
    (cd "$INSTALL_DIR" && nohup "${CMD_ARRAY[@]}" >>"$LOG_FILE" 2>&1 & echo $! > "$PID_FILE")
    sleep 1
    local pid
    pid="$(get_pid || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      echo -e "${GREEN}启动成功 (PID: $pid)${NC}"
      return 0
    fi
    rm -f "$PID_FILE"
    echo -e "${RED}启动失败，查看日志: $LOG_FILE${NC}"
    return 1
  fi
}

do_run_foreground() {
  # 给 systemd 用：前台运行（不后台），并保留自动避让+落盘队列逻辑
  load_config || { echo -e "${RED}配置文件不存在: $CONFIG_FILE${NC}"; return 1; }
  [[ -x "$FAKEHTTP_BIN" ]] || { echo -e "${RED}未安装 fakehttp: $FAKEHTTP_BIN${NC}"; return 1; }

  touch "$LOG_FILE"; chmod 600 "$LOG_FILE" || true

  pre_start_cleanup
  ensure_queue_available

  # 强制前台：不加 -d
  local old_run_daemon="$RUN_DAEMON"
  RUN_DAEMON="false"
  build_cmd_array
  RUN_DAEMON="$old_run_daemon"

  echo "前台运行命令: ${CMD_ARRAY[*]}"
  exec "${CMD_ARRAY[@]}"
}

do_stop() {
  # 尽可能使用 pid file + fakehttp -k
  if ! is_running; then
    echo -e "${YELLOW}未运行${NC}"
    rm -f "$PID_FILE"
    return 0
  fi

  echo "停止中..."
  [[ -x "$FAKEHTTP_BIN" ]] && "$FAKEHTTP_BIN" -k >/dev/null 2>&1 || true

  local pid
  pid="$(get_pid || true)"
  if [[ -n "${pid:-}" ]]; then
    kill -TERM "$pid" 2>/dev/null || true
  fi

  local count=0
  while is_running && (( count < 8 )); do
    sleep 1
    ((count++))
  done

  if is_running; then
    local pids
    pids="$(strict_pgrep || true)"
    while IFS= read -r p; do
      [[ -z "${p:-}" ]] && continue
      kill -KILL "$p" 2>/dev/null || true
    done <<< "$pids"
  fi

  rm -f "$PID_FILE"
  echo -e "${GREEN}已停止${NC}"
}

do_restart() {
  do_stop
  sleep 1
  do_start
}

print_status() {
  if is_running; then
    echo -e "状态: ${GREEN}● 运行中${NC} (PID: $(get_pid))"
  else
    echo -e "状态: ${RED}○ 未运行${NC}"
  fi
}

# ============================================================================
# 下载安装
# ============================================================================
find_mirror() {
  for mirror in "${GITHUB_MIRRORS[@]}"; do
    curl -sI --connect-timeout 3 "${mirror}https://github.com" &>/dev/null && { echo "$mirror"; return 0; }
  done
  return 1
}

download_fakehttp() {
  local platform
  platform="$(detect_architecture)"
  [[ -z "$platform" ]] && { echo -e "${RED}不支持的架构${NC}"; return 1; }

  local filename="fakehttp-${platform}.tar.gz"
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "'"$temp_dir"'"' EXIT

  echo "选择下载方式:"
  echo "  1. GitHub 镜像 (推荐)"
  echo "  2. 直接下载"
  echo "  3. HTTP 代理"
  read -rp "选择 [1]: " method
  method="${method:-1}"

  local url="https://github.com/${GITHUB_REPO}/releases/download/${FAKEHTTP_VERSION}/${filename}"
  local -a opts
  opts=("-L" "--progress-bar" "--fail" "--connect-timeout" "15")

  case "$method" in
    1)
      local mirror
      mirror="$(find_mirror || true)"
      [[ -z "${mirror:-}" ]] && { echo -e "${RED}无可用镜像${NC}"; return 1; }
      url="${mirror}${url}"
      ;;
    3)
      read -rp "代理地址: " proxy
      opts+=("--proxy" "$proxy")
      ;;
  esac

  echo "下载: $url"
  curl "${opts[@]}" -o "${temp_dir}/${filename}" "$url" || { echo -e "${RED}下载失败${NC}"; return 1; }

  echo "解压安装..."
  local extract_dir
  extract_dir="$(mktemp -d)"
  tar --no-same-owner --no-same-permissions -xzf "${temp_dir}/${filename}" -C "$extract_dir"

  local binary
  binary="$(find "$extract_dir" -name "fakehttp" -type f | head -1 || true)"
  [[ -z "${binary:-}" ]] && { echo -e "${RED}未找到二进制文件${NC}"; return 1; }

  cp "$binary" "$FAKEHTTP_BIN"
  chmod 755 "$FAKEHTTP_BIN"
  rm -rf "$extract_dir"
  trap - EXIT
  rm -rf "$temp_dir"

  echo -e "${GREEN}安装完成: $FAKEHTTP_BIN${NC}"
}

# ============================================================================
# 配置向导
# ============================================================================
detect_interfaces() {
  DETECTED_INTERFACES=()
  while IFS= read -r line; do
    if [[ "$line" =~ ^[0-9]+:\ ([^:@]+)[@:]? ]]; then
      local iface="${BASH_REMATCH[1]}"
      [[ "$iface" != "lo" && ! "$iface" =~ ^(veth|docker|br-) ]] && DETECTED_INTERFACES+=("$iface")
    fi
  done < <(ip link show 2>/dev/null || true)
}

config_wizard() {
  clear_screen
  print_header
  echo -e "${CYAN}配置向导${NC}"
  echo

  detect_interfaces
  echo "网络接口 (留空=所有接口 -a):"
  echo "  0. 所有接口"
  local i=1
  for iface in "${DETECTED_INTERFACES[@]}"; do
    echo "  $i. $iface"
    ((i++))
  done
  read -rp "选择 (空格分隔多选) [0]: " choices
  INTERFACES=()
  if [[ -n "${choices:-}" && "${choices:-}" != "0" ]]; then
    for c in $choices; do
      (( c >= 1 && c <= ${#DETECTED_INTERFACES[@]} )) && INTERFACES+=("${DETECTED_INTERFACES[$((c-1))]}")
    done
  fi
  echo -e "接口: ${GREEN}${INTERFACES[*]:-(所有)}${NC}"
  echo

  echo "-h HTTP 域名 (模拟 http://example.com):"
  echo "  预设: 1.speedtest 2.nuaa 3.fast.com 4.google"
  echo "  输入域名或编号，空格分隔，直接回车使用默认"
  read -rp "> " input
  HOSTS=()
  if [[ -z "${input:-}" ]]; then
    HOSTS=("www.speedtest.net" "speed.nuaa.edu.cn")
  else
    for item in $input; do
      case "$item" in
        1) HOSTS+=("www.speedtest.net") ;;
        2) HOSTS+=("speed.nuaa.edu.cn") ;;
        3) HOSTS+=("fast.com") ;;
        4) HOSTS+=("www.google.com") ;;
        *) HOSTS+=("$item") ;;
      esac
    done
  fi
  echo -e "-h: ${GREEN}${HOSTS[*]}${NC}"
  echo

  echo "-e HTTPS/TLS 域名 (模拟 https://example.com):"
  echo "  预设: 1.ustc 2.google 3.youtube"
  echo "  直接回车跳过"
  read -rp "> " input
  EXCLUDES=()
  for item in ${input:-}; do
    case "$item" in
      1) EXCLUDES+=("test.ustc.edu.cn") ;;
      2) EXCLUDES+=("www.google.com") ;;
      3) EXCLUDES+=("www.youtube.com") ;;
      *) EXCLUDES+=("$item") ;;
    esac
  done
  echo -e "-e: ${GREEN}${EXCLUDES[*]:-(无)}${NC}"
  echo

  local bins=()
  while IFS= read -r -d '' f; do
    bins+=("$(basename "$f")")
  done < <(find "$INSTALL_DIR" -maxdepth 1 -name "*.bin" -type f -print0 2>/dev/null || true)

  echo "-b Payload 文件:"
  if [[ ${#bins[@]} -gt 0 ]]; then
    echo "  检测到: ${bins[*]}"
  fi
  echo "  输入文件名，空格分隔，直接回车跳过"
  read -rp "> " input
  PAYLOADS=()
  for item in ${input:-}; do
    [[ -n "$item" ]] && PAYLOADS+=("$item")
  done
  echo -e "-b: ${GREEN}${PAYLOADS[*]:-(无)}${NC}"
  echo

  read -rp "TTL [5]: " input
  TTL="${input:-5}"
  echo -e "TTL: ${GREEN}$TTL${NC}"
  echo

  echo "IP 版本: 1.IPv4 2.IPv6 3.双栈"
  read -rp "选择 [1]: " input
  case "${input:-1}" in
    2) IP_VERSION="6" ;;
    3) IP_VERSION="46" ;;
    *) IP_VERSION="4" ;;
  esac
  echo -e "IP: ${GREEN}IPv$IP_VERSION${NC}"
  echo

  read -rp "NFQUEUE 队列号 QUEUE_NUM [1000]: " input
  QUEUE_NUM="${input:-1000}"
  echo -e "QUEUE_NUM: ${GREEN}$QUEUE_NUM${NC}"
  echo

  read -rp "AUTO_FIX_QUEUE 自动避让并落盘？[Y/n]: " input
  if [[ "${input:-Y}" =~ ^[Nn]$ ]]; then AUTO_FIX_QUEUE="false"; else AUTO_FIX_QUEUE="true"; fi
  echo -e "AUTO_FIX_QUEUE: ${GREEN}$AUTO_FIX_QUEUE${NC}"
  echo

  read -rp "RUN_DAEMON 使用 fakehttp -d？（不推荐）[y/N]: " input
  if [[ "${input:-N}" =~ ^[Yy]$ ]]; then RUN_DAEMON="true"; else RUN_DAEMON="false"; fi
  echo -e "RUN_DAEMON: ${GREEN}$RUN_DAEMON${NC}"
  echo

  read -rp "SILENT 默认静默(-s)？[y/N]: " input
  if [[ "${input:-N}" =~ ^[Yy]$ ]]; then SILENT="true"; else SILENT="false"; fi
  echo -e "SILENT: ${GREEN}$SILENT${NC}"
  echo

  save_config
  echo -e "${GREEN}配置已保存${NC}"
}

# ============================================================================
# systemd 服务（推荐使用脚本的 run 前台模式，以便保留队列避让+落盘）\n# ============================================================================
create_service() {
  [[ "$NO_SYSTEMD" == "true" ]] && return 0

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=FakeHTTP Service (managed by ${SCRIPT_NAME})
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${SCRIPT_NAME} run
ExecStop=${INSTALL_DIR}/${SCRIPT_NAME} stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  echo -e "${GREEN}systemd 服务已创建/更新: ${SERVICE_FILE}${NC}"
}

# ============================================================================
# 菜单功能
# ============================================================================
menu_status() {
  clear_screen
  print_header
  load_config 2>/dev/null || true

  echo -e "${CYAN}【状态信息】${NC}\n"
  print_status
  echo
  echo "安装目录: $INSTALL_DIR"
  echo "二进制:   $([[ -x "$FAKEHTTP_BIN" ]] && echo -e "${GREEN}已安装${NC}" || echo -e "${RED}未安装${NC}")"
  echo "配置文件: $([[ -f "$CONFIG_FILE" ]] && echo -e "${GREEN}存在${NC}" || echo -e "${YELLOW}不存在${NC}")"
  echo
  echo -e "${CYAN}【当前配置】${NC}\n"
  echo "接口 -i:     ${INTERFACES[*]:-(所有 -a)}"
  echo "-h HTTP:     ${HOSTS[*]:-(无)}"
  echo "-e HTTPS:    ${EXCLUDES[*]:-(无)}"
  echo "-b Payload:  ${PAYLOADS[*]:-(无)}"
  echo "TTL:         $TTL"
  echo "IP版本:      IPv$IP_VERSION"
  echo "QUEUE_NUM:   $QUEUE_NUM"
  echo "AUTO_FIX:    $AUTO_FIX_QUEUE"
  echo "RUN_DAEMON:  $RUN_DAEMON"
  echo "SILENT:      $SILENT"

  press_enter
}

menu_start() { clear_screen; print_header; echo -e "${CYAN}【启动服务】${NC}\n"; do_start; press_enter; }
menu_stop() { clear_screen; print_header; echo -e "${CYAN}【停止服务】${NC}\n"; do_stop; press_enter; }
menu_restart() { clear_screen; print_header; echo -e "${CYAN}【重启服务】${NC}\n"; do_restart; press_enter; }

menu_log() {
  clear_screen
  print_header
  echo -e "${CYAN}【运行日志】${NC} (最近 80 行)\n"
  if [[ -f "$LOG_FILE" ]]; then
    tail -80 "$LOG_FILE" || true
    echo
    read -rp "实时查看？[y/N]: " realtime
    [[ "${realtime:-N}" =~ ^[Yy]$ ]] && tail -f "$LOG_FILE"
  else
    echo -e "${YELLOW}暂无日志${NC}"
  fi
  press_enter
}

menu_config() {
  clear_screen
  print_header
  echo -e "${CYAN}【配置管理】${NC}\n"
  echo "  1. 配置向导 (交互式)"
  echo "  2. 编辑配置文件"
  echo "  3. 查看当前配置"
  echo "  0. 返回\n"
  read -rp "选择: " choice
  case "$choice" in
    1) config_wizard; press_enter ;;
    2)
      if command -v nano &>/dev/null; then nano "$CONFIG_FILE"
      elif command -v vi &>/dev/null; then vi "$CONFIG_FILE"
      else echo "请手动编辑: $CONFIG_FILE"; press_enter; fi
      ;;
    3)
      echo
      if [[ -f "$CONFIG_FILE" ]]; then cat "$CONFIG_FILE"; else echo -e "${YELLOW}配置文件不存在${NC}"; fi
      press_enter
      ;;
  esac
}

menu_install() {
  clear_screen
  print_header
  echo -e "${CYAN}【安装/更新】${NC}\n"

  if [[ -x "$FAKEHTTP_BIN" ]]; then
    echo -e "${YELLOW}已安装 fakehttp${NC}"
    read -rp "重新下载安装？[y/N]: " confirm
    [[ ! "${confirm:-N}" =~ ^[Yy]$ ]] && return
  fi

  download_fakehttp || { press_enter; return; }

  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo
    read -rp "运行配置向导？[Y/n]: " wizard
    [[ ! "${wizard:-Y}" =~ ^[Nn]$ ]] && config_wizard
  fi

  detect_systemd
  if [[ "$NO_SYSTEMD" == "false" ]]; then
    echo
    read -rp "创建/更新 systemd 服务（建议）？[Y/n]: " svc
    [[ ! "${svc:-Y}" =~ ^[Nn]$ ]] && create_service
  fi

  press_enter
}

menu_uninstall() {
  clear_screen
  print_header
  echo -e "${CYAN}【卸载】${NC}\n"
  echo -e "${RED}警告: 此操作将删除 fakehttp-bin、PID、日志${NC}"
  read -rp "确定卸载？[y/N]: " confirm
  [[ ! "${confirm:-N}" =~ ^[Yy]$ ]] && return

  do_stop 2>/dev/null || true

  detect_systemd
  if [[ "$NO_SYSTEMD" == "false" ]]; then
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
  fi

  rm -f "$FAKEHTTP_BIN" "$PID_FILE" "$LOG_FILE"
  read -rp "删除配置文件？[y/N]: " del_conf
  [[ "${del_conf:-N}" =~ ^[Yy]$ ]] && rm -f "$CONFIG_FILE"

  echo -e "${GREEN}卸载完成${NC}"
  press_enter
}

menu_service() {
  detect_systemd
  if [[ "$NO_SYSTEMD" == "true" ]]; then
    echo -e "${YELLOW}systemd 不可用${NC}"
    press_enter
    return
  fi

  clear_screen
  print_header
  echo -e "${CYAN}【systemd 服务管理】${NC}\n"

  local status enabled
  status="$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo "inactive")"
  enabled="$(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || echo "disabled")"
  echo "服务状态: $status"
  echo "开机启动: $enabled\n"
  echo "  1. 启动服务"
  echo "  2. 停止服务"
  echo "  3. 重启服务"
  echo "  4. 启用开机启动"
  echo "  5. 禁用开机启动"
  echo "  6. 查看服务状态"
  echo "  7. 重新生成服务文件"
  echo "  0. 返回\n"
  read -rp "选择: " choice

  case "$choice" in
    1) systemctl start "$SERVICE_NAME"; echo "已启动" ;;
    2) systemctl stop "$SERVICE_NAME"; echo "已停止" ;;
    3) systemctl restart "$SERVICE_NAME"; echo "已重启" ;;
    4) systemctl enable "$SERVICE_NAME"; echo "已启用" ;;
    5) systemctl disable "$SERVICE_NAME"; echo "已禁用" ;;
    6) systemctl status "$SERVICE_NAME" --no-pager || true ;;
    7) create_service ;;
  esac

  press_enter
}

# ============================================================================
# 主菜单
# ============================================================================
main_menu() {
  while true; do
    clear_screen
    print_header
    print_status
    echo
    echo -e "${CYAN}【主菜单】${NC}\n"
    echo "  1. 查看状态"
    echo "  2. 启动"
    echo "  3. 停止"
    echo "  4. 重启"
    echo "  5. 查看日志"
    echo "  6. 配置管理"
    echo "  7. systemd 服务"
    echo "  8. 安装/更新"
    echo "  9. 卸载"
    echo "  0. 退出\n"
    read -rp "选择: " choice
    case "$choice" in
      1) menu_status ;;
      2) menu_start ;;
      3) menu_stop ;;
      4) menu_restart ;;
      5) menu_log ;;
      6) menu_config ;;
      7) menu_service ;;
      8) menu_install ;;
      9) menu_uninstall ;;
      0|q|Q) clear_screen; echo "再见！"; exit 0 ;;
    esac
  done
}

# ============================================================================
# 入口
# ============================================================================
case "${1:-}" in
  start)   check_root; do_start ;;
  stop)    check_root; do_stop ;;
  restart) check_root; do_restart ;;
  status)  load_config 2>/dev/null || true; print_status ;;
  run)     check_root; do_run_foreground ;;
  -h|--help)
    echo "FakeHTTP 管理工具 v${SCRIPT_VERSION}"
    echo
    echo "用法: $0 [命令]"
    echo
    echo "命令:"
    echo "  (无)      交互式菜单"
    echo "  start     后台启动（自动清理旧进程、自动避让并落盘队列号）"
    echo "  stop      停止"
    echo "  restart   重启"
    echo "  status    状态"
    echo "  run       前台运行（给 systemd 用，保留队列避让+落盘）"
    echo
    exit 0
    ;;
  "")
    check_root
    main_menu
    ;;
  *)
    echo "未知命令: $1"
    echo "使用 $0 --help 查看帮助"
    exit 1
    ;;
esac
