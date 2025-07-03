# FakeHTTP 安装和管理脚本

一个功能完整的 FakeHTTP 自动化安装和管理脚本，支持多种下载方式和系统架构。

## 📋 功能特性

- ✅ **多架构支持**: 自动检测系统架构 (x86_64, i386, arm64, arm)
- ✅ **多下载方式**: 直连、HTTP代理、GitHub镜像代理
- ✅ **智能网络检测**: 自动检测网络环境并推荐最佳下载方式
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
| 网络接口 | eno1 | 网络接口名称 |
| TTL | 5 | 数据包 TTL 值 |
| 目标主机 | www.speedtest.net, speed.nuaa.edu.cn | 拦截的域名 |

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
2. **网络检测**: 检测网络环境，选择最佳下载方式
3. **下载安装**: 下载并安装 FakeHTTP 二进制文件
4. **服务配置**: 创建 systemd 服务和管理脚本
5. **启动服务**: 自动启动并设置开机自启

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

编辑 `install.sh` 文件，修改以下变量：

```bash
# 版本配置
VERSION="0.9.18"

# 安装目录
INSTALL_DIR="/vol2/1000/fake"

# 网络配置
INTERFACE="eno1"
TTL="5"
HOSTS=("www.speedtest.net" "speed.nuaa.edu.cn")

# 代理配置
DEFAULT_PROXY="http://192.168.31.175:7890"
GITHUB_PROXY="https://gh-proxy.com/"
```

### 添加新的目标主机

```bash
# 编辑配置
HOSTS=("www.speedtest.net" "speed.nuaa.edu.cn" "your-domain.com")
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

---

**注意**: 使用本脚本前请确保你了解 FakeHTTP 的工作原理和潜在影响。
