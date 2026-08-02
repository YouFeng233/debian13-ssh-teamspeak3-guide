# Debian 13 SSH 加固与 TeamSpeak 3 部署指南

一份面向中文读者的实操教程，覆盖 Debian 13 的 SSH 公钥加固、TeamSpeak 3 Server 安装与 systemd 服务、IPv4/IPv6、DNS/SRV、租赁频道权限隔离及验收。

所有公网地址、域名、端口、密钥、密码和 Token 都以占位符表示；请替换为自己的值，且不要将敏感信息提交到公开仓库。

## 教程

- [Debian 13 与 TeamSpeak 3：配置归档与运维手册](outputs/Debian13-TeamSpeak-配置归档与运维手册.md)

## 适用范围

- Debian 13
- OpenSSH：root 仅可使用公钥登录，密码认证关闭
- TeamSpeak 3 Server：语音、文件传输、systemd 服务与 IPv4/IPv6
- Cloudflare 或任意 DNS 服务商：A、AAAA、SRV 记录
- TeamSpeak 租赁频道：成员隐私、Guest、房间会员、房主权限模型

## 安全提醒

进行 SSH 变更时，请始终保留原 SSH 会话，并先在新终端验证新端口和公钥登录。服务器的私钥、ServerQuery 密码、Privilege Key、真实 IP 与域名均不得公开。
