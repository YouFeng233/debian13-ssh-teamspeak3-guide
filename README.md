# Debian 13 SSH 加固与 TeamSpeak 3 Server 部署教程

一份面向中文读者的 Debian 13 服务器搭建实操教程。内容覆盖 OpenSSH 安全加固、root 仅允许 SSH 密钥登录、修改 SSH 端口、关闭密码登录，以及 TeamSpeak 3 Server 安装、systemd 自启动、IPv4/IPv6 双栈、域名 DNS 与 SRV 记录、租赁频道权限隔离。

所有公网地址、域名、端口、密钥、密码和 Token 都以占位符表示；请替换为自己的值，且不要将敏感信息提交到公开仓库。

## 教程

- [Debian 13 与 TeamSpeak 3：配置归档与运维手册](outputs/Debian13-TeamSpeak-配置归档与运维手册.md)

## 你将完成什么

跟随教程可以完成以下配置：

1. 在 Debian 13 VPS 安装 OpenSSH Server。
2. 配置 root 使用 Ed25519 SSH 公钥登录，禁止密码登录与 keyboard-interactive 登录。
3. 安全地更换 SSH 默认 22 端口，并验证 IPv4、IPv6 监听和防火墙规则。
4. 安装 TeamSpeak 3 Server，创建 `teamspeak` 系统用户与 `teamspeak.service` systemd 服务。
5. 开放 TeamSpeak 语音端口 UDP 9987、文件传输端口 TCP 30033，并限制 ServerQuery TCP 10011。
6. 在 Cloudflare、域名注册商或其他 DNS 服务商配置 A、AAAA、`_ts3._udp` SRV 记录。
7. 使用 Privilege Key 获取 TeamSpeak Server Admin，并配置频道 Guest、房间会员、房主的权限边界。

## 常见搜索问题

本教程适合在搜索以下问题时参考：

- Debian 13 SSH 加固、SSH 修改端口、SSH 禁止密码登录、root SSH 公钥登录
- `Permission denied (publickey)`、`sshd -t`、`sshd -T`、Ed25519 私钥与公钥指纹核对
- Debian 安装 TeamSpeak 3 Server、TeamSpeak 3 systemd 服务、TeamSpeak 端口开放
- TeamSpeak 3 IPv6、TeamSpeak SRV 记录、TeamSpeak 域名连接、Cloudflare TeamSpeak DNS only
- TeamSpeak 3 Privilege Key、Server Admin、Channel Group、频道权限、租赁频道、隐藏频道成员

## 文档结构

| 部分 | 内容 |
|---|---|
| SSH 加固 | 公钥、权限、drop-in 配置、端口切换、验证和故障排查 |
| TeamSpeak 部署 | 安装、许可证、systemd、端口、日志、管理员凭据 |
| 域名与网络 | A / AAAA / SRV、IPv6、Cloudflare 与通用 DNS 后台 |
| 租赁频道权限 | 成员隐私、Channel Guest、房间会员、房主与验收测试 |

## 适用范围

- Debian 13
- OpenSSH：root 仅可使用公钥登录，密码认证关闭
- TeamSpeak 3 Server：语音、文件传输、systemd 服务与 IPv4/IPv6
- Cloudflare 或任意 DNS 服务商：A、AAAA、SRV 记录
- TeamSpeak 租赁频道：成员隐私、Guest、房间会员、房主权限模型

## 安全提醒

进行 SSH 变更时，请始终保留原 SSH 会话，并先在新终端验证新端口和公钥登录。服务器的私钥、ServerQuery 密码、Privilege Key、真实 IP 与域名均不得公开。

## 贡献与问题反馈

如果发现命令与新版 Debian、OpenSSH 或 TeamSpeak Server 不兼容，欢迎提交 Issue，说明系统版本、报错信息和已执行步骤。请先删除 IP、域名、私钥、密码、Token 和客户端 Identity 等敏感内容。
