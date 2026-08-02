#!/usr/bin/env bash
# Debian 13 server bootstrap and TeamSpeak 3 Server installer.
# Does not modify SSH authentication, open ports, or enable nftables.service.

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
    log INFO "DRY RUN: $(printf '%q ' "$@")"
    return 0
  fi

  log INFO "Running: $(printf '%q ' "$@")"
  "$@"
}

usage() {
  cat <<EOF
Usage: sudo bash ${SCRIPT_NAME} [options]

Bootstrap a newly installed Debian 13 server with common administration and
security packages. It does not change SSH authentication, open ports, or
network settings. It does not enable nftables.service by default.

Options:
  --yes                 Run without an interactive confirmation prompt.
  --dry-run             Print planned actions without changing the system.
  --status              Show the managed service and package status only.
  --timezone ZONE       Set an IANA timezone, for example Asia/Shanghai.
  --enable-nftables     Enable nftables.service after installation. Use only
                        after reviewing /etc/nftables.conf.
  --skip-teamspeak      Install the Debian server baseline only.
  --ts-version VERSION  TeamSpeak 3 Server version (default: 3.13.8).
  --accept-ts3-license  Confirm that you accept the TeamSpeak license and
                        install TeamSpeak 3 Server.
  -h, --help            Show this help text.
EOF
}

require_root() {
  (( EUID == 0 )) || die "Run this script as root, for example: sudo bash ${SCRIPT_NAME} --yes"
}

require_debian_13() {
  [[ -r /etc/os-release ]] || die "Cannot identify the operating system."
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "debian" && "${VERSION_ID:-}" == "13" ]] || \
    die "This script supports Debian 13 only; detected ${PRETTY_NAME:-unknown}."
  command -v systemctl >/dev/null 2>&1 || die "systemd is required."
}

confirm() {
  (( ASSUME_YES || DRY_RUN )) && return 0

  cat <<'EOF'
The script will:
  - update installed packages;
  - install common tools, Fail2Ban, nftables, unattended-upgrades and time sync;
  - enable Fail2Ban, systemd-timesyncd and unattended-upgrades timers;
  - run apt autoremove --purge and apt clean;
  - install TeamSpeak 3 Server unless --skip-teamspeak is used.

It will not change SSH settings, open ports, or enable nftables.service.
Fail2Ban may create temporary ban rules after failed login attempts.
EOF
  read -r -p "Continue? [y/N] " answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || die "Cancelled."
}

validate_requested_install() {
  if (( INSTALL_TEAMSPEAK && ! DRY_RUN )) && [[ ! -x "$TS_DIR/ts3server" ]] && (( ! ACCEPT_TS3_LICENSE )); then
    die "TeamSpeak 3 installation requires --accept-ts3-license. Read the license first, or use --skip-teamspeak."
  fi
}

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}

configure_timezone() {
  [[ -n "$TIMEZONE" ]] || return 0
  [[ -e "/usr/share/zoneinfo/$TIMEZONE" ]] || die "Unknown timezone: $TIMEZONE"
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
      log INFO "DRY RUN: would configure Fail2Ban sshd jail for port $ssh_port"
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
    log WARN "Could not determine a numeric SSH port; leaving the sshd jail at package defaults."
  fi

  run systemctl enable --now fail2ban.service
  run fail2ban-client ping
}

configure_unattended_upgrades() {
  run install -d -m 0755 /etc/apt/apt.conf.d
  if (( DRY_RUN )); then
    log INFO "DRY RUN: would write /etc/apt/apt.conf.d/20auto-upgrades"
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
    log INFO "Skipping TeamSpeak 3 Server installation."
    return 0
  }

  [[ "$(dpkg --print-architecture)" == "amd64" ]] || die "TeamSpeak 3 binary installer currently supports amd64 only."

  if (( DRY_RUN )); then
    log INFO "DRY RUN: would download TeamSpeak 3 Server ${TS_VERSION} to $TS_DIR and create teamspeak.service"
    return 0
  fi

  if [[ -x "$TS_DIR/ts3server" ]]; then
    log INFO "Existing TeamSpeak installation found at $TS_DIR; skipping download."
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
    [[ -d "$extracted_dir" ]] || die "Unexpected TeamSpeak archive layout."
    run install -d -m 0750 -o "$TS_USER" -g "$TS_USER" "$TS_DIR"
    run cp -a "$extracted_dir/." "$TS_DIR/"
    run touch "$TS_DIR/.ts3server_license_accepted"
    run chown -R "$TS_USER:$TS_USER" "$TS_DIR"
    run chmod 0750 "$TS_DIR/ts3server" "$TS_DIR/ts3server_startscript.sh" "$TS_DIR/ts3server_minimal_runscript.sh"
    log INFO "TeamSpeak 3 Server ${TS_VERSION} installed at $TS_DIR."
  fi

  if (( DRY_RUN )); then
    log INFO "DRY RUN: would write /etc/systemd/system/teamspeak.service"
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
  log INFO "TeamSpeak listens on UDP 9987 and TCP 30033. Open only the required ports in your cloud firewall after reviewing your network policy."
  log WARN "Initial ServerQuery credentials and Privilege Key are sensitive. View them locally in $TS_DIR/logs; do not copy them into shell history, chat, or GitHub."
}

show_status() {
  printf '\n== Operating system ==\n'
  cat /etc/os-release

  printf '\n== Managed packages ==\n'
  dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\t${Version}\n' "${BASE_PACKAGES[@]}" 2>/dev/null || true

  printf '\n== Services ==\n'
  systemctl --no-pager --full status fail2ban.service systemd-timesyncd.service 2>/dev/null || true

  printf '\n== Time synchronization ==\n'
  timedatectl status || true

  printf '\n== Automatic updates ==\n'
  systemctl --no-pager status apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

  printf '\n== Fail2Ban ==\n'
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
        (( $# )) || die "--timezone requires a value."
        TIMEZONE="$1"
        ;;
      --enable-nftables) ENABLE_NFTABLES=1 ;;
      --skip-teamspeak) INSTALL_TEAMSPEAK=0 ;;
      --accept-ts3-license) ACCEPT_TS3_LICENSE=1 ;;
      --ts-version)
        shift
        (( $# )) || die "--ts-version requires a value."
        TS_VERSION="$1"
        [[ "$TS_VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]] || die "Invalid TeamSpeak version: $TS_VERSION"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *) die "Unknown option: $1" ;;
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
    log WARN "Enabling nftables can load existing rules from /etc/nftables.conf. Review that file before using this option."
    run systemctl enable --now nftables.service
  else
    log INFO "nftables was installed but not enabled. Fail2Ban can still add its own temporary ban rules. Use --enable-nftables only after reviewing /etc/nftables.conf."
  fi

  run apt-get autoremove --purge -y
  run apt-get clean

  if (( ! DRY_RUN )); then
    show_status
    log INFO "Bootstrap complete. Log: $LOG_FILE"
  fi
}

main "$@"
