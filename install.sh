#!/bin/bash

# FakeHTTP 安装和管理脚本
# 自动检测系统架构，下载并安装 FakeHTTP
# 支持安装、卸载、启动、停止等操作

set -e

# 配置变量
GITHUB_REPO="MikeWang000000/FakeHTTP"
VERSION="0.9.18"
INSTALL_DIR="/vol2/1000/fake"
SERVICE_NAME="fakehttp"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LOG_FILE="${INSTALL_DIR}/fakehttp.log"

# 代理配置
DEFAULT_PROXY="http://192.168.31.175:7890"
GITHUB_PROXY="https://gh-proxy.com/"  # GitHub 文件代理
PROXY_TIMEOUT=10
USE_PROXY_AUTO=true  # 自动检测是否需要代理

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

highlight() {
    echo -e "${CYAN}${BOLD}$1${NC}"
}

# 网络配置
INTERFACE="eno1-ovs"
TTL="5"
IP_VERSION="4"  # 4=IPv4, 6=IPv6, 46=双栈
HOSTS=("www.speedtest.net" "speed.nuaa.edu.cn")

# 网络接口检测函数
detect_network_interfaces() {
    info "检测网络接口..."

    # 获取所有网络接口信息
    local interfaces=()
    local interface_info=()

    # 使用 ip 命令获取接口信息
    while IFS= read -r line; do
        if [[ "$line" =~ ^[0-9]+:\ ([^:]+): ]]; then
            local iface="${BASH_REMATCH[1]}"
            # 排除回环接口和明显不符合的接口
            if [[ "$iface" != "lo" && ! "$iface" =~ ^(veth|docker0|br-[a-f0-9]+)$ ]]; then
                local ip_info=$(ip addr show "$iface" 2>/dev/null | grep -E "inet [0-9]" | head -1 | awk '{print $2}' | cut -d'/' -f1)
                local state=$(ip link show "$iface" 2>/dev/null | grep -o "state [A-Z]*" | cut -d' ' -f2)

                # 只保留有IP地址或者是UP状态的接口
                if [[ -n "$ip_info" || "$state" == "UP" ]]; then
                    interfaces+=("$iface")
                    interface_info+=("$iface|$ip_info|$state")
                fi
            fi
        fi
    done < <(ip link show 2>/dev/null)

    # 导出接口信息供其他函数使用
    export DETECTED_INTERFACES=("${interfaces[@]}")
    export INTERFACE_INFO=("${interface_info[@]}")
}



# 显示网络接口详细信息
show_interface_details() {
    local iface="$1"

    for info in "${INTERFACE_INFO[@]}"; do
        IFS='|' read -r if_name ip_addr state <<< "$info"
        if [[ "$if_name" == "$iface" ]]; then
            echo "  接口名称: $if_name"
            echo "  IP 地址:  ${ip_addr:-未配置}"
            echo "  状态:     ${state:-未知}"


            # 显示更多详细信息
            if command -v ip &> /dev/null; then
                local mac=$(ip link show "$iface" 2>/dev/null | grep -o "link/ether [^ ]*" | cut -d' ' -f2)
                local mtu=$(ip link show "$iface" 2>/dev/null | grep -o "mtu [0-9]*" | cut -d' ' -f2)

                if [[ -n "$mac" ]]; then
                    echo "  MAC 地址: $mac"
                fi
                if [[ -n "$mtu" ]]; then
                    echo "  MTU:      $mtu"
                fi
            fi

            # 测试接口连通性
            if [[ -n "$ip_addr" ]]; then
                echo "  连通性测试..."
                if ping -c 1 -W 2 -I "$iface" 8.8.8.8 &> /dev/null; then
                    echo "  网络连通: ✅ 正常"
                else
                    echo "  网络连通: ❌ 异常"
                fi
            fi

            break
        fi
    done
}

