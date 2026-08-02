#!/usr/bin/env bash
# Debian 13 基础环境与 TeamSpeak 3 Server 一键安装脚本。
# 默认不会修改 SSH 登录方式、开放端口或启用 nftables.service。

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="/var/log/debian13-bootstrap.log"
ASSUME_YES=0
DRY_RUN=0
STATUS_ONLY=0
TIMEZONE=""
ENABLE_NFTABLES=0
INSTALL_TEAMSPEAK=1
ACCEPT_TS3_LICENSE=0
TS_VERSION="3.13.8"
TS_DIR="/opt/teamspeak"
TS_USER="teamspeak"
TEMP_DIR=""

readonly -a BASE_PACKAGES=(
  ca-certificates
  curl
  wget
  bzip2
  htop
  nano
  vim-tiny
  git
  jq
  unzip
  zip
  lsof
  dnsutils
  rsync
  tmux
  fail2ban
  nftables
  unattended-upgrades
  apt-listchanges
  systemd-timesyncd
)

log() {
  local level="$1"
  shift
  printf '[%s] [%s] %s\n' "$(date -Is)" "$level" "$*" | tee -a "$LOG_FILE"
}

die() {
  log ERROR "$*"
  exit 1
}

run() {
  if (( DRY_RUN )); then
    log INFO "预演模式，不会执行：$(printf '%q ' "$@")"
    return 0
  fi

  log INFO "正在执行：$(printf '%q ' "$@")"
  "$@"
}

usage() {
  cat <<EOF
用法：sudo bash ${SCRIPT_NAME} [选项]

适用于刚安装好的 Debian 13 amd64 服务器。脚本会更新系统、安装常用工具、
安全组件和 TeamSpeak 3 Server。默认不会修改 SSH 登录方式、开放端口、网络
设置，也不会启用 nftables.service。

选项：
  --yes                 不显示确认问题，直接开始安装。
  --dry-run             只显示计划执行的操作，不修改系统。
  --status              只查看已安装组件和服务状态。
  --timezone ZONE       设置时区，例如 Asia/Shanghai。
  --enable-nftables     安装后启用 nftables.service；使用前请先检查
                        /etc/nftables.conf。
  --skip-teamspeak      只安装 Debian 基础环境，不安装 TeamSpeak。
  --ts-version VERSION  指定 TeamSpeak 3 Server 版本（默认：3.13.8）。
  --accept-ts3-license  确认你已接受 TeamSpeak 许可证，并安装 TeamSpeak。
  -h, --help            显示此帮助。
EOF
}

require_root() {
  (( EUID == 0 )) || die "请使用 root 权限运行，例如：sudo bash ${SCRIPT_NAME} --yes"
}

require_debian_13() {
  [[ -r /etc/os-release ]] || die "无法识别当前操作系统。"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "debian" && "${VERSION_ID:-}" == "13" ]] || \
    die "此脚本仅支持 Debian 13；当前系统是 ${PRETTY_NAME:-unknown}。"
  command -v systemctl >/dev/null 2>&1 || die "此脚本需要 systemd。"
}

confirm() {
  (( ASSUME_YES || DRY_RUN )) && return 0

  cat <<'EOF'
脚本将会：
  - 更新已安装的软件包；
  - 安装常用工具、Fail2Ban、nftables、自动更新和时间同步；
  - 启用 Fail2Ban、systemd-timesyncd 和自动更新定时器；
  - 运行 apt autoremove --purge 和 apt clean；
  - 除非使用 --skip-teamspeak，否则安装 TeamSpeak 3 Server。

脚本不会修改 SSH 设置、开放端口或启用 nftables.service。Fail2Ban 会在
有人多次登录失败后建立临时封禁规则。
EOF
  read -r -p "是否继续？[y/N] " answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || die "已取消。"
}

validate_requested_install() {
  if (( INSTALL_TEAMSPEAK && ! DRY_RUN )) && [[ ! -x "$TS_DIR/ts3server" ]] && (( ! ACCEPT_TS3_LICENSE )); then
    die "安装 TeamSpeak 3 需要 --accept-ts3-license；请先阅读许可证，或使用 --skip-teamspeak。"
  fi
}

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}

