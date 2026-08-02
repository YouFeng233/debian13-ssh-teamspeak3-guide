---
title: "Debian 13 与 TeamSpeak 3：从零安装、加固与权限配置教程"
date: 2026-08-03
description: "面向新手的 Debian 13、SSH 加固、TeamSpeak 3 安装、域名 DNS 和租赁频道权限配置教程。"
---

# Debian 13 与 TeamSpeak 3：从零安装、加固与权限配置教程

这篇教程带你在 Debian 13 服务器上完成 SSH 安全加固、TeamSpeak 3 安装、域名解析和租赁频道权限配置。文中的 `<...>` 都是需要替换成自己信息的占位符；不要在公开文章、截图或 GitHub 仓库中填写真实密码、私钥、Token、IP 或域名。

## 1. 开始前先了解目标

| 项目 | 已记录的状态 |
|---|---|
| 操作系统 | Debian 13 |
| SSH 登录用户 | `root` |
| SSH 端口 | `<SSH_PORT>` |
| SSH 认证 | 仅 Ed25519 公钥；禁止密码及 keyboard-interactive |
| TeamSpeak 运行用户 | `teamspeak` |
| TeamSpeak 安装目录 | `/opt/teamspeak` |
| systemd 服务 | `teamspeak.service` |
| TeamSpeak Server 版本 | 3.13.8（安装前请在官方页面确认版本与架构） |
| 语音端口 | UDP `9987` |
| 文件传输端口 | TCP `30033` |
| ServerQuery | TCP `10011`；不应向全公网开放 |
| DNS | A、AAAA 与 `_ts3._udp` SRV；Cloudflare 必须为 DNS only（灰云） |

## 2. SSH 安全配置目标

最终有效配置应满足：

```text
Port <SSH_PORT>
PubkeyAuthentication yes
AuthenticationMethods publickey
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PermitRootLogin prohibit-password
```

公钥文件及权限：

```text
/root                         700
/root/.ssh                    700
/root/.ssh/authorized_keys    600
```

### 修改 SSH 时请按这个顺序操作

1. 保持当前 SSH 会话不断开，并确保有云控制台或救援模式。
2. 备份 `/etc/ssh`，写入或修改配置后执行 `sshd -t`。
3. 先在防火墙或云安全组放行 `<SSH_PORT>`，重启服务并检查监听。
4. 在**新的终端**用私钥验证登录成功。
5. 验证密码登录失败；最后才删除 TCP 22 的放行规则。

常用核查命令：

```bash
sshd -t
sshd -T | grep -Ei 'port|pubkeyauthentication|authenticationmethods|passwordauthentication|kbdinteractiveauthentication|permitrootlogin'
ss -lntp | grep sshd
namei -l /root/.ssh/authorized_keys
journalctl -u ssh.service -n 100 --no-pager
```

> `ssh -i` 必须指定客户端的私钥文件（通常没有 `.pub` 后缀）；`.pub` 是公钥，不能用于登录。

## 3. TeamSpeak 服务与域名连接

### 服务操作与检查

```bash
systemctl status teamspeak.service
systemctl restart teamspeak.service
journalctl -u teamspeak.service -n 100 --no-pager
ss -lunpt | grep -E '9987|30033|10011'
```

TeamSpeak 应监听 UDP `9987` 和 TCP `30033`。如果看到 `[::]:9987`、`[::]:30033`，表示程序也正在监听 IPv6；能否从公网连接还取决于云安全组、防火墙和 DNS 是否正确。

### DNS 记录模型

```text
A     <TEAMSPEAK_DOMAIN>              → <SERVER_IPV4>
AAAA  <TEAMSPEAK_DOMAIN>              → <SERVER_IPV6>
SRV   _ts3._udp.<TEAMSPEAK_DOMAIN>    → 0 0 9987 <TEAMSPEAK_DOMAIN>
```

Cloudflare 的上述记录必须设为 `DNS only`。代理模式不能代理 TeamSpeak 的 UDP 服务。

### 敏感管理凭据

- 首次启动日志会包含 `serveradmin`、ServerQuery 密码和 Server Admin Privilege Key。
- Privilege Key 通常按一次性令牌处理，用于把当前客户端 Identity 加入 Server Admin。
- 权限绑定到 TeamSpeak 客户端 **Identity**，不是昵称；应安全备份管理员 Identity。
- 不把密码、Token、私钥、真实域名或公网地址放入文档、截图和代码仓库。