# 选择网络接口
choose_network_interface() {
    # 检测网络接口
    detect_network_interfaces

    if [ ${#DETECTED_INTERFACES[@]} -eq 0 ]; then
        error "未检测到可用的网络接口"
        warn "请检查网络配置或手动指定接口"
        read -p "请输入网络接口名称: " custom_interface
        if [[ -n "$custom_interface" ]]; then
            INTERFACE="$custom_interface"
            success "已设置接口: $INTERFACE"
        else
            error "未指定网络接口"
            exit 1
        fi
        return
    fi

    highlight "检测到以下网络接口："
    echo

    # 显示接口列表
    local index=1
    for info in "${INTERFACE_INFO[@]}"; do
        IFS='|' read -r iface ip_addr state <<< "$info"

        # 设置状态显示
        local status_display=""
        if [[ "$state" == "UP" ]]; then
            status_display="✅ UP"
        else
            status_display="❌ DOWN"
        fi

        printf "%2d. %-15s %s %s\n" "$index" "$iface" "$status_display" "${ip_addr:-无IP}"
        ((index++))
    done

    echo
    echo "$(($index)). 自定义接口名称"
    echo "$(($index + 1)). 使用当前配置 ($INTERFACE)"
    echo

    while true; do
        read -p "请选择接口 (1-$(($index + 1))): " -r choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 && $choice -le ${#DETECTED_INTERFACES[@]} ]]; then
            local selected_index=$((choice - 1))
            INTERFACE="${DETECTED_INTERFACES[$selected_index]}"
            success "已选择接口: $INTERFACE"
            break
        elif [[ "$choice" == "$index" ]]; then
            read -p "请输入自定义接口名称: " custom_interface
            if [[ -n "$custom_interface" ]]; then
                INTERFACE="$custom_interface"
                success "已设置自定义接口: $INTERFACE"
                break
            else
                error "接口名称不能为空"
                continue
            fi
        elif [[ "$choice" == "$(($index + 1))" ]]; then
            info "保持当前配置: $INTERFACE"
            break
        else
            error "无效选择，请重新输入"
            continue
        fi
    done

    echo
    highlight "选择的接口详细信息："
    show_interface_details "$INTERFACE"
    echo

    # 确认选择
    read -p "确认使用此接口吗？(Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        success "已确认使用接口: $INTERFACE"
    else
        info "重新选择接口..."
        choose_network_interface
    fi
}

# 选择 IP 版本
choose_ip_version() {
    highlight "请选择 IP 版本："
    echo "1. IPv4 (推荐)"
    echo "2. IPv6"
    echo "3. 双栈 (IPv4 + IPv6)"
    echo "4. 使用当前配置 (IPv$IP_VERSION)"
    echo

    while true; do
        read -p "请选择 IP 版本 (1-4): " -n 1 -r
        echo

        case $REPLY in
            1)
                IP_VERSION="4"
                success "已选择 IPv4"
                break
                ;;
            2)
                IP_VERSION="6"
                success "已选择 IPv6"
                break
                ;;
            3)
                IP_VERSION="46"
                success "已选择双栈 (IPv4 + IPv6)"
                break
                ;;
            4)
                info "保持当前配置: IPv$IP_VERSION"
                break
                ;;
            *)
                error "无效选择，请重新输入"
                continue
                ;;
        esac
    done

    # 显示选择结果
    echo
    case $IP_VERSION in
        "4")
            info "将使用 IPv4 (-4 参数)"
            ;;
        "6")
            info "将使用 IPv6 (-6 参数)"
            ;;
        "46")
            info "将使用双栈 (IPv4 + IPv6，-4 和 -6 参数)"
            ;;
    esac
    echo
}

# 选择 TTL 值
choose_ttl() {
    highlight "请选择 TTL 值："
    echo "1. 5  (默认值，推荐)"
    echo "2. 10 (较高值)"
    echo "3. 15 (高值)"
    echo "4. 20 (更高值)"
    echo "5. 自定义"
    echo "6. 使用当前配置 ($TTL)"
    echo

    while true; do
        read -p "请选择 TTL 值 (1-6): " -n 1 -r
        echo

        case $REPLY in
            1)
                TTL="5"
                success "已选择 TTL: $TTL"
                break
                ;;
            2)
                TTL="10"
                success "已选择 TTL: $TTL"
                break
                ;;
            3)
                TTL="15"
                success "已选择 TTL: $TTL"
                break
                ;;
            4)
                TTL="20"
                success "已选择 TTL: $TTL"
                break
                ;;
            5)
                while true; do
                    read -p "请输入自定义 TTL 值 (1-255): " custom_ttl
                    if [[ "$custom_ttl" =~ ^[0-9]+$ ]] && [[ $custom_ttl -ge 1 && $custom_ttl -le 255 ]]; then
                        TTL="$custom_ttl"
                        success "已设置自定义 TTL: $TTL"
                        break
                    else
                        error "TTL 值必须是 1-255 之间的数字"
                        continue
                    fi
                done
                break
                ;;
            6)
                info "保持当前配置: $TTL"
                break
                ;;
            *)
                error "无效选择，请重新输入"
                continue
                ;;
        esac
    done

    echo
    info "TTL 值说明："
    echo "  • TTL 值决定数据包在网络中的生存时间"
    echo "  • 值越小，数据包传输距离越近"
    echo "  • 通常 5-20 之间的值适用于大多数场景"
    echo "  • 当前设置: $TTL"
    echo
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本需要 root 权限运行"
        echo "请使用: sudo $0 $*"
        exit 1
    fi
}

# 检测系统架构
detect_architecture() {
    local arch=$(uname -m)
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')

    case $arch in
        x86_64|amd64)
            arch="x86_64"
            ;;
        i386|i686)
            arch="i386"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        armv7l)
            arch="arm"
            ;;
        *)
            error "不支持的架构: $arch"
            exit 1
            ;;
    esac

    case $os in
        linux)
            os="linux"
            ;;
        darwin)
            os="darwin"
            ;;
        *)
            error "不支持的操作系统: $os"
            exit 1
            ;;
    esac

    echo "${os}-${arch}"
}