configure_timezone() {
  [[ -n "$TIMEZONE" ]] || return 0
  [[ -e "/usr/share/zoneinfo/$TIMEZONE" ]] || die "未知时区：$TIMEZONE"
  run timedatectl set-timezone "$TIMEZONE"
}

configure_time_sync() {
  run systemctl enable --now systemd-timesyncd.service
  run timedatectl set-ntp true
}

detect_ssh_port() {
  if command -v sshd >/dev/null 2>&1; then
    sshd -T 2>/dev/null | awk '/^port / { print $2; exit }'
  else
    printf 'ssh\n'
  fi
}

configure_fail2ban() {
  local ssh_port
  ssh_port="$(detect_ssh_port)"

  if [[ "$ssh_port" =~ ^[0-9]+$ ]]; then
    run install -d -m 0755 /etc/fail2ban/jail.d
    if (( DRY_RUN )); then
      log INFO "预演模式：将为 SSH 端口 $ssh_port 配置 Fail2Ban。"
    else
      cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
backend = systemd
port = ${ssh_port}
maxretry = 5
findtime = 10m
bantime = 1h
EOF
    fi
  else
    log WARN "无法识别 SSH 端口；将保留 Fail2Ban 的默认 sshd 设置。"
  fi

  run systemctl enable --now fail2ban.service
  run fail2ban-client ping
}

configure_unattended_upgrades() {
  run install -d -m 0755 /etc/apt/apt.conf.d
  if (( DRY_RUN )); then
    log INFO "预演模式：将写入 /etc/apt/apt.conf.d/20auto-upgrades。"
  else
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
  fi
  run systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
}

install_teamspeak() {
  local archive_name ts_url extracted_dir

  (( INSTALL_TEAMSPEAK )) || {
    log INFO "已跳过 TeamSpeak 3 Server 安装。"
    return 0
  }

  [[ "$(dpkg --print-architecture)" == "amd64" ]] || die "当前 TeamSpeak 3 二进制安装包仅支持 amd64 架构。"

  if (( DRY_RUN )); then
    log INFO "预演模式：将下载 TeamSpeak 3 Server ${TS_VERSION} 到 $TS_DIR，并创建 teamspeak.service。"
    return 0
  fi

  if [[ -x "$TS_DIR/ts3server" ]]; then
    log INFO "在 $TS_DIR 找到已有 TeamSpeak 安装，跳过下载。"
  else
    id "$TS_USER" >/dev/null 2>&1 || run useradd \
      --system \
      --home-dir "$TS_DIR" \
      --create-home \
      --shell /usr/sbin/nologin \
      "$TS_USER"

    TEMP_DIR="$(mktemp -d)"
    archive_name="teamspeak3-server_linux_amd64-${TS_VERSION}.tar.bz2"
    ts_url="https://files.teamspeak-services.com/releases/server/${TS_VERSION}/${archive_name}"
    extracted_dir="$TEMP_DIR/teamspeak3-server_linux_amd64"

    run curl --fail --location --proto '=https' --tlsv1.2 "$ts_url" --output "$TEMP_DIR/$archive_name"
    run tar -xjf "$TEMP_DIR/$archive_name" -C "$TEMP_DIR"
    [[ -d "$extracted_dir" ]] || die "下载的 TeamSpeak 压缩包目录结构不符合预期。"
    run install -d -m 0750 -o "$TS_USER" -g "$TS_USER" "$TS_DIR"
    run cp -a "$extracted_dir/." "$TS_DIR/"
    run touch "$TS_DIR/.ts3server_license_accepted"
    run chown -R "$TS_USER:$TS_USER" "$TS_DIR"
    run chmod 0750 "$TS_DIR/ts3server" "$TS_DIR/ts3server_startscript.sh" "$TS_DIR/ts3server_minimal_runscript.sh"
    log INFO "TeamSpeak 3 Server ${TS_VERSION} 已安装到 $TS_DIR。"
  fi

  if (( DRY_RUN )); then
    log INFO "预演模式：将写入 /etc/systemd/system/teamspeak.service。"
  else
    cat > /etc/systemd/system/teamspeak.service <<EOF
[Unit]
Description=TeamSpeak 3 Server
Wants=network-online.target
After=network-online.target

[Service]
Type=forking
User=${TS_USER}
Group=${TS_USER}
WorkingDirectory=${TS_DIR}
Environment=TS3SERVER_LICENSE=accept
ExecStart=${TS_DIR}/ts3server_startscript.sh start
ExecStop=${TS_DIR}/ts3server_startscript.sh stop
ExecReload=${TS_DIR}/ts3server_startscript.sh restart
PIDFile=${TS_DIR}/ts3server.pid
Restart=on-failure
RestartSec=5
LimitNOFILE=100000
UMask=0077

[Install]
WantedBy=multi-user.target
EOF
  fi

  run systemctl daemon-reload
  run systemctl enable --now teamspeak.service
  log INFO "TeamSpeak 使用 UDP 9987 和 TCP 30033。请按自己的网络策略，在云安全组或防火墙中只开放需要的端口。"
  log WARN "首次启动生成的 ServerQuery 密码和 Privilege Key 属于敏感信息。请仅在 $TS_DIR/logs 本地查看，切勿复制到命令历史、聊天记录或 GitHub。"
}

