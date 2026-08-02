# Debian 13 TeamSpeak 3 Server Installer

[中文 README（主要版本）](README.md)

This repository helps you set up a Debian 13 amd64 server and install TeamSpeak 3 Server. It includes system updates, common administration tools, Fail2Ban, time synchronization, unattended security updates, TeamSpeak systemd service setup, DNS guidance, SSH hardening instructions, and rental-channel permission guidance.

## Quick install

Run this on a fresh Debian 13 server while logged in as `root`. `--accept-ts3-license` confirms that you have read and accepted the TeamSpeak license.

```bash
curl -fsSL https://raw.githubusercontent.com/YouFeng233/debian13-ssh-teamspeak3-guide/main/debian13-ts3-install.sh | bash -s -- --accept-ts3-license --yes
```

If you are not logged in as `root`, add `sudo` before `bash`:

```bash
curl -fsSL https://raw.githubusercontent.com/YouFeng233/debian13-ssh-teamspeak3-guide/main/debian13-ts3-install.sh | sudo bash -s -- --accept-ts3-license --yes
```

Preview the full installation without changing the server:

```bash
curl -fsSL https://raw.githubusercontent.com/YouFeng233/debian13-ssh-teamspeak3-guide/main/debian13-ts3-install.sh | bash -s -- --dry-run
```

## What the script installs

- System updates and cleanup (`apt-get update`, upgrade, autoremove, clean)
- Common tools: curl, wget, htop, nano, vim, git, jq, dnsutils, rsync, tmux, and more
- Fail2Ban for the active SSH port
- `systemd-timesyncd` for time synchronization
- `unattended-upgrades` for automatic security updates
- TeamSpeak 3 Server 3.13.8 in `/opt/teamspeak`, managed by `teamspeak.service`

The script installs nftables but does not enable its service by default. It does not change SSH authentication or ports, open firewall ports, modify cloud security groups, or configure DNS.

## Useful options

```bash
# Debian baseline only; skip TeamSpeak
bash debian13-ts3-install.sh --skip-teamspeak --yes

# Set a timezone
bash debian13-ts3-install.sh --timezone Asia/Shanghai --accept-ts3-license --yes

# Show installation and service status
bash debian13-ts3-install.sh --status

# Enable nftables only after reviewing /etc/nftables.conf
bash debian13-ts3-install.sh --enable-nftables --accept-ts3-license --yes
```

The complete Chinese guide covers SSH hardening, A/AAAA/SRV DNS records, IPv6, server administration credentials, and TeamSpeak rental-channel permissions: [open the guide](outputs/Debian13-TeamSpeak-配置归档与运维手册.md).

## Important

Keep the TeamSpeak ServerQuery password, Privilege Key, SSH private keys, real IP addresses, and domain names private. The installation log is written to `/var/log/debian13-bootstrap.log`.