# 获取下载链接
get_download_url() {
    local platform=$(detect_architecture)
    local filename="fakehttp-${platform}.tar.gz"
    local base_url="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${filename}"

    # 根据下载方式返回不同的URL
    case "${DOWNLOAD_METHOD:-}" in
        "github-proxy")
            echo "${GITHUB_PROXY}${base_url}"
            ;;
        *)
            echo "$base_url"
            ;;
    esac
}

# 检查依赖
check_dependencies() {
    local deps=("curl" "tar" "systemctl")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        error "缺少依赖: ${missing[*]}"
        info "请安装缺少的依赖后重试"
        exit 1
    fi
}

# 检测是否需要代理
detect_proxy_need() {
    info "检测网络环境..."

    # 检查是否在中国大陆（通过检测能否访问GitHub）
    if curl -s --connect-timeout 5 https://api.github.com &> /dev/null; then
        info "直连 GitHub 正常，无需代理"
        return 1
    else
        warn "直连 GitHub 失败，可能需要代理"
        return 0
    fi
}

# 测试代理连接
test_proxy() {
    local proxy_url="$1"
    info "测试代理: $proxy_url"

    if curl -s --connect-timeout $PROXY_TIMEOUT --proxy "$proxy_url" https://api.github.com &> /dev/null; then
        success "代理连接测试成功"
        return 0
    else
        warn "代理连接测试失败"
        return 1
    fi
}

# 选择下载方式
choose_download_method() {
    highlight "请选择下载方式："
    echo "1. 直接下载 (从 GitHub 直接下载)"
    echo "2. 代理下载 (使用 HTTP 代理)"
    echo "3. 加速下载 (使用 GitHub 镜像代理)"
    echo "4. 退出安装"
    echo

    while true; do
        read -p "请选择 (1-4): " -n 1 -r
        echo

        case $REPLY in
            1)
                info "选择直接下载"
                DOWNLOAD_METHOD="direct"
                break
                ;;
            2)
                info "选择代理下载"
                # 测试默认代理
                if test_proxy "$DEFAULT_PROXY"; then
                    DOWNLOAD_METHOD="http-proxy"
                    export CURL_PROXY="$DEFAULT_PROXY"
                    break
                else
                    warn "默认代理不可用，请输入自定义代理地址"
                    read -p "代理地址 (格式: http://ip:port): " custom_proxy
                    if [[ -n "$custom_proxy" ]] && test_proxy "$custom_proxy"; then
                        DOWNLOAD_METHOD="http-proxy"
                        export CURL_PROXY="$custom_proxy"
                        break
                    else
                        error "代理测试失败，请重新选择"
                        continue
                    fi
                fi
                ;;
            3)
                info "选择加速下载"
                DOWNLOAD_METHOD="github-proxy"
                success "已选择 GitHub 镜像代理"
                break
                ;;
            4)
                info "退出安装"
                exit 0
                ;;
            *)
                error "无效选择，请重新输入"
                continue
                ;;
        esac
    done

    success "已选择下载方式: $DOWNLOAD_METHOD"
}

# 检查网络连接
check_network() {
    info "正在检测网络环境..."

    # 检查环境变量中的代理设置
    local proxy_url=""
    if [[ -n "$HTTP_PROXY" ]]; then
        proxy_url="$HTTP_PROXY"
    elif [[ -n "$http_proxy" ]]; then
        proxy_url="$http_proxy"
    elif [[ -n "$HTTPS_PROXY" ]]; then
        proxy_url="$HTTPS_PROXY"
    elif [[ -n "$https_proxy" ]]; then
        proxy_url="$https_proxy"
    fi

    # 如果环境变量中有代理，询问是否使用
    if [[ -n "$proxy_url" ]]; then
        info "检测到环境变量代理: $proxy_url"
        read -p "是否使用环境变量代理？(y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if test_proxy "$proxy_url"; then
                info "使用环境变量代理: $proxy_url"
                export CURL_PROXY="$proxy_url"
                DOWNLOAD_METHOD="http-proxy"
                return 0
            else
                warn "环境变量代理测试失败，请手动选择下载方式"
            fi
        fi
    fi

    # 让用户选择下载方式
    choose_download_method
}

# 停止现有服务
stop_existing_service() {
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        warn "停止现有的 $SERVICE_NAME 服务..."
        systemctl stop "$SERVICE_NAME"
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        warn "禁用 $SERVICE_NAME 服务..."
        systemctl disable "$SERVICE_NAME"
    fi
}