show_status() {
  printf '\n== 操作系统 ==\n'
  cat /etc/os-release

  printf '\n== 已管理的软件包 ==\n'
  dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\t${Version}\n' "${BASE_PACKAGES[@]}" 2>/dev/null || true

  printf '\n== 服务状态 ==\n'
  systemctl --no-pager --full status fail2ban.service systemd-timesyncd.service 2>/dev/null || true

  printf '\n== 时间同步 ==\n'
  timedatectl status || true

  printf '\n== 自动更新 ==\n'
  systemctl --no-pager status apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

  printf '\n== Fail2Ban 防护 ==\n'
  fail2ban-client ping 2>/dev/null || true

  printf '\n== nftables ==\n'
  systemctl is-enabled nftables.service 2>/dev/null || true

  printf '\n== TeamSpeak 3 ==\n'
  systemctl --no-pager --full status teamspeak.service 2>/dev/null || true
  ss -lunp | grep ':9987' || true
  ss -lntp | grep -E ':(30033|10011)' || true
}

parse_args() {
  while (( $# )); do
    case "$1" in
      --yes) ASSUME_YES=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --status) STATUS_ONLY=1 ;;
      --timezone)
        shift
        (( $# )) || die "--timezone 需要提供时区值。"
        TIMEZONE="$1"
        ;;
      --enable-nftables) ENABLE_NFTABLES=1 ;;
      --skip-teamspeak) INSTALL_TEAMSPEAK=0 ;;
      --accept-ts3-license) ACCEPT_TS3_LICENSE=1 ;;
      --ts-version)
        shift
        (( $# )) || die "--ts-version 需要提供版本号。"
        TS_VERSION="$1"
        [[ "$TS_VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]] || die "无效的 TeamSpeak 版本号：$TS_VERSION"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *) die "未知选项：$1" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  require_root
  require_debian_13

  if (( STATUS_ONLY )); then
    show_status
    return 0
  fi

  validate_requested_install
  touch "$LOG_FILE"
  chmod 0600 "$LOG_FILE"
  trap cleanup EXIT
  confirm

  export DEBIAN_FRONTEND=noninteractive
  run apt-get update
  run apt-get -y upgrade
  run apt-get install -y "${BASE_PACKAGES[@]}"

  configure_timezone
  configure_time_sync
  configure_fail2ban
  configure_unattended_upgrades
  install_teamspeak

  if (( ENABLE_NFTABLES )); then
    log WARN "启用 nftables 可能会加载 /etc/nftables.conf 中已有的规则；使用此选项前请先检查该文件。"
    run systemctl enable --now nftables.service
  else
    log INFO "nftables 已安装但未启用。Fail2Ban 仍可添加自己的临时封禁规则；只有检查过 /etc/nftables.conf 后才使用 --enable-nftables。"
  fi

  run apt-get autoremove --purge -y
  run apt-get clean

  if (( ! DRY_RUN )); then
    show_status
    log INFO "安装完成。运行日志：$LOG_FILE"
  fi
}

main "$@"
