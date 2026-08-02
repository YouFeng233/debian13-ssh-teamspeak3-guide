# Debian 13 一键安装 TeamSpeak 3：新手部署教程

这是给想自己搭建 TeamSpeak 服务器的用户准备的中文教程。你不需要预先熟悉 Linux：按 README 的命令即可完成 Debian 13 的基础初始化和 TeamSpeak 3 安装；需要更严格的 SSH、域名或频道权限配置时，再按完整教程继续操作。

所有公网地址、域名、端口、密钥、密码和 Token 都以占位符表示；请替换为自己的值，且不要将敏感信息提交到公开仓库。

## 从这里开始

- [完整教程：SSH 加固、域名、IPv6 与频道权限](outputs/Debian13-TeamSpeak-配置归档与运维手册.md)
- [一键初始化与 TeamSpeak 3 安装脚本：`debian13-ts3-install.sh`](#debian-13-一键初始化与-teamspeak-3-安装脚本)

## Debian 13 一键初始化与 TeamSpeak 3 安装脚本

[`debian13-ts3-install.sh`](debian13-ts3-install.sh) 面向刚安装完成的 Debian 13 amd64 VPS。它会更新系统、安装常用管理工具和基础安全组件、启用时间同步与自动安全更新，并安装 TeamSpeak 3 Server 3.13.8。

包含的软件：`ca-certificates`、`curl`、`wget`、`htop`、`nano`、`vim-tiny`、`git`、`jq`、`unzip`、`zip`、`lsof`、`dnsutils`、`rsync`、`tmux`、`fail2ban`、`nftables`、`unattended-upgrades`、`apt-listchanges`、`systemd-timesyncd`。

脚本会：

- 执行 `apt-get update`、`apt-get -y upgrade`、`apt-get autoremove --purge -y` 与 `apt-get clean`；
- 为当前 SSH 监听端口配置 Fail2Ban 的 `sshd` jail，并启动 Fail2Ban；
- 启用 `systemd-timesyncd`（NTP/SNTP 时间同步）和自动安全更新定时器；
- 默认仅安装 nftables，**不启用、不加载 `/etc/nftables.conf` 的规则**；Fail2Ban 在识别到暴力破解时会建立临时封禁规则。
- 创建 `teamspeak` 系统用户、`/opt/teamspeak` 安装目录和 `teamspeak.service`，启动并设置 TeamSpeak 开机自启。

脚本不会修改 SSH 认证、SSH 端口、云安全组、DNS 或现有防火墙规则。

### 使用方法

#### 直接用 curl 安装

在 Debian 13 服务器上直接执行以下命令。`--accept-ts3-license` 表示你已阅读并接受 TeamSpeak 许可证：

```bash
curl -fsSL https://raw.githubusercontent.com/YouFeng233/debian13-ssh-teamspeak3-guide/main/debian13-ts3-install.sh | sudo bash -s -- --accept-ts3-license --yes
```

执行前可直接预演完整安装流程；该命令不会改动系统：

```bash
curl -fsSL https://raw.githubusercontent.com/YouFeng233/debian13-ssh-teamspeak3-guide/main/debian13-ts3-install.sh | sudo bash -s -- --dry-run
```

`--skip-teamspeak` 不是默认选项，只在用户**只想安装 Debian 基础工具、明确不想安装 TeamSpeak** 时使用：

```bash
curl -fsSL https://raw.githubusercontent.com/YouFeng233/debian13-ssh-teamspeak3-guide/main/debian13-ts3-install.sh | sudo bash -s -- --skip-teamspeak --yes
```

#### 如果系统没有 curl

先按当前系统的包管理器安装 curl。以下命令仅用于安装 curl；本项目的一键脚本本身只支持 Debian 13。

```bash
# Debian / Ubuntu
sudo apt-get update && sudo apt-get install -y curl

# RHEL / Rocky Linux / AlmaLinux / Fedora
sudo dnf install -y curl

# CentOS 7 或旧版 RHEL
sudo yum install -y curl

# Alpine Linux
sudo apk add curl

# Arch Linux / Manjaro
sudo pacman -Sy --noconfirm curl

# openSUSE / SUSE Linux Enterprise
sudo zypper --non-interactive install curl
```

如果不确定使用哪个包管理器，可运行下面这段检测命令；它会安装 curl，但脚本在非 Debian 13 系统上仍会安全退出：

```bash
if ! command -v curl >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y curl
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y curl
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y curl
  elif command -v apk >/dev/null 2>&1; then
    sudo apk add curl
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm curl
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper --non-interactive install curl
  else
    echo "未识别包管理器，请手动安装 curl。" >&2
    exit 1
  fi
fi
```

常用可选参数：

```bash
# 设置时区并运行
sudo bash debian13-ts3-install.sh --timezone Asia/Shanghai --accept-ts3-license --yes

# 仅查看已安装组件的状态
sudo bash debian13-ts3-install.sh --status

# 仅在已经审阅 /etc/nftables.conf 后才启用 nftables
sudo bash debian13-ts3-install.sh --enable-nftables --accept-ts3-license --yes
```

执行日志写入 `/var/log/debian13-bootstrap.log`，且权限为仅 root 可读。

脚本默认安装 TeamSpeak；执行前需要明确传入 `--accept-ts3-license`。如果只需要 Debian 基础环境，可使用 `--skip-teamspeak`。脚本不会自动开放 UDP 9987、TCP 30033 或 TCP 10011，也不会自动修改云安全组、DNS、SSH 端口或认证方式。

## 安装完成后你会得到什么

运行脚本并完成后续配置后，你将拥有：

1. 在 Debian 13 VPS 安装 OpenSSH Server。
2. 配置 root 使用 Ed25519 SSH 公钥登录，禁止密码登录与 keyboard-interactive 登录。
3. 安全地更换 SSH 默认 22 端口，并验证 IPv4、IPv6 监听和防火墙规则。
4. 安装 TeamSpeak 3 Server，创建 `teamspeak` 系统用户与 `teamspeak.service` systemd 服务。
5. 开放 TeamSpeak 语音端口 UDP 9987、文件传输端口 TCP 30033，并限制 ServerQuery TCP 10011。
6. 在 Cloudflare、域名注册商或其他 DNS 服务商配置 A、AAAA、`_ts3._udp` SRV 记录。
7. 使用 Privilege Key 获取 TeamSpeak Server Admin，并配置频道 Guest、房间会员、房主的权限边界。

## 你可能正在找这些内容

本教程适合在搜索以下问题时参考：

- Debian 13 SSH 加固、SSH 修改端口、SSH 禁止密码登录、root SSH 公钥登录
- `Permission denied (publickey)`、`sshd -t`、`sshd -T`、Ed25519 私钥与公钥指纹核对
- Debian 安装 TeamSpeak 3 Server、TeamSpeak 3 systemd 服务、TeamSpeak 端口开放
- TeamSpeak 3 IPv6、TeamSpeak SRV 记录、TeamSpeak 域名连接、Cloudflare TeamSpeak DNS only
- TeamSpeak 3 Privilege Key、Server Admin、Channel Group、频道权限、租赁频道、隐藏频道成员

## 文章包含什么

| 部分 | 内容 |
|---|---|
| SSH 加固 | 公钥、权限、drop-in 配置、端口切换、验证和故障排查 |
| TeamSpeak 部署 | 安装、许可证、systemd、端口、日志、管理员凭据 |
| 域名与网络 | A / AAAA / SRV、IPv6、Cloudflare 与通用 DNS 后台 |
| 租赁频道权限 | 成员隐私、Channel Guest、房间会员、房主与验收测试 |

## 使用前请确认

- Debian 13
- OpenSSH：root 仅可使用公钥登录，密码认证关闭
- TeamSpeak 3 Server：语音、文件传输、systemd 服务与 IPv4/IPv6
- Cloudflare 或任意 DNS 服务商：A、AAAA、SRV 记录
- TeamSpeak 租赁频道：成员隐私、Guest、房间会员、房主权限模型

## 重要提醒

进行 SSH 变更时，请始终保留原 SSH 会话，并先在新终端验证新端口和公钥登录。服务器的私钥、ServerQuery 密码、Privilege Key、真实 IP 与域名均不得公开。

## 贡献与问题反馈

如果发现命令与新版 Debian、OpenSSH 或 TeamSpeak Server 不兼容，欢迎提交 Issue，说明系统版本、报错信息和已执行步骤。请先删除 IP、域名、私钥、密码、Token 和客户端 Identity 等敏感内容。