# 下载 FakeHTTP
download_fakehttp() {
    local download_url=$(get_download_url)
    local platform=$(detect_architecture)
    local temp_dir=$(mktemp -d)
    local filename="fakehttp-${platform}.tar.gz"

    info "检测到系统架构: $platform"

    # 检查是否已经安装了相同版本
    if [ -f "${INSTALL_DIR}/fakehttp" ]; then
        local current_version
        if current_version=$("${INSTALL_DIR}/fakehttp" --version 2>/dev/null | grep -o 'v[0-9.]*' | head -1); then
            if [ "$current_version" = "v${VERSION}" ]; then
                success "FakeHTTP ${VERSION} 已经安装，跳过下载"
                return 0
            else
                warn "检测到已安装版本 $current_version，将更新到 ${VERSION}"
            fi
        else
            warn "无法获取当前版本信息，继续安装"
        fi
    fi

    # 检查当前目录是否已有下载文件
    if [ -f "./${filename}" ]; then
        info "发现本地文件: ./${filename}"
        warn "是否使用本地文件？ (y/N)"
        read -p "" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            info "使用本地文件"
            cp "./${filename}" "${temp_dir}/${filename}"
            if [ $? -eq 0 ]; then
                success "本地文件复制完成"
                # 跳转到解压部分
                extract_and_install "$temp_dir" "$filename"
                return $?
            else
                error "本地文件复制失败，继续下载"
            fi
        else
            info "跳过本地文件，重新下载"
        fi
    fi

    info "下载 FakeHTTP ${VERSION}..."
    local download_url=$(get_download_url)
    info "下载链接: $download_url"

    # 根据下载方式显示不同信息
    case "$DOWNLOAD_METHOD" in
        "direct")
            info "使用直连下载"
            ;;
        "http-proxy")
            info "使用 HTTP 代理下载: $CURL_PROXY"
            ;;
        "github-proxy")
            info "使用 GitHub 镜像代理下载"
            ;;
    esac

    # 构建curl命令
    local curl_cmd="curl -L --progress-bar --fail --connect-timeout 10 --max-time 300"
    if [[ "$DOWNLOAD_METHOD" == "http-proxy" && -n "$CURL_PROXY" ]]; then
        curl_cmd="$curl_cmd --proxy $CURL_PROXY"
    fi

    # 下载文件
    if ! $curl_cmd -o "${temp_dir}/${filename}" "$download_url"; then
        error "下载失败: $download_url"

        echo
        highlight "请选择操作："
        echo "1. 重新选择下载方式"
        echo "2. 使用自动重试 (最多3次)"
        echo "3. 退出安装"
        echo
        read -p "请选择 (1-3): " -n 1 -r
        echo

        case $REPLY in
            1)
                info "重新选择下载方式..."
                choose_download_method
                # 重新调用下载函数
                download_fakehttp
                return $?
                ;;
            2)
                info "使用自动重试..."
                if retry_download "$temp_dir" "$filename"; then
                    success "重试下载成功！"
                else
                    error "重试下载失败"
                    rm -rf "$temp_dir"
                    exit 1
                fi
                ;;
            3)
                info "退出安装"
                rm -rf "$temp_dir"
                exit 0
                ;;
            *)
                error "无效选择"
                rm -rf "$temp_dir"
                exit 1
                ;;
        esac
    fi

    success "下载完成"

    extract_and_install "$temp_dir" "$filename"
}

# 解压和安装函数
extract_and_install() {
    local temp_dir="$1"
    local filename="$2"

    # 创建安装目录
    mkdir -p "$INSTALL_DIR"

    # 解压文件到临时目录
    info "解压文件..."
    local extract_temp=$(mktemp -d)
    if ! tar -xzf "${temp_dir}/${filename}" -C "$extract_temp"; then
        error "解压失败"
        rm -rf "$temp_dir" "$extract_temp"
        exit 1
    fi

    # 查找 fakehttp 二进制文件
    local fakehttp_binary=$(find "$extract_temp" -name "fakehttp" -type f | head -1)
    if [ -z "$fakehttp_binary" ]; then
        error "未找到 fakehttp 二进制文件"
        rm -rf "$temp_dir" "$extract_temp"
        exit 1
    fi

    info "找到二进制文件: $fakehttp_binary"
    info "复制到安装目录: ${INSTALL_DIR}/fakehttp"

    # 复制二进制文件到安装目录
    if ! cp "$fakehttp_binary" "${INSTALL_DIR}/fakehttp"; then
        error "复制文件失败"
        rm -rf "$temp_dir" "$extract_temp"
        exit 1
    fi

    # 设置可执行权限
    chmod +x "${INSTALL_DIR}/fakehttp"

    # 清理临时文件
    rm -rf "$temp_dir" "$extract_temp"

    success "FakeHTTP 安装完成"
}

