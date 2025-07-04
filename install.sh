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

# 网络配置
INTERFACE="eno1-ovs"
TTL="5"
HOSTS=("www.speedtest.net" "speed.nuaa.edu.cn")

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

# 简单的网络连接测试
test_network_connectivity() {
    local test_sites=("github.com" "api.github.com")
    local results=()
    
    info "测试网络连接状态..."
    
    for site in "${test_sites[@]}"; do
        if curl -s --connect-timeout 3 --max-time 5 "https://$site" &> /dev/null; then
            results+=("$site: ✓ 可达")
        else
            results+=("$site: ✗ 不可达")
        fi
    done
    
    for result in "${results[@]}"; do
        echo "  $result"
    done
    
    # 测试镜像代理
    if curl -s --connect-timeout 5 --max-time 8 "${GITHUB_PROXY}https://github.com" &> /dev/null; then
        echo "  镜像代理: ✓ 可用"
    else
        echo "  镜像代理: ✗ 不可用"
    fi
    
    echo
}

# 选择下载方式
choose_download_method() {
    # 显示网络连接状态
    test_network_connectivity
    
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
    
    cat > "$manager_script" << 'EOF'
#!/bin/bash

# FakeHTTP 管理脚本
# 用于启动和停止 fakehttp 服务

# 配置变量
FAKEHTTP_BIN="./fakehttp"
INTERFACE="eno1-ovs"
TTL="5"
LOG_FILE="/vol2/1000/fake/fakehttp.log"
HOSTS=("www.speedtest.net" "speed.nuaa.edu.cn")

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# 检查 fakehttp 二进制文件是否存在
check_binary() {
    if [ ! -f "$FAKEHTTP_BIN" ]; then
        error "FakeHTTP 二进制文件不存在: $FAKEHTTP_BIN"
        exit 1
    fi
    
    if [ ! -x "$FAKEHTTP_BIN" ]; then
        error "FakeHTTP 二进制文件没有执行权限: $FAKEHTTP_BIN"
        exit 1
    fi
}

# 检查日志目录
check_log_dir() {
    local log_dir=$(dirname "$LOG_FILE")
    if [ ! -d "$log_dir" ]; then
        warn "日志目录不存在，正在创建: $log_dir"
        mkdir -p "$log_dir" || {
            error "无法创建日志目录: $log_dir"
            exit 1
        }
    fi
}

# 检查进程是否运行
is_running() {
    pgrep -f "fakehttp.*-d" > /dev/null 2>&1
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
    
    # 构建命令参数 (添加 -s 静默模式，不需要 -w 参数)
    local cmd_args=""
    for host in "${HOSTS[@]}"; do
        cmd_args="$cmd_args -h $host"
    done
    cmd_args="$cmd_args -i $INTERFACE -t $TTL -d -s"
    
    log "正在启动 FakeHTTP (静默模式)..."
    info "命令: $FAKEHTTP_BIN $cmd_args"
    
    # 启动服务
    $FAKEHTTP_BIN $cmd_args
    
    # 等待一会儿检查启动状态
    sleep 2
    
    if is_running; then
        log "FakeHTTP 启动成功！"
        show_status
    else
        error "FakeHTTP 启动失败"
        # 静默模式下没有日志文件，显示系统日志
        echo "检查系统日志:"
        journalctl -u fakehttp --no-pager -n 10
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
    $FAKEHTTP_BIN -k
    
    # 等待进程结束
    local count=0
    while is_running && [ $count -lt 10 ]; do
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
        local pid=$(pgrep -f "fakehttp.*-d")
        log "FakeHTTP 正在运行 (PID: $pid)"
        
        # 显示进程详细信息
        ps -p $pid -o pid,ppid,user,cmd --no-headers 2>/dev/null | while read line; do
            info "进程信息: $line"
        done
        
        # 静默模式下没有日志文件
        info "运行模式: 静默模式 (无日志文件)"
    else
        warn "FakeHTTP 未运行"
    fi
}

# 查看日志
view_logs() {
    local lines=${1:-50}
    
    if [ ! -f "$LOG_FILE" ]; then
        warn "日志文件不存在: $LOG_FILE"
        return 1
    fi
    
    info "显示最近 $lines 行日志:"
    echo "----------------------------------------"
    tail -n "$lines" "$LOG_FILE"
}

# 实时查看日志
tail_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        warn "日志文件不存在: $LOG_FILE"
        return 1
    fi
    
    info "实时查看日志 (按 Ctrl+C 退出):"
    echo "----------------------------------------"
    tail -f "$LOG_FILE"
}

