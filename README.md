# FakeHTTP 安装和管理脚本

一个功能完整的 FakeHTTP 自动化安装和管理脚本，支持多种下载方式和系统架构。

## 📋 功能特性

- ✅ **多架构支持**: 自动检测系统架构 (x86_64, i386, arm64, arm)
- ✅ **多下载方式**: 直连、HTTP代理、GitHub镜像代理
- ✅ **智能网络检测**: 自动检测网络环境并推荐最佳下载方式
- ✅ **交互式配置**: 自定义网络接口、TTL值、主机列表
- ✅ **自动检测网口**: 检测所有可用网络接口 (如: eno1, eno1-ovs, pppoe-wan等)
- ✅ **预设主机列表**: 包含常用的 B站、抖音、网盘等域名
- ✅ **systemd 服务**: 自动创建系统服务，支持开机自启
- ✅ **管理脚本**: 完整的服务管理脚本
- ✅ **版本检测**: 避免重复安装相同版本
- ✅ **本地文件支持**: 可使用本地下载的文件进行安装
- ✅ **完整卸载**: 一键完全卸载所有相关文件

## 🚀 快速开始

### 安装

```bash
# 下载脚本
wget https://raw.githubusercontent.com/SimonGino/FakeHTTP-install/main/install.sh
# 或者
curl -O https://raw.githubusercontent.com/SimonGino/FakeHTTP-install/main/install.sh

# 添加执行权限
chmod +x install.sh

# 运行安装
sudo ./install.sh install
```

### 基本命令

```bash
# 安装 FakeHTTP
sudo ./install.sh install

# 查看状态
./install.sh status

# 卸载
sudo ./install.sh uninstall

# 显示帮助
./install.sh help
```

## 📦 配置信息

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| 版本 | 0.9.18 | FakeHTTP 版本 |
| 安装目录 | /vol2/1000/fake | 安装路径 |
| 服务名称 | fakehttp | systemd 服务名 |
| 网络接口 | eno1 | 网络接口名称 (安装时可选择) |
| TTL | 5 | 数据包 TTL 值 (安装时可自定义) |
| 默认主机 | www.speedtest.net, speed.nuaa.edu.cn | 默认拦截的域名 |

### 预设主机列表

脚本提供了丰富的预设主机列表供选择：

- **网络测试**: www.speedtest.net, speed.nuaa.edu.cn
- **B站相关**: upos-sz-mirrorcos.bilivideo.com, member.bilibili.com, upos-cs-upcdnqn.bilivideo.com 等
- **抖音相关**: creator.douyin.com, p3-pc-sign.douyinpic.com
- **网盘相关**: pan.wo.cn

## 🌐 下载方式

脚本支持三种下载方式，会根据网络环境自动选择或让用户手动选择：

### 1. 直接下载
- **适用场景**: 海外服务器或网络畅通的环境
- **下载源**: 直接从 GitHub 官方仓库下载
- **优点**: 速度快，稳定可靠

### 2. HTTP 代理下载
- **适用场景**: 有本地代理服务的环境
- **默认代理**: `http://192.168.31.175:7890`
- **支持**: 自定义代理地址
- **环境变量**: 支持 `HTTP_PROXY`, `HTTPS_PROXY` 等

### 3. GitHub 镜像代理下载 (推荐)
- **适用场景**: 国内网络环境
- **镜像地址**: `https://gh-proxy.com/`
- **优点**: 国内访问速度快，无需配置代理

## 🔧 使用方法

### 安装过程

1. **依赖检查**: 自动检查 `curl`, `tar`, `systemctl` 等依赖
2. **交互式配置**: 选择网络接口、TTL值、主机列表
3. **网络检测**: 检测网络环境，选择最佳下载方式
4. **下载安装**: 下载并安装 FakeHTTP 二进制文件
5. **服务配置**: 创建 systemd 服务和管理脚本
6. **启动服务**: 自动启动并设置开机自启

### 交互式配置

安装时会提供以下配置选项：

#### 网络接口选择
- 自动检测所有可用网络接口
- 支持选择检测到的接口 (如: eno1, eno1-ovs, pppoe-wan等)
- 支持手动输入接口名称
- 可使用默认接口