# 创建管理脚本
create_manager_script() {
    local manager_script="${INSTALL_DIR}/fakehttp-manager.sh"

    info "创建管理脚本..."

    cat > "$manager_script" << EOF
#!/bin/bash

# FakeHTTP 管理脚本
# 用于启动和停止 fakehttp 服务

# 配置变量
FAKEHTTP_BIN="./fakehttp"
INTERFACE="$INTERFACE"
TTL="$TTL"
IP_VERSION="$IP_VERSION"
LOG_FILE="$LOG_FILE"
HOSTS=($(printf '"%s" ' "${HOSTS[@]}"))

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "\${GREEN}[\$(date '+%Y-%m-%d %H:%M:%S')]\${NC} \$1"
}

error() {
    echo -e "\${RED}[ERROR]\${NC} \$1" >&2
}

warn() {
    echo -e "\${YELLOW}[WARN]\${NC} \$1"
}

info() {
    echo -e "\${BLUE}[INFO]\${NC} \$1"
}

success() {
    echo -e "\${GREEN}[SUCCESS]\${NC} \$1"
}

highlight() {
    echo -e "\${CYAN}\${BOLD}\$1\${NC}"
}

# 检查 fakehttp 二进制文件是否存在
check_binary() {
    if [ ! -f "\$FAKEHTTP_BIN" ]; then
        error "FakeHTTP 二进制文件不存在: \$FAKEHTTP_BIN"
        exit 1
    fi

    if [ ! -x "\$FAKEHTTP_BIN" ]; then
        error "FakeHTTP 二进制文件没有执行权限: \$FAKEHTTP_BIN"
        exit 1
    fi
}

# 检查日志目录
check_log_dir() {
    local log_dir=\$(dirname "\$LOG_FILE")
    if [ ! -d "\$log_dir" ]; then
        warn "日志目录不存在，正在创建: \$log_dir"
        mkdir -p "\$log_dir" || {
            error "无法创建日志目录: \$log_dir"
            exit 1
        }
    fi
}

# 检查进程是否运行
is_running() {
    pgrep -f "fakehttp.*-d" > /dev/null 2>&1
}

# 显示配置信息
show_config() {
    highlight "FakeHTTP 配置信息:"
    echo "  二进制文件: \$FAKEHTTP_BIN"
    echo "  网络接口:   \$INTERFACE"
    echo "  TTL 值:     \$TTL"
    echo "  IP 版本:    IPv\$IP_VERSION"
    echo "  日志文件:   \$LOG_FILE"
    echo "  目标主机:   \${HOSTS[*]}"
    echo "  运行模式:   静默模式 (-s 参数)"
    echo
}

# 构建完整命令
build_command() {
    local cmd_args=""
    for host in "\${HOSTS[@]}"; do
        cmd_args="\$cmd_args -h \$host"
    done

    # 添加 IP 版本参数
    case "\$IP_VERSION" in
        "4")
            cmd_args="\$cmd_args -4"
            ;;
        "6")
            cmd_args="\$cmd_args -6"
            ;;
        "46")
            cmd_args="\$cmd_args -4 -6"
            ;;
    esac

    cmd_args="\$cmd_args -i \$INTERFACE -t \$TTL -d -s"

    echo "\$FAKEHTTP_BIN \$cmd_args"
}

# 启动 fakehttp
start_fakehttp() {
    log "正在检查 FakeHTTP 状态..."

    if is_running; then
        warn "FakeHTTP 已经在运行中"
        show_status
        return 0
    fi

    check_binary
    check_log_dir

    # 显示配置信息
    show_config

    # 构建并显示完整命令
    local full_command=\$(build_command)
    highlight "启动命令:"
    echo "  \$full_command"
    echo

    log "正在启动 FakeHTTP (静默模式)..."

    # 启动服务
    \$full_command

    # 等待一会儿检查启动状态
    sleep 2

    if is_running; then
        log "FakeHTTP 启动成功！"
        show_status
    else
        error "FakeHTTP 启动失败"
        # 静默模式下没有日志文件，显示系统日志
        echo "检查系统日志:"
        journalctl -u fakehttp --no-pager -n 10 2>/dev/null || echo "无法获取系统日志"
        exit 1
    fi
}

# 停止 fakehttp
stop_fakehttp() {
    log "正在停止 FakeHTTP..."

    if ! is_running; then
        warn "FakeHTTP 未在运行"
        return 0
    fi

    check_binary

    # 发送停止命令
    \$FAKEHTTP_BIN -k

    # 等待进程结束
    local count=0
    while is_running && [ \$count -lt 10 ]; do
        sleep 1
        ((count++))
    done

    if is_running; then
        error "FakeHTTP 停止失败，尝试强制终止..."
        pkill -f "fakehttp.*-d"
        sleep 2

        if is_running; then
            error "无法停止 FakeHTTP 进程"
            exit 1
        else
            warn "FakeHTTP 已被强制终止"
        fi
    else
        log "FakeHTTP 已成功停止"
    fi
}

# 重启 fakehttp
restart_fakehttp() {
    log "正在重启 FakeHTTP..."
    stop_fakehttp
    sleep 2
    start_fakehttp
}

