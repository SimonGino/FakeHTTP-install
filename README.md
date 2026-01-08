# FakeHTTP 管理工具

一个功能完整的 FakeHTTP 安装、配置和管理脚本，支持交互式菜单和命令行两种模式。

## 📋 功能特性

- ✅ **多架构支持**: 自动检测系统架构 (x86_64, i386, arm64, arm)
- ✅ **多下载方式**: 直连、HTTP代理、GitHub镜像代理（自动探测最佳镜像）
- ✅ **交互式菜单**: 完整的图形化菜单，方便操作
- ✅ **命令行模式**: 支持 start/stop/restart/status 等命令
- ✅ **独立配置文件**: `config.conf` 配置与脚本分离，便于管理
- ✅ **NFQUEUE 智能管理**: 自动检测队列冲突、避让并落盘
- ✅ **进程管理**: 精确进程匹配、残留清理、PID 文件管理
- ✅ **systemd 服务**: 自动创建系统服务，支持开机自启
- ✅ **Payload 支持**: 支持 `-b` 参数加载自定义 payload 文件
- ✅ **完整卸载**: 一键完全卸载所有相关文件

## 🚀 快速开始

### 安装

```bash
# 下载脚本
wget https://raw.githubusercontent.com/SimonGino/FakeHTTP-install/main/fakehttp.sh
# 或者
curl -O https://raw.githubusercontent.com/SimonGino/FakeHTTP-install/main/fakehttp.sh

# 添加执行权限
chmod +x fakehttp.sh

# 运行交互式菜单（推荐首次使用）
sudo ./fakehttp.sh
```

### 基本命令

```bash
# 交互式菜单
sudo ./fakehttp.sh

# 启动服务
sudo ./fakehttp.sh start

# 停止服务
sudo ./fakehttp.sh stop

# 重启服务
sudo ./fakehttp.sh restart

# 查看状态
./fakehttp.sh status

# 显示帮助
./fakehttp.sh --help
```

## 📦 配置文件

配置保存在脚本同目录的 `config.conf` 文件中：

```bash
# FakeHTTP 配置文件示例
INTERFACES=("eno1")              # 网络接口，留空使用所有接口
HOSTS=("www.speedtest.net")      # -h HTTP 域名
EXCLUDES=()                      # -e HTTPS/TLS 域名
PAYLOADS=("payload01.bin")       # -b Payload 文件

TTL="5"                          # TTL 值
IP_VERSION="4"                   # 4=IPv4, 6=IPv6, 46=双栈

QUEUE_NUM="1000"                 # NFQUEUE 队列号（自动避让）
AUTO_FIX_QUEUE="true"            # 队列冲突时自动寻找可用队列

RUN_DAEMON="false"               # 是否使用 fakehttp -d 模式
SILENT="false"                   # 是否默认静默 (-s)
```

### 配置说明

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `INTERFACES` | `()` (所有) | 网络接口列表，留空使用 `-a` 所有接口 |
| `HOSTS` | `()` | HTTP 域名列表 (`-h` 参数) |
| `EXCLUDES` | `()` | HTTPS/TLS 域名列表 (`-e` 参数) |
| `PAYLOADS` | `()` | Payload 二进制文件列表 (`-b` 参数) |
| `TTL` | `5` | 数据包 TTL 值 |
| `IP_VERSION` | `4` | IP 版本：4/6/46 |
| `QUEUE_NUM` | `1000` | NFQUEUE 队列号 |
| `AUTO_FIX_QUEUE` | `true` | 队列冲突时自动避让 |

## 🛠️ 服务管理

### 命令行模式

```bash
# 启动（自动清理残留进程、自动避让队列）
sudo ./fakehttp.sh start

# 停止
sudo ./fakehttp.sh stop

# 重启
sudo ./fakehttp.sh restart

# 查看状态
./fakehttp.sh status

# 前台运行（给 systemd 使用）
sudo ./fakehttp.sh run
```

### 交互式菜单

运行 `sudo ./fakehttp.sh` 进入交互式菜单：

```
╔═══════════════════════════════════════════════════════════╗
║              FakeHTTP 管理工具 v3.4.0                     ║
╚═══════════════════════════════════════════════════════════╝

状态: ● 运行中 (PID: 12345)

【主菜单】

  1. 查看状态
  2. 启动
  3. 停止
  4. 重启
  5. 查看日志
  6. 配置管理
  7. systemd 服务
  8. 安装/更新
  9. 卸载
  0. 退出
```

### systemd 服务

```bash
# 通过菜单创建 systemd 服务后：
sudo systemctl start fakehttp
sudo systemctl stop fakehttp
sudo systemctl restart fakehttp
sudo systemctl status fakehttp
sudo systemctl enable fakehttp   # 开机自启
sudo systemctl disable fakehttp  # 禁用自启
```

## 📋 命令参考

| 命令 | 说明 |
|------|------|
| `(无参数)` | 进入交互式菜单 |
| `start` | 后台启动服务 |
| `stop` | 停止服务 |
| `restart` | 重启服务 |
| `status` | 显示运行状态 |
| `run` | 前台运行（systemd 专用） |
| `-h, --help` | 显示帮助信息 |

## 🔧 高级功能

### NFQUEUE 智能管理

脚本会自动处理 NFQUEUE 队列冲突：

1. 启动前检测 `QUEUE_NUM` 是否被占用
2. 如果 `AUTO_FIX_QUEUE=true`，自动向上寻找空闲队列
3. 新队列号自动写入 `config.conf`

### 进程管理

- 启动前自动清理残留进程和 PID 文件
- 精确匹配进程路径，避免误杀其他进程
- 停止时优先使用 `fakehttp -k`，超时后 SIGTERM，最后 SIGKILL

### Payload 文件

将 `.bin` 文件放在脚本同目录，配置向导会自动检测：

```bash
PAYLOADS=("payload01.bin" "payload03.bin" "payload04.bin")
```

## 📁 文件结构

```
./
├── fakehttp.sh          # 管理脚本
├── config.conf          # 配置文件
├── fakehttp-bin         # FakeHTTP 二进制文件（安装后生成）
├── fakehttp.log         # 运行日志
├── .pid                 # PID 文件
└── *.bin                # Payload 文件（可选）
```

## 🔍 故障排除

### 常见问题

**1. 队列被占用**
```bash
# 脚本会自动避让，也可以手动指定：
# 编辑 config.conf，修改 QUEUE_NUM
```

**2. 权限问题**
```bash
# 需要 root 权限
sudo ./fakehttp.sh start
```

**3. 服务启动失败**
```bash
# 查看日志
tail -f fakehttp.log

# 查看 systemd 日志
sudo journalctl -u fakehttp -f
```

**4. 下载失败**
```bash
# 脚本支持多镜像源自动探测
# 也可以选择 HTTP 代理下载
```

### 日志位置

- **运行日志**: `./fakehttp.log`
- **systemd 日志**: `journalctl -u fakehttp`

## 🏗️ 支持的系统架构

| 系统 | 架构 | 支持状态 |
|------|------|----------|
| Linux | x86_64 | ✅ |
| Linux | i386 | ✅ |
| Linux | arm64 | ✅ |
| Linux | arm | ✅ |

## 📄 许可证

本项目使用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🔗 相关链接

- [FakeHTTP 官方仓库](https://github.com/MikeWang000000/FakeHTTP)

## 📞 支持

如果你遇到问题或有建议，请：

1. 查看上方故障排除部分
2. 搜索现有的 [Issues](https://github.com/SimonGino/FakeHTTP-install/issues)
3. 创建新的 [Issue](https://github.com/SimonGino/FakeHTTP-install/issues/new)
