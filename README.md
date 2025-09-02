# TeamSpeak 3 Server on Fedora Bootc

A bootable container deployment of TeamSpeak 3 Server using [Fedora bootc](https://docs.fedoraproject.org/en-US/bootc/) technology with automated Anaconda kickstart installation.

The overarching goal to this project is to deliver an ISO which can be utilized to rapidly deploy a Teamspeak server as a deployable self-configuring ISO and for myself to learn the basics of bootable containers.

**Note**: This project is currently under development, feel free to contribute or take inspiration.

## 🚀 Quick Start

```bash
# Generate keys and set passwords
./teamspeak-bootc.sh genkey

# Build the container image
./teamspeak-bootc.sh build

# Create bootable ISO with automated installation
./teamspeak-bootc.sh deploy

# Deploy to Proxmox (upload output/install.iso)
# Boot VM - installation proceeds automatically
# Access via SSH: ssh fedora@<vm-ip> (password: password)
```

### Build Process

1. **Generate Keys & Passwords**: Creates SSH keys and sets initial passwords

    ```bash
    ./teamspeak-bootc.sh genkey
    ```

2. **Build Container Image**: Packages TeamSpeak server and dependencies into a bootc container

    ```bash
    ./teamspeak-bootc.sh build
    ```

    - Builds from `Containerfile`
    - Installs TeamSpeak 3.13.7
    - Configures systemd services from `config/teamspeak.service`
    - Creates required directories
    - Copies `config` to `/etc/teamspeak`, important for `ts3server.ini`

### Deployment Process

1. **Create Bootable ISO**: Generates installation media with kickstart automation

    ```bash
    ./teamspeak-bootc.sh deploy
    ```

    - Creates `output/install.iso` using Anaconda installer
    - Embeds bootc container image
    - Configures unattended installation

2. **Deploy on Hardware/VM**: Boot target system from the ISO

    - Installation proceeds automatically
    - System configures itself with TeamSpeak server
    - TeamSpeak service starts automatically on first boot
    - Admin token available in `/var/lib/teamspeak/logs/` (see ts3server_*.log)

## 📋 Features

- **Automated Installation**: [Anaconda kickstart](https://osbuild.org/docs/bootc/#anaconda-iso-installer-options-installer-mapping) for unattended deployment
- **Immutable Infrastructure**: [Bootc](https://github.com/containers/bootc) container with systemd as PID 1
- **Persistent Data**: TeamSpeak data in `/var/lib/teamspeak` (survives updates)
- **User Injection**: SSH keys and credentials via [bootc build config](https://osbuild.org/docs/bootc/#-build-config)
- **Security**: Hardened systemd service with proper isolation
- **Update Support**: In-place updates via `bootc switch`

## 🏗️ Architecture

This is the target directory structure for the Bootc container image:

```shell
┌─────────────────────────────────────────────────────────────────┐
│                    Bootc Container Image                        │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ /opt/teamspeak3-server/ (READ-ONLY)                         │ │
│ │ ├── ts3server (binary)                                      │ │
│ │ ├── sql/create_sqlite/ (database schemas)                   │ │
│ │ └── logs/, files/, database/ (read-only, static content)    │ │
│ └─────────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ /var/lib/teamspeak/ (PERSISTENT, writable)                  │ │
│ │ ├── logs/ (actual log storage, writable)                    │ │
│ │ ├── files/ (file transfers, writable)                       │ │
│ │ └── database/ts3server.sqlitedb (SQLite database, writable) │ │
│ └─────────────────────────────────────────────────────────-───┘ │
└─────────────────────────────────────────────────────────────────┘
```

## 🛠️ Management Commands

All commands use the unified management script:

```bash
# Build container image
./teamspeak-bootc.sh build

# Create bootable ISO with kickstart
./teamspeak-bootc.sh deploy

# Clean up old images
./teamspeak-bootc.sh clean
```

## 📝 Configuration Files

### `config/config.toml`

[Bootc build config](https://osbuild.org/docs/bootc/#-build-config) with:

- User creation via kickstart
- SSH key injection
- Automated installation settings
- Filesystem customizations

### `Containerfile`

Clean bootc container with:

- TeamSpeak 3.13.7 installation
- systemd-sysusers for service account
- tmpfiles.d for directory ownership
- `/sbin/init` as PID 1 (proper bootc pattern)

### `config/teamspeak.service`

Systemd service with direct writable directories for persistent data and security hardening.

## 🔧 Deployment Steps

1. **Generate Keys/Set Password**: `./teamspeak-bootc.sh genkey`
1. **Build**: `./teamspeak-bootc.sh build`
1. **Create ISO**: `./teamspeak-bootc.sh deploy`
1. **Upload**: Transfer `output/install.iso` to Proxmox ISO storage
1. **Create VM**: 4GB+ RAM, 20GB+ disk, attach ISO as CD/DVD
1. **Boot**: Installation proceeds automatically (no interaction needed)
1. **Access**: SSH `fedora@<vm-ip>` (password: `password`)
1. **Verify**: `sudo systemctl status teamspeak`

TeamSpeak admin token appears in `/var/lib/teamspeak/logs/ts3server_*.log` on first start.

```bash
VM_ID=103
qm create $VM_ID --name teamspeak --machine q35 --bios ovmf --scsi0 local-lvm:103,iothreaad=on --efidisk0 local-lvm:1,efitype=4m,pre-enrolled-keys=1 --memory 4096 --cores 4 --net0 virtio,bridge=vmbr0 --cdrom local:iso/$ISO_FILE
```

## 🔌 Proxmox VM Creation

For Proxmox deployment, you can use this command to create a suitable VM:

```bash
VM_ID=103
# Create TeamSpeak VM with UEFI, 4GB RAM, and 4 cores
qm create $VM_ID \
    --name "teamspeak" \
    --machine q35 \
    --bios ovmf \
    --efidisk0 local-lvm:1,efitype=4m,pre-enrolled-keys=1 \
    --scsihw virtio-scsi-single \
    --scsi0 local-lvm:20,iothread=on \
    --memory 4096 \
    --cores 4 \
    --net0 virtio,bridge=vmbr0 \
    --bootdisk scsi0 \
    --serial0 socket \
    --vga std \
    --cdrom local:iso/install.iso
```

This creates a VM with UEFI boot, virtio-scsi disk, and network connectivity. After creation, start the VM and the automated installation will begin.
```


## 🧹 File Structure

```text
teamspeak/
├── Containerfile                   # Bootc container definition
├── teamspeak-bootc.sh              # Management script
├── config/
│   ├── config.toml                 # Build config with kickstart
│   ├── teamspeak.service           # Systemd service
│   └── ts3server.ini               # TeamSpeak configuration
└── keys/
    ├── README.md
    ├── teamspeak-bootc-key
    └── teamspeak-bootc-key.pub
```