## 4. 租赁频道权限：你会得到什么效果

目标效果：租户只能看到自己房间的成员；访客凭密码可进入；房主可管理 Guest 与房间会员，但无法改频道、无法管理房主；Server Admin 负责分配与撤销房主。

限制：TeamSpeak 3 可借由订阅权限隐藏其他频道的成员列表，但通常不能彻底隐藏频道名称或频道树节点。

### 每一个实际租赁语音频道

```text
i_channel_needed_subscribe_power = 75
i_channel_needed_join_power = 0 或未设置
频道密码 = 每个频道独立设置
```

可选：`i_channel_needed_description_view_power = 75`。这类设置需逐个实际语音频道配置；仅设置父频道不足够。

### 频道组权限表

| 频道组 | 订阅 / 免密码 | 管理能力 | 目标组保护门槛 |
|---|---|---|---|
| Channel Guest | 无特殊订阅或免密权限 | 不设置 Add / Remove / Modify Power | 三项 Needed Power 均为 `20` |
| 房间会员 | `i_channel_subscribe_power = 75`；`b_channel_join_ignore_password = 1` | 不设置 Add / Remove / Modify Power | 三项 Needed Power 均为 `20` |
| 房主 | 同房间会员 | Add / Remove / Modify Power 均为 `30` | 三项 Needed Power 均为 `75` |

数值关系：

```text
20 < 30 < 75
```

由此得到：

- 房主 `30 ≥ 20`：可以在 Channel Guest 与房间会员之间调整。
- 会员和 Guest 没有相应操作 Power：不能管理身份。
- 房主 `30 < 75`：不能授予或撤销房主。
- Server Admin `75 ≥ 75`：可以管理房主。

### 必须避免的误配置

- 不要把默认 `20` 随意改为 `25`；当前关系已足够。
- 不要笼统改动所有服务器组的 Needed Power；应检查操作者的最终有效权限来源。
- 不要把默认 `Channel Admin` 直接交给租户。
- 不要给房主频道修改、删除、结构调整、名称/描述、音质/容量等权限。
- 同名权限出现在多个频道组中，不代表它们共享数值；每个频道组各自保存 Value。

## 5. 配置完成后这样验收

### SSH

- [ ] `sshd -t` 通过，`sshd -T` 与第 2 节基线一致。
- [ ] 新端口在 IPv4 和 IPv6 上监听，并已由防火墙/安全组放行。
- [ ] 新终端可使用正确私钥登录；密码登录无法成功。
- [ ] 在确认新登录稳定之前，旧会话和端口 22 放行未被提前移除。

### TeamSpeak 服务

- [ ] `teamspeak.service` 处于 active 状态，服务重启后可自动恢复。
- [ ] UDP 9987、TCP 30033 可从预期网络访问。
- [ ] TCP 10011 只对受控管理来源开放，或完全不向公网开放。
- [ ] A、AAAA、SRV 记录正确且为 DNS only。
- [ ] 管理员 Identity、ServerQuery 密码和日志备份被安全保管。

### 租赁频道

- [ ] 每个实际租赁语音频道均有独立密码与 `i_channel_needed_subscribe_power = 75`。
- [ ] 房主/会员在自己的频道内能看到成员，在其他租赁频道看不到成员。
- [ ] 知道密码的 Guest 可进入，但进入前不能订阅查看成员。
- [ ] 房主可授予/撤销房间会员，会员不能管理身份。
- [ ] 房主不能创建、修改、移动或删除频道，也不能管理其他高权限频道组。
- [ ] 用至少两个测试 Identity 完成上述测试，避免管理员自身权限掩盖问题。

## 6. 后续维护建议

1. 先做一次只读核查，记录实际 SSH 最终配置、监听端口、防火墙/安全组规则和 TeamSpeak 服务状态。
2. 建立受保护的凭据备份：管理员 Identity、ServerQuery 密码、恢复方式；不要将其混入这份 Markdown。
3. 变更前先在测试频道验证权限；上线后用普通测试 Identity 验收。
4. 若未来要自动化部署，另起脚本项目，并实现 dry-run、配置备份、两阶段关闭 22、幂等性与回滚；不要直接把现有机器当作脚本测试目标。

---

# 从零开始：完整操作步骤

下面按顺序操作即可。所有尖括号占位符必须替换为自己的值；不要把私钥、密码、Privilege Key 或真实 IP 提交到公开仓库。除本地 SSH 测试命令外，其他命令均在服务器上以 `root` 执行。