# 显示状态
show_status() {
    if is_running; then
        local pid=\$(pgrep -f "fakehttp.*-d")
        log "FakeHTTP 正在运行 (PID: \$pid)"

        # 显示进程详细信息
        ps -p \$pid -o pid,ppid,user,cmd --no-headers 2>/dev/null | while read line; do
            info "进程信息: \$line"
        done

        # 显示网络接口信息
        if command -v ip &> /dev/null; then
            local interface_info=\$(ip addr show "\$INTERFACE" 2>/dev/null | grep -E "inet [0-9]" | head -1 | awk '{print \$2}' | cut -d'/' -f1)
            if [[ -n "\$interface_info" ]]; then
                info "网络接口: \$INTERFACE (\$interface_info)"
            else
                info "网络接口: \$INTERFACE (无IP)"
            fi
        else
            info "网络接口: \$INTERFACE"
        fi

        # 显示配置信息
        info "TTL 设置: \$TTL"
        info "IP 版本: IPv\$IP_VERSION"
        info "目标主机: \${HOSTS[*]}"
        info "运行模式: 静默模式 (无日志文件)"

        # 显示完整命令
        local full_command=\$(build_command)
        info "运行命令: \$full_command"
    else
        warn "FakeHTTP 未运行"
    fi
}

# 查看日志
view_logs() {
    local lines=\${1:-50}

    if [ ! -f "\$LOG_FILE" ]; then
        warn "日志文件不存在: \$LOG_FILE"
        info "当前运行在静默模式，无日志文件"
        return 1
    fi

    info "显示最近 \$lines 行日志:"
    echo "----------------------------------------"
    tail -n "\$lines" "\$LOG_FILE"
}

# 实时查看日志
tail_logs() {
    if [ ! -f "\$LOG_FILE" ]; then
        warn "日志文件不存在: \$LOG_FILE"
        info "当前运行在静默模式，无日志文件"
        return 1
    fi

    info "实时查看日志 (按 Ctrl+C 退出):"
    echo "----------------------------------------"
    tail -f "\$LOG_FILE"
}

# 显示帮助信息
show_help() {
    cat << HELP_EOF
FakeHTTP 管理脚本

用法: \$0 {start|stop|restart|status|config|logs|tail|help}

命令:
    start     启动 FakeHTTP 服务
    stop      停止 FakeHTTP 服务
    restart   重启 FakeHTTP 服务
    status    显示服务状态
    config    显示配置信息
    logs      查看日志 (默认最近50行)
    tail      实时查看日志
    help      显示此帮助信息

当前配置:
    接口:     \$INTERFACE
    TTL:      \$TTL
    IP版本:   IPv\$IP_VERSION
    日志文件: \$LOG_FILE
    主机列表: \${HOSTS[*]}
    静默模式: 已启用 (-s 参数)

示例:
    \$0 start          # 启动服务
    \$0 stop           # 停止服务
    \$0 status         # 查看状态
    \$0 config         # 显示配置
    \$0 logs 100       # 查看最近100行日志

HELP_EOF
}

# 主函数
main() {
    case "\${1:-}" in
        start)
            start_fakehttp
            ;;
        stop)
            stop_fakehttp
            ;;
        restart)
            restart_fakehttp
            ;;
        status)
            show_status
            ;;
        config)
            show_config
            ;;
        logs)
            view_logs "\${2:-50}"
            ;;
        tail)
            tail_logs
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            error "请指定操作命令"
            echo
            show_help
            exit 1
            ;;
        *)
            error "未知命令: \$1"
            echo
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "\$@"
EOF

    chmod +x "$manager_script"
    success "管理脚本创建完成: $manager_script"
}

# 创建 systemd 服务文件
create_systemd_service() {
    info "创建 systemd 服务文件..."

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=FakeHTTP Service
Documentation=FakeHTTP service for speed test domains
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/fakehttp-manager.sh start
ExecStop=${INSTALL_DIR}/fakehttp-manager.sh stop
ExecReload=${INSTALL_DIR}/fakehttp-manager.sh restart
Restart=on-failure
RestartSec=5
TimeoutStartSec=60
TimeoutStopSec=30
RemainAfterExit=yes

# 安全设置
NoNewPrivileges=false
PrivateTmp=false
ProtectSystem=false
ProtectHome=false

[Install]
WantedBy=multi-user.target
EOF

    success "Systemd 服务文件创建完成: $SERVICE_FILE"
}

# 启用并启动服务
enable_and_start_service() {
    info "重新加载 systemd 配置..."
    systemctl daemon-reload

    info "启用 $SERVICE_NAME 服务..."
    systemctl enable "$SERVICE_NAME"

    info "启动 $SERVICE_NAME 服务..."
    systemctl start "$SERVICE_NAME"

    # 检查服务状态
    sleep 3
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        success "$SERVICE_NAME 服务启动成功！"
        systemctl status "$SERVICE_NAME" --no-pager -l
    else
        error "$SERVICE_NAME 服务启动失败"
        systemctl status "$SERVICE_NAME" --no-pager -l
        exit 1
    fi
}