#### TTL值设置
- 使用默认值 (5)
- 自定义TTL值 (1-255)

#### 主机列表配置
- 使用默认主机列表
- 从预设列表中选择 (支持多选)
- 手动输入自定义主机列表

### 交互式下载方式选择

当网络检测到无法直连 GitHub 时，会提示选择下载方式：

```
请选择下载方式：
1. 直接下载 (可能失败)
2. 使用 HTTP 代理下载  
3. 使用 GitHub 镜像代理下载 (推荐)
4. 退出安装

请选择 (1-4):
```

### 环境变量支持

```bash
# 使用指定代理安装
HTTP_PROXY=http://127.0.0.1:7890 sudo ./install.sh install

# 使用 HTTPS 代理
HTTPS_PROXY=http://proxy.example.com:8080 sudo ./install.sh install
```

## 🛠️ 服务管理

安装完成后，可以使用以下命令管理 FakeHTTP 服务：

### systemctl 命令
```bash
# 启动服务
sudo systemctl start fakehttp

# 停止服务  
sudo systemctl stop fakehttp

# 重启服务
sudo systemctl restart fakehttp

# 查看状态
sudo systemctl status fakehttp

# 开机自启
sudo systemctl enable fakehttp

# 禁用自启
sudo systemctl disable fakehttp
```

### 管理脚本
```bash
# 进入安装目录
cd /vol2/1000/fake

# 启动服务
./fakehttp-manager.sh start

# 停止服务
./fakehttp-manager.sh stop

# 重启服务
./fakehttp-manager.sh restart

# 查看状态
./fakehttp-manager.sh status

# 查看日志
./fakehttp-manager.sh logs

# 实时日志
./fakehttp-manager.sh tail

# 查看配置信息
./fakehttp-manager.sh config
```

## 📋 命令参考

### 安装脚本命令

| 命令 | 说明 |
|------|------|
| `install` | 安装 FakeHTTP |
| `uninstall` | 卸载 FakeHTTP |
| `status` | 显示安装状态 |
| `version` | 显示版本信息 |
| `update` | 检查更新 |
| `help` | 显示帮助信息 |

### 管理脚本命令

| 命令 | 说明 |
|------|------|
| `start` | 启动 FakeHTTP 服务 |
| `stop` | 停止 FakeHTTP 服务 |
| `restart` | 重启 FakeHTTP 服务 |
| `status` | 显示服务状态 |
| `config` | 显示配置信息 |
| `logs [行数]` | 查看日志 (默认50行) |
| `tail` | 实时查看日志 |
| `help` | 显示帮助信息 |

## 🔍 故障排除

### 常见问题

**1. 下载失败**
```bash
# 检查网络连接
curl -I https://api.github.com

# 尝试不同下载方式
sudo ./install.sh install
# 然后选择其他下载方式
```

**2. 权限问题**
```bash
# 确保使用 root 权限
sudo ./install.sh install
```

**3. 服务启动失败**
```bash
# 查看服务状态
sudo systemctl status fakehttp

# 查看详细日志
sudo journalctl -u fakehttp -f

# 检查二进制文件
ls -la /vol2/1000/fake/fakehttp
```

**4. 代理配置问题**
```bash
# 测试代理连接
curl --proxy http://your-proxy:port https://api.github.com

# 检查环境变量
echo $HTTP_PROXY
echo $HTTPS_PROXY
```

### 日志位置

- **安装日志**: 实时显示在终端
- **服务日志**: `sudo journalctl -u fakehttp`
- **应用日志**: `/vol2/1000/fake/fakehttp.log` (如果启用)

## 🏗️ 支持的系统架构

| 系统 | 架构 | 支持状态 |
|------|------|----------|
| Linux | x86_64 | ✅ |
| Linux | i386 | ✅ |
| Linux | arm64 | ✅ |
| Linux | arm | ✅ |
| macOS | x86_64 | ✅ |
| macOS | arm64 | ✅ |

## 📁 文件结构

安装完成后的文件结构：

```
/vol2/1000/fake/
├── fakehttp                    # 主程序二进制文件
├── fakehttp-manager.sh         # 管理脚本
└── fakehttp.log               # 日志文件 (如果启用)

/etc/systemd/system/
└── fakehttp.service           # systemd 服务文件
```