## 步骤 1：安装 OpenSSH 并写入 root 公钥

先进入 root：

```bash
sudo -i
apt update
apt install -y openssh-server
```

创建公钥目录，随后将下面一行的占位符替换为**客户端公钥**（以 `ssh-ed25519` 开头，而不是私钥）：

```bash
install -d -m 700 -o root -g root /root/.ssh

cat > /root/.ssh/authorized_keys <<'EOF'
<ROOT_SSH_PUBLIC_KEY>
EOF

chown root:root /root
chown -R root:root /root/.ssh
chmod 700 /root
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

namei -l /root/.ssh/authorized_keys
ssh-keygen -lf /root/.ssh/authorized_keys
```

备份现有 SSH 配置：

```bash
SSH_BACKUP="/root/ssh-backup-$(date +%Y%m%d-%H%M%S)"
cp -a /etc/ssh "$SSH_BACKUP"
printf 'SSH backup: %s\n' "$SSH_BACKUP"
```

## 步骤 2：更改 SSH 端口并禁用密码登录

**不要关闭现有 SSH 会话。** 先检查是否已经有其他 `Port` 配置；避免多个端口定义导致 SSH 同时监听旧端口。

```bash
mkdir -p /etc/ssh/sshd_config.d
grep -RniE '^[[:space:]]*Port[[:space:]]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null || true
```

写入 drop-in 配置。把 `<SSH_PORT>` 改成高位、未被占用的 TCP 端口：

```bash
cat > /etc/ssh/sshd_config.d/00-00-root-key-only.conf <<'EOF'
Port <SSH_PORT>

PubkeyAuthentication yes
AuthenticationMethods publickey
AuthorizedKeysFile .ssh/authorized_keys

PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no

PermitRootLogin prohibit-password
EOF

chmod 644 /etc/ssh/sshd_config.d/00-00-root-key-only.conf
/usr/sbin/sshd -t
/usr/sbin/sshd -T -C user=root,host="$(hostname)",addr=127.0.0.1 | \
  grep -E '^(port|permitrootlogin|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|authenticationmethods|authorizedkeysfile|permitemptypasswords) '
```

在云厂商安全组先放行 `TCP <SSH_PORT>`，但保留 TCP 22。若使用 UFW，再执行：

```bash
ufw allow <SSH_PORT>/tcp
ufw status
systemctl enable ssh.service
systemctl restart ssh.service
systemctl --no-pager --full status ssh.service
ss -lntp | grep ':<SSH_PORT>'
```

在本地**新终端**测试。`-i` 后面是私钥文件，不是 `.pub` 公钥文件：

```bash
ssh -o IdentitiesOnly=yes -p <SSH_PORT> -i ~/.ssh/id_ed25519 root@<SERVER_IPV4>
ssh -o IdentitiesOnly=yes -p <SSH_PORT> -i ~/.ssh/id_ed25519 root@<SSH_DOMAIN>
```

确认新会话成功后，再验证密码认证已禁用：

```bash
ssh -p <SSH_PORT> \
  -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password,keyboard-interactive \
  root@<SERVER_IPV4>
```

预期会得到 `Permission denied (publickey).`。仅在上述两项验证成功后，才删除旧端口放行：

```bash
ufw delete allow 22/tcp
ufw status
```

若公钥登录失败，保持旧会话，执行：

```bash
cat /root/.ssh/authorized_keys
namei -l /root/.ssh/authorized_keys
ssh-keygen -lf /root/.ssh/authorized_keys
journalctl -u ssh.service --since '10 minutes ago' --no-pager | tail -n 100
```

本地核对私钥对应的公钥指纹：

```bash
ssh-keygen -y -f ~/.ssh/id_ed25519 | ssh-keygen -lf -
```

## 步骤 3：安装 TeamSpeak 3 Server

以下以历史版本 `3.13.8` 举例。下载前应在 TeamSpeak 官方发布页确认该版本仍可用及适用于自己的 CPU 架构；`amd64` 仅适用于 x86_64 服务器。