# 安装 FakeHTTP
install_fakehttp() {
    highlight "=== FakeHTTP 安装程序 ==="
    echo

    check_dependencies

    # 网络接口选择
    info "配置网络接口..."
    choose_network_interface

    # IP 版本选择
    info "配置 IP 版本..."
    choose_ip_version

    # TTL 选择
    info "配置 TTL 值..."
    choose_ttl

    check_network
    stop_existing_service

    download_fakehttp
    create_manager_script
    create_systemd_service
    enable_and_start_service

    echo
    success "FakeHTTP ${VERSION} 安装完成！"
    echo
    highlight "当前配置:"
    echo "  版本:       ${VERSION}"
    echo "  架构:       $(detect_architecture)"
    echo "  安装目录:   ${INSTALL_DIR}"
    echo "  网络接口:   ${INTERFACE}"
    echo "  IP 版本:    IPv${IP_VERSION}"
    echo "  TTL 值:     ${TTL}"
    echo "  目标主机:   ${HOSTS[*]}"
    echo "  服务名称:   ${SERVICE_NAME}"
    echo
    highlight "管理命令:"
    echo "  systemctl start $SERVICE_NAME     # 启动服务"
    echo "  systemctl stop $SERVICE_NAME      # 停止服务"
    echo "  systemctl restart $SERVICE_NAME   # 重启服务"
    echo "  systemctl status $SERVICE_NAME    # 查看状态"
    echo "  ${INSTALL_DIR}/fakehttp-manager.sh status  # 详细状态"
    echo "  ${INSTALL_DIR}/fakehttp-manager.sh config  # 查看配置"
    echo "  ${INSTALL_DIR}/fakehttp-manager.sh logs    # 查看日志"
    echo
}

# 卸载 FakeHTTP
uninstall_fakehttp() {
    highlight "=== FakeHTTP 卸载程序 ==="
    echo

    warn "即将卸载 FakeHTTP，这将删除所有相关文件"
    read -p "确定要继续吗？ (y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "取消卸载"
        exit 0
    fi

    # 停止并禁用服务
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        info "停止 $SERVICE_NAME 服务..."
        systemctl stop "$SERVICE_NAME"
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        info "禁用 $SERVICE_NAME 服务..."
        systemctl disable "$SERVICE_NAME"
    fi

    # 删除服务文件
    if [ -f "$SERVICE_FILE" ]; then
        info "删除服务文件: $SERVICE_FILE"
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi

    # 删除安装目录
    if [ -d "$INSTALL_DIR" ]; then
        info "删除安装目录: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
    fi

    success "FakeHTTP 卸载完成！"
}

# 显示版本信息
show_version() {
    if [ -f "${INSTALL_DIR}/fakehttp" ]; then
        echo "已安装版本: ${VERSION}"
        echo "安装路径: ${INSTALL_DIR}"
        echo "架构: $(detect_architecture)"

        # 显示配置信息
        echo "网络接口: ${INTERFACE}"
        echo "IP 版本: IPv${IP_VERSION}"
        echo "TTL 值: ${TTL}"
        echo "目标主机: ${HOSTS[*]}"

        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo "服务状态: 运行中"
        else
            echo "服务状态: 已停止"
        fi

        # 显示接口状态
        if command -v ip &> /dev/null; then
            local interface_info=$(ip addr show "$INTERFACE" 2>/dev/null | grep -E "inet [0-9]" | head -1 | awk '{print $2}' | cut -d'/' -f1)
            if [[ -n "$interface_info" ]]; then
                echo "接口状态: $INTERFACE ($interface_info)"
            else
                echo "接口状态: $INTERFACE (无IP)"
            fi
        fi
    else
        echo "FakeHTTP 未安装"
    fi
}

# 检查更新
check_update() {
    info "检查 FakeHTTP 更新..."

    # 这里可以添加检查最新版本的逻辑
    # 目前只显示当前配置的版本
    echo "当前配置版本: ${VERSION}"
    echo "如需更新，请修改脚本中的 VERSION 变量后重新安装"
}