## 🔧 自定义配置

### 修改配置参数

#### 方法1：重新安装 (推荐)
```bash
# 重新安装会启动交互式配置
sudo ./install.sh install
```

#### 方法2：手动修改脚本
编辑 `install.sh` 文件，修改以下变量：

```bash
# 版本配置
VERSION="0.9.18"

# 安装目录
INSTALL_DIR="/vol2/1000/fake"

# 默认网络配置
DEFAULT_INTERFACE="eno1"
DEFAULT_TTL="5"
DEFAULT_HOSTS=("www.speedtest.net" "speed.nuaa.edu.cn")

# 预设主机列表
PRESET_HOSTS=(
    "www.speedtest.net"
    "speed.nuaa.edu.cn"
    "creator.douyin.com"
    "p3-pc-sign.douyinpic.com"
    "upos-sz-mirrorcos.bilivideo.com"
    "member.bilibili.com"
    "pan.wo.cn"
    # 添加更多主机...
)

# 代理配置
DEFAULT_PROXY="http://192.168.31.175:7890"
GITHUB_PROXY="https://gh-proxy.com/"
```

### 添加新的目标主机

#### 方法1：安装时选择
在安装过程中选择 "从预设列表中选择" 或 "手动输入主机列表"

#### 方法2：修改预设列表
```bash
# 编辑 install.sh 文件，在 PRESET_HOSTS 数组中添加
PRESET_HOSTS=(
    "www.speedtest.net"
    "speed.nuaa.edu.cn"
    "your-custom-domain.com"  # 添加自定义域名
    "another-domain.com"      # 添加更多域名
)
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进这个脚本！

### 开发指南

1. Fork 本仓库
2. 创建特性分支: `git checkout -b feature/amazing-feature`
3. 提交更改: `git commit -m 'Add amazing feature'`
4. 推送到分支: `git push origin feature/amazing-feature`
5. 提交 Pull Request

## 📄 许可证

本项目使用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🔗 相关链接

- [FakeHTTP 官方仓库](https://github.com/MikeWang000000/FakeHTTP)
- [GitHub 镜像代理](https://gh-proxy.com/)
- [systemd 文档](https://systemd.io/)

## 📞 支持

如果你遇到问题或有建议，请：

1. 查看 [FAQ](#故障排除) 部分
2. 搜索现有的 [Issues](https://github.com/SimonGino/FakeHTTP-install/issues)
3. 创建新的 [Issue](https://github.com/SimonGino/FakeHTTP-install/issues/new)

## 🔧 高级功能

### 自动网络接口检测

脚本会自动检测系统中所有可用的网络接口，包括：

- 标准以太网接口 (eth0, eno1, enp0s3等)
- Open vSwitch接口 (eno1-ovs, br0等)
- PPPoE接口 (pppoe-wan等)
- 虚拟接口 (veth, docker等)

### 智能主机选择

支持多种主机配置方式：

#### 1. 默认主机列表
适用于一般网络优化场景

#### 2. 预设主机列表
包含常用服务的域名：
- **视频平台**: B站上传、抖音创作相关域名
- **网盘服务**: 各种网盘的上传域名
- **网络测试**: 测速网站域名

#### 3. 自定义主机列表
支持输入任意域名列表

### 配置示例

#### 针对B站上传优化
```bash
# 选择以下主机
upos-sz-mirrorcos.bilivideo.com
member.bilibili.com  
upos-cs-upcdnqn.bilivideo.com
upos-cs-upcdnbldsa.bilivideo.com
upos-sz-upcdnws.bilivideo.com
upos-cs-upcdnbda2.bilivideo.com
upos-cs-upcdntx.bilivideo.com
```

#### 针对抖音创作优化
```bash
# 选择以下主机
creator.douyin.com
p3-pc-sign.douyinpic.com
```

#### 针对网盘上传优化
```bash
# 选择以下主机
pan.wo.cn
```

---

**注意**: 使用本脚本前请确保你了解 FakeHTTP 的工作原理和潜在影响。新版本提供了更灵活的配置选项，请根据实际需求选择合适的网络接口和主机列表。