```bash
apt update
apt install -y curl bzip2 ca-certificates

id teamspeak >/dev/null 2>&1 || useradd \
  --system \
  --home-dir /opt/teamspeak \
  --create-home \
  --shell /usr/sbin/nologin \
  teamspeak

TS_VERSION="3.13.8"
TS_DIR="/opt/teamspeak"
TS_URL="https://files.teamspeak-services.com/releases/server/${TS_VERSION}/teamspeak3-server_linux_amd64-${TS_VERSION}.tar.bz2"

cd /tmp
curl -fL "$TS_URL" -o teamspeak3-server.tar.bz2
tar -xjf teamspeak3-server.tar.bz2
mkdir -p "$TS_DIR"
cp -a /tmp/teamspeak3-server_linux_amd64/. "$TS_DIR/"

less /opt/teamspeak/LICENSE
touch /opt/teamspeak/.ts3server_license_accepted
chown -R teamspeak:teamspeak /opt/teamspeak
chmod +x /opt/teamspeak/ts3server /opt/teamspeak/ts3server_startscript.sh /opt/teamspeak/ts3server_minimal_runscript.sh
```

`less` 中按 `q` 退出。接受许可证前请先阅读并确认适用条款。

创建 systemd 服务：

```bash
cat > /etc/systemd/system/teamspeak.service <<'EOF'
[Unit]
Description=TeamSpeak 3 Server
Wants=network-online.target
After=network-online.target

[Service]
Type=forking
User=teamspeak
Group=teamspeak
WorkingDirectory=/opt/teamspeak
Environment=TS3SERVER_LICENSE=accept
ExecStart=/opt/teamspeak/ts3server_startscript.sh start
ExecStop=/opt/teamspeak/ts3server_startscript.sh stop
ExecReload=/opt/teamspeak/ts3server_startscript.sh restart
PIDFile=/opt/teamspeak/ts3server.pid
Restart=on-failure
RestartSec=5
LimitNOFILE=100000
UMask=0077

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now teamspeak.service
systemctl --no-pager --full status teamspeak.service
```

## 步骤 4：防火墙、日志与管理员凭据

在云安全组开放 UDP 9987 与 TCP 30033。若使用 UFW：

```bash
ufw allow 9987/udp
ufw allow 30033/tcp
ufw status

ss -lunp | grep ':9987'
ss -lntp | grep ':30033'
journalctl -u teamspeak.service -n 100 --no-pager
ls -lt /opt/teamspeak/logs/
```

不要向全部公网开放 TCP 10011（ServerQuery）。首次启动生成的敏感内容只在服务器本地查看：

```bash
grep -R -E 'loginname=|password=|token=' /opt/teamspeak/logs/ | tail -n 30
```

其中 `token=` 对应 Server Admin Privilege Key。TeamSpeak 客户端连接服务器后，进入 `Permissions → Use Privilege Key`（有的版本显示 `Use Token`），粘贴 Key，使当前 **Identity** 获得 Server Admin。密码、Key 与 Identity 备份均不得公开。

## 步骤 5：配置域名 DNS

无论域名是在哪里买的，关键都不是“注册商”本身，而是当前为该域名提供解析的 DNS 管理后台。进入该后台，添加以下三条记录：

```text
A     <TEAMSPEAK_DOMAIN>           <SERVER_IPV4>
AAAA  <TEAMSPEAK_DOMAIN>           <SERVER_IPV6>
SRV   _ts3._udp.<TEAMSPEAK_DOMAIN> 0 0 9987 <TEAMSPEAK_DOMAIN>
```

如果使用 Cloudflare，三条记录都必须设为 **DNS only / 灰色云朵**；Cloudflare 的代理不能转发 TeamSpeak 的 UDP 语音流量。

如果使用其他域名注册商或 DNS 服务商（例如在购买域名的网站直接管理 DNS），在其 DNS 管理页面添加同样的 A、AAAA、SRV 记录即可。字段名称可能略有不同：

```text
主机记录 / Name：<TEAMSPEAK_DOMAIN> 对应的主机部分
记录值 / Value：A 填 <SERVER_IPV4>；AAAA 填 <SERVER_IPV6>
SRV 服务 / Service：_ts3
SRV 协议 / Protocol：_udp
SRV 优先级 / Priority：0
SRV 权重 / Weight：0
SRV 端口 / Port：9987
SRV 目标 / Target：<TEAMSPEAK_DOMAIN>
```

不要把 IPv6 前缀长度（如 `/48`）或方括号填进 AAAA 记录。若 DNS 后台要求 SRV 的主机名完整填写，则使用 `_ts3._udp.<TEAMSPEAK_DOMAIN>`；若它把主机、服务和协议拆成独立字段，则按页面分别填写。保存后等待解析生效。