# 显示帮助信息
show_help() {
    cat << EOF
FakeHTTP 安装和管理脚本

用法: $0 {install|uninstall|status|version|update|help}

命令:
    install      安装 FakeHTTP
    uninstall    卸载 FakeHTTP
    status       显示安装状态
    version      显示版本信息
    update       检查更新
    help         显示此帮助信息

配置信息:
    版本:        ${VERSION}
    安装目录:    ${INSTALL_DIR}
    服务名称:    ${SERVICE_NAME}
    日志文件:    ${LOG_FILE}
    网络接口:    ${INTERFACE}
    IP 版本:     IPv${IP_VERSION}
    TTL:         ${TTL}
    目标主机:    ${HOSTS[*]}

代理配置:
    默认代理:    ${DEFAULT_PROXY}
    自动检测:    ${USE_PROXY_AUTO}
    超时时间:    ${PROXY_TIMEOUT}秒

支持的架构:
    linux-x86_64, linux-i386, linux-arm64, linux-arm
    darwin-x86_64, darwin-arm64

IP 版本配置:
    - 支持 IPv4、IPv6 和双栈模式
    - IPv4 模式：使用 -4 参数，适合大多数环境
    - IPv6 模式：使用 -6 参数，适合 IPv6 网络
    - 双栈模式：同时使用 -4 和 -6 参数，支持 IPv4 和 IPv6
    - 安装时可交互选择 IP 版本

TTL 配置:
    - 支持自定义 TTL 值 (1-255)
    - 提供常用预设值：5、10、15、20
    - TTL 值决定数据包在网络中的生存时间
    - 值越小，数据包传输距离越近
    - 建议范围：5-20 适用于大多数场景

网络接口配置:
    - 安装时智能检测和推荐可用接口
    - 支持以太网、WiFi、虚拟接口等
    - 自动显示接口IP地址和连通状态
    - 可自定义接口名称

代理设置说明:
    1. 环境变量: HTTP_PROXY, http_proxy, HTTPS_PROXY, https_proxy
    2. 交互选择: 提供三种下载方式选择
       - 直接下载: 直接从 GitHub 下载
       - 代理下载: 使用 HTTP 代理下载 (默认: ${DEFAULT_PROXY})
       - 加速下载: 使用 GitHub 镜像代理下载 (${GITHUB_PROXY})
    3. 重试机制: 下载失败时可重新选择方式或自动重试

示例:
    $0 install                    # 安装 FakeHTTP (智能接口选择 + 交互下载方式)
    HTTP_PROXY=http://127.0.0.1:7890 $0 install  # 使用指定代理安装
    $0 uninstall                  # 卸载 FakeHTTP
    $0 status                     # 查看详细状态

网络接口选择:
    - 安装时自动检测所有可用网络接口
    - 智能推荐最适合的接口 (优先有IP的以太网接口)
    - 显示接口详细信息：IP地址、状态、类型、MAC地址等
    - 支持手动选择或自定义接口名称
    - 连通性测试确保接口可用

下载方式说明:
    1. 直接下载: 直接从 GitHub 下载，适合网络良好的环境
    2. 代理下载: 通过 HTTP 代理下载，适合有代理服务的环境
    3. 加速下载: 通过 ${GITHUB_PROXY} 下载，适合网络受限的环境

下载失败处理:
    - 可重新选择下载方式
    - 支持自动重试 (最多3次)
    - 每次重试都可选择不同的下载方式

安装后管理:
    systemctl start fakehttp     # 启动服务
    systemctl stop fakehttp      # 停止服务
    systemctl status fakehttp    # 查看服务状态
    ${INSTALL_DIR}/fakehttp-manager.sh status  # 详细状态
    ${INSTALL_DIR}/fakehttp-manager.sh config  # 查看配置

配置管理:
    - 重新安装时可重新选择网络接口、IP 版本和 TTL 值
    - 管理脚本显示当前接口状态和完整配置
    - 支持查看接口IP地址和连通性
    - 配置修改后需重新安装服务

EOF
}

# 主函数
main() {
    case "${1:-}" in
        install)
            check_root "$@"
            install_fakehttp
            ;;
        uninstall)
            check_root "$@"
            uninstall_fakehttp
            ;;
        status)
            show_version
            ;;
        version)
            show_version
            ;;
        update)
            check_update
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            error "请指定操作命令"
            echo
            show_help
            exit 1
            ;;
        *)
            error "未知命令: $1"
            echo
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"

# 重试下载函数
retry_download() {
    local temp_dir="$1"
    local filename="$2"
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        info "尝试重新下载 (第 $((retry_count + 1)) 次)..."

        # 重新选择下载方式
        choose_download_method

        # 构建下载命令
        local download_url=$(get_download_url)
        local curl_cmd="curl -L --progress-bar --fail --connect-timeout 10 --max-time 300"

        if [[ "$DOWNLOAD_METHOD" == "http-proxy" && -n "$CURL_PROXY" ]]; then
            curl_cmd="$curl_cmd --proxy $CURL_PROXY"
        fi

        info "下载链接: $download_url"
        info "使用方式: $DOWNLOAD_METHOD"

        # 尝试下载
        if $curl_cmd -o "${temp_dir}/${filename}" "$download_url"; then
            success "下载成功！"
            return 0
        else
            error "下载失败 (第 $((retry_count + 1)) 次尝试)"
            ((retry_count++))

            if [ $retry_count -lt $max_retries ]; then
                warn "将在 3 秒后重试..."
                sleep 3
            fi
        fi
    done

    error "已达到最大重试次数 ($max_retries)，下载失败"
    return 1
}