# 显示帮助信息
show_help() {
    cat << HELP_EOF
FakeHTTP 管理脚本

用法: $0 {start|stop|restart|status|logs|tail|help}

命令:
    start     启动 FakeHTTP 服务
    stop      停止 FakeHTTP 服务  
    restart   重启 FakeHTTP 服务
    status    显示服务状态
    logs      查看日志 (默认最近50行)
    tail      实时查看日志
    help      显示此帮助信息

配置:
    接口:     $INTERFACE
    TTL:      $TTL
    日志文件: $LOG_FILE
    主机列表: ${HOSTS[*]}
    静默模式: 已启用 (-s 参数)

示例:
    $0 start          # 启动服务
    $0 stop           # 停止服务
    $0 status         # 查看状态
    $0 logs 100       # 查看最近100行日志

HELP_EOF
}

# 主函数
main() {
    case "${1:-}" in
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
        logs)
            view_logs "${2:-50}"
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
            error "未知命令: $1"
            echo
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
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
    check_network
    stop_existing_service
    
    download_fakehttp
    create_manager_script
    create_systemd_service
    enable_and_start_service
    
    echo
    success "FakeHTTP ${VERSION} 安装完成！"
    echo
    highlight "管理命令:"
    echo "  systemctl start $SERVICE_NAME     # 启动服务"
    echo "  systemctl stop $SERVICE_NAME      # 停止服务"
    echo "  systemctl restart $SERVICE_NAME   # 重启服务"
    echo "  systemctl status $SERVICE_NAME    # 查看状态"
    echo "  ${INSTALL_DIR}/fakehttp-manager.sh status  # 详细状态"
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
        
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo "服务状态: 运行中"
        else
            echo "服务状态: 已停止"
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
    TTL:         ${TTL}
    目标主机:    ${HOSTS[*]}

代理配置:
    默认代理:    ${DEFAULT_PROXY}
    自动检测:    ${USE_PROXY_AUTO}
    超时时间:    ${PROXY_TIMEOUT}秒

支持的架构:
    linux-x86_64, linux-i386, linux-arm64, linux-arm
    darwin-x86_64, darwin-arm64

代理设置说明:
    1. 环境变量: HTTP_PROXY, http_proxy, HTTPS_PROXY, https_proxy
    2. 交互选择: 提供三种下载方式选择
       - 直接下载: 直接从 GitHub 下载
       - 代理下载: 使用 HTTP 代理下载 (默认: ${DEFAULT_PROXY})
       - 加速下载: 使用 GitHub 镜像代理下载 (${GITHUB_PROXY})
    3. 重试机制: 下载失败时可重新选择方式或自动重试

示例:
    $0 install                    # 安装 FakeHTTP (交互选择下载方式)
    HTTP_PROXY=http://127.0.0.1:7890 $0 install  # 使用指定代理安装
    $0 uninstall                  # 卸载 FakeHTTP
    $0 status                     # 查看状态

下载方式说明:
    1. 直接下载: 直接从 GitHub 下载，适合网络良好的环境
    2. 代理下载: 通过 HTTP 代理下载，适合有代理服务的环境
    3. 加速下载: 通过 ${GITHUB_PROXY} 下载，适合网络受限的环境

下载失败处理:
    - 可重新选择下载方式
    - 支持自动重试 (最多3次)
    - 每次重试都可选择不同的下载方式

安装后管理:
    systemctl start fakehttp
    systemctl stop fakehttp
    ${INSTALL_DIR}/fakehttp-manager.sh status

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