检查解析：

```bash
dig @1.1.1.1 +short A <TEAMSPEAK_DOMAIN>
dig @1.1.1.1 +short AAAA <TEAMSPEAK_DOMAIN>
dig @1.1.1.1 +short SRV _ts3._udp.<TEAMSPEAK_DOMAIN>
```

服务器侧检查 IPv6 和双栈监听：

```bash
ip -6 addr show scope global
ip -6 route show default
ping -6 -c 3 2606:4700:4700::1111
ss -lunp | grep ':9987'
ss -lntp | grep ':30033'
```

看到 `[::]:9987` 与 `[::]:30033` 表示程序已监听 IPv6。

## 步骤 6：在 TeamSpeak 客户端创建租赁频道权限

先在客户端启用 `Tools → Options → Application → Advanced permissions system`。建立自定义频道组“房间会员”和“房主”；不要把默认 `Channel Admin` 交给租户。

对**每个实际租赁语音频道**，右键频道进入权限设置，搜索并设置：

```text
i_channel_needed_subscribe_power = 75
i_channel_needed_join_power = 0 或未设置
频道密码 = 独立且随机的密码
可选：i_channel_needed_description_view_power = 75
```

不要只在父频道设置，这些值必须写入每个实际语音频道。

分别在三个频道组的权限设置中填写以下值：

```text
Channel Guest
  i_group_needed_member_add_power = 20
  i_group_needed_member_remove_power = 20
  i_client_needed_permission_modify_power = 20
  i_group_member_add_power / remove_power / i_client_permission_modify_power = 未设置

房间会员
  i_channel_subscribe_power = 75
  b_channel_join_ignore_password = 1
  i_group_needed_member_add_power = 20
  i_group_needed_member_remove_power = 20
  i_client_needed_permission_modify_power = 20
  i_group_member_add_power / remove_power / i_client_permission_modify_power = 未设置

房主
  i_channel_subscribe_power = 75
  b_channel_join_ignore_password = 1
  i_group_member_add_power = 30
  i_group_member_remove_power = 30
  i_client_permission_modify_power = 30
  i_group_needed_member_add_power = 75
  i_group_needed_member_remove_power = 75
  i_client_needed_permission_modify_power = 75
```

最后用不带管理员权限的多个测试 Identity 验证：Guest 可凭密码进房；房主可把 Guest 加为会员并撤销会员；会员不能管理任何身份；房主不能编辑、移动、删除频道，也不能授予或撤销房主。管理员帐号不能用于这一验收，因为其高权限会掩盖实际问题。

### 步骤 6.1：在客户端创建和分配频道组

以下操作在已启用高级权限系统的 TeamSpeak 客户端中完成：

1. 打开 `Permissions → Channel Groups`，新建“房间会员”和“房主”两个频道组。
2. 打开每个组的权限窗口，按上节的技术名称搜索并填写数值；任何要求“未设置”的权限都不要勾选或填写数值。
3. 在目标租赁频道内右键用户，进入 `Set Channel Group`，由 Server Admin 分配“房主”。
4. 房主在自己频道内对 Guest 使用同一菜单，把对方设为“房间会员”；撤销时改回 `Channel Guest`。
5. 不给房主 `Channel Admin`，也不授予频道创建、编辑、删除、移动、名称/描述、音质/容量或权限编辑能力。

若房主仍能管理不该管理的组，检查其服务器组、频道组和 Client Permissions 的最终有效权限，尤其是目标用户的 `i_client_needed_permission_modify_power`。不同频道组显示同名权限并不表示它们共用同一个 Value。

## 步骤 7：macOS 本地 DNS 排错（可选）

如果 `dig @1.1.1.1` 能查到记录、但 TeamSpeak 客户端或默认 `dig` 查询不到，先查看本机 DNS：

```bash
scutil --dns | grep -E 'resolver|nameserver'
networksetup -getdnsservers "Wi-Fi"
dig +short A <TEAMSPEAK_DOMAIN>
dig +short AAAA <TEAMSPEAK_DOMAIN>
```

需要临时把 macOS 的 Wi-Fi DNS 改为 Cloudflare 时：

```bash
sudo networksetup -setdnsservers "Wi-Fi" 1.1.1.1 1.0.0.1
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

将 `Wi-Fi` 替换为系统中实际的网络服务名称；这一步只影响本机解析，不会改动服务器或域名的 DNS 记录。
