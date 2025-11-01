# Network Attached Storage (NAS)

## Overview

The HomeSec server provides NAS functionality using Samba (SMB/CIFS) and NFS for centralized file storage across the network.

**IP Address**: 192.168.20.10 (server.homesec.local)
**Storage**: RAID array (recommended RAID 5 or RAID 6)
**Services**: Samba (Windows/Mac/Linux), NFS (Linux)

## Features

- **Centralized storage**: Single storage location for all devices
- **RAID protection**: Data redundancy with RAID 5/6
- **User authentication**: Per-user access control
- **Share isolation**: Different shares for different VLANs
- **Backup integration**: Automated backups to RAID
- **Snapshots**: LVM snapshots for point-in-time recovery
- **Monitoring**: Storage metrics sent to ELK Stack

## Storage Layout

### RAID Configuration

```
/dev/sda, /dev/sdb, /dev/sdc, /dev/sdd  → RAID 5/6
    ↓
/dev/md0 (RAID array)
    ↓
LVM Physical Volume
    ↓
Volume Group: vg_storage
    ↓
Logical Volumes:
├── lv_shared     (500GB)  - Shared files
├── lv_backups    (1TB)    - System backups
├── lv_logs       (200GB)  - Log archive
├── lv_media      (500GB)  - Media files (optional)
└── lv_documents  (300GB)  - Documents
```

### Share Structure

| Share Name | Path | Access | Purpose |
|------------|------|--------|---------|
| `shared` | /mnt/storage/shared | VLAN 10, 20 | General shared files |
| `backups` | /mnt/storage/backups | VLAN 20 only | System backups |
| `logs` | /mnt/storage/logs | VLAN 20 only | Archived logs |
| `documents` | /mnt/storage/documents | VLAN 10, 20 | Documents |
| `media` | /mnt/storage/media | VLAN 10, 30 | Media files (optional) |

## Installation

### 1. Create RAID Array

```bash
# Install mdadm
sudo yum install -y mdadm

# Create RAID 5 array (minimum 3 disks)
sudo mdadm --create --verbose /dev/md0 --level=5 --raid-devices=4 \
    /dev/sda /dev/sdb /dev/sdc /dev/sdd

# Monitor creation progress
cat /proc/mdstat

# Save RAID configuration
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm.conf

# Update initramfs
sudo dracut -f
```

### 2. Create LVM Structure

```bash
# Install LVM
sudo yum install -y lvm2

# Create physical volume
sudo pvcreate /dev/md0

# Create volume group
sudo vgcreate vg_storage /dev/md0

# Create logical volumes
sudo lvcreate -L 500G -n lv_shared vg_storage
sudo lvcreate -L 1T -n lv_backups vg_storage
sudo lvcreate -L 200G -n lv_logs vg_storage
sudo lvcreate -L 500G -n lv_media vg_storage
sudo lvcreate -L 300G -n lv_documents vg_storage

# Format filesystems (XFS recommended for large files)
sudo mkfs.xfs /dev/vg_storage/lv_shared
sudo mkfs.xfs /dev/vg_storage/lv_backups
sudo mkfs.xfs /dev/vg_storage/lv_logs
sudo mkfs.xfs /dev/vg_storage/lv_media
sudo mkfs.xfs /dev/vg_storage/lv_documents

# Create mount points
sudo mkdir -p /mnt/storage/{shared,backups,logs,media,documents}

# Add to /etc/fstab
echo "/dev/vg_storage/lv_shared    /mnt/storage/shared      xfs  defaults  0 0" | sudo tee -a /etc/fstab
echo "/dev/vg_storage/lv_backups   /mnt/storage/backups     xfs  defaults  0 0" | sudo tee -a /etc/fstab
echo "/dev/vg_storage/lv_logs      /mnt/storage/logs        xfs  defaults  0 0" | sudo tee -a /etc/fstab
echo "/dev/vg_storage/lv_media     /mnt/storage/media       xfs  defaults  0 0" | sudo tee -a /etc/fstab
echo "/dev/vg_storage/lv_documents /mnt/storage/documents   xfs  defaults  0 0" | sudo tee -a /etc/fstab

# Mount all
sudo mount -a

# Verify
df -h
```

### 3. Install and Configure Samba

```bash
# Install Samba
sudo yum install -y samba samba-client samba-common

# Backup default config
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.backup

# Copy HomeSec Samba config
sudo cp smb.conf /etc/samba/smb.conf

# Test configuration
testparm

# Create Samba users (matching system users)
sudo useradd -M -s /sbin/nologin smbuser
sudo smbpasswd -a smbuser

# Set permissions
sudo chown -R root:users /mnt/storage/shared
sudo chmod -R 0775 /mnt/storage/shared

sudo chown -R root:root /mnt/storage/backups
sudo chmod -R 0700 /mnt/storage/backups

# Enable and start Samba
sudo systemctl enable smb nmb
sudo systemctl start smb nmb

# Check status
sudo systemctl status smb nmb
```

### 4. Install and Configure NFS

```bash
# Install NFS
sudo yum install -y nfs-utils

# Copy NFS exports config
sudo cp exports /etc/exports

# Enable and start NFS
sudo systemctl enable nfs-server rpcbind
sudo systemctl start nfs-server rpcbind

# Export shares
sudo exportfs -arv

# Verify exports
sudo exportfs -v
```

### 5. Configure Firewall

```bash
# Samba (SMB/CIFS)
sudo firewall-cmd --permanent --add-service=samba
sudo firewall-cmd --permanent --add-service=samba-client

# NFS
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --permanent --add-service=rpc-bind

# Reload firewall
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-services
```

## Samba Configuration

See `smb.conf` for full configuration. Key settings:

### Global Settings
```ini
[global]
    workgroup = HOMESEC
    server string = HomeSec NAS Server
    security = user
    map to guest = never
    log file = /var/log/samba/log.%m
    max log size = 1000
```

### Share Examples
```ini
[shared]
    path = /mnt/storage/shared
    valid users = @users
    read only = no
    browseable = yes
```

## NFS Configuration

See `exports` file for full configuration. Example:

```
/mnt/storage/shared    192.168.10.0/24(rw,sync,no_root_squash)
/mnt/storage/backups   192.168.20.20(rw,sync,no_root_squash)
```

## Client Access

### Windows Client (Samba)

```cmd
# Map network drive
net use Z: \\192.168.20.10\shared /user:smbuser password

# Or via File Explorer
\\192.168.20.10\shared
```

### macOS Client (Samba)

```bash
# Finder → Go → Connect to Server
smb://192.168.20.10/shared

# Or command line
mount -t smbfs //smbuser@192.168.20.10/shared /Volumes/shared
```

### Linux Client (Samba)

```bash
# Install client tools
sudo yum install -y cifs-utils

# Mount manually
sudo mkdir -p /mnt/nas-shared
sudo mount -t cifs //192.168.20.10/shared /mnt/nas-shared \
    -o username=smbuser,password=password

# Add to /etc/fstab for persistent mount
echo "//192.168.20.10/shared  /mnt/nas-shared  cifs  credentials=/root/.smbcredentials,uid=1000,gid=1000  0 0" | sudo tee -a /etc/fstab

# Create credentials file
echo "username=smbuser" | sudo tee /root/.smbcredentials
echo "password=yourpassword" | sudo tee -a /root/.smbcredentials
sudo chmod 600 /root/.smbcredentials
```

### Linux Client (NFS)

```bash
# Install NFS client
sudo yum install -y nfs-utils

# Mount manually
sudo mkdir -p /mnt/nas-shared
sudo mount -t nfs 192.168.20.10:/mnt/storage/shared /mnt/nas-shared

# Add to /etc/fstab
echo "192.168.20.10:/mnt/storage/shared  /mnt/nas-shared  nfs  defaults  0 0" | sudo tee -a /etc/fstab

# Test
df -h /mnt/nas-shared
```

## User Management

### Add Samba User

```bash
# Create system user
sudo useradd -M -s /sbin/nologin newuser

# Add to Samba
sudo smbpasswd -a newuser

# Enable user
sudo smbpasswd -e newuser

# Add to users group
sudo usermod -aG users newuser
```

### Remove Samba User

```bash
# Disable Samba user
sudo smbpasswd -x username

# Remove system user
sudo userdel username
```

## Monitoring

### Check RAID Status

```bash
# RAID health
cat /proc/mdstat

# Detailed info
sudo mdadm --detail /dev/md0

# Check for errors
sudo mdadm --examine /dev/sd[abcd]
```

### Check LVM Status

```bash
# Physical volumes
sudo pvs

# Volume groups
sudo vgs

# Logical volumes
sudo lvs

# Detailed display
sudo lvdisplay
```

### Check Disk Usage

```bash
# Overall usage
df -h

# Per-share usage
du -sh /mnt/storage/*

# Detailed breakdown
du -h --max-depth=1 /mnt/storage/shared | sort -hr
```

### Samba Status

```bash
# Service status
sudo systemctl status smb nmb

# Connected users
sudo smbstatus

# Open files
sudo smbstatus --locks

# Shares
sudo smbstatus --shares
```

### NFS Status

```bash
# Service status
sudo systemctl status nfs-server

# Active connections
sudo showmount -a

# Exports
sudo exportfs -v

# NFS stats
nfsstat
```

## Backup and Snapshots

### LVM Snapshots

```bash
# Create snapshot
sudo lvcreate -L 10G -s -n lv_shared_snap /dev/vg_storage/lv_shared

# Mount snapshot (read-only)
sudo mkdir /mnt/snapshot
sudo mount -o ro /dev/vg_storage/lv_shared_snap /mnt/snapshot

# Restore from snapshot (if needed)
sudo lvconvert --merge /dev/vg_storage/lv_shared_snap

# Remove snapshot
sudo umount /mnt/snapshot
sudo lvremove /dev/vg_storage/lv_shared_snap
```

### Automated Snapshot Script

```bash
# See ../backup/snapshot-lvm.sh
sudo /usr/local/bin/snapshot-lvm.sh lv_shared
```

## Performance Tuning

### Samba Optimization

Edit `/etc/samba/smb.conf`:

```ini
[global]
    # Performance
    socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
    read raw = yes
    write raw = yes
    max xmit = 65535
    dead time = 15
    getwd cache = yes
```

### NFS Optimization

Edit `/etc/nfs.conf`:

```ini
[nfsd]
threads=128
```

## Troubleshooting

### Samba Issues

```bash
# Test configuration
testparm

# Check logs
sudo tail -f /var/log/samba/log.smbd

# Test connectivity from client
smbclient -L //192.168.20.10 -U username

# Check firewall
sudo firewall-cmd --list-services | grep samba
```

### NFS Issues

```bash
# Check NFS is running
sudo systemctl status nfs-server

# Check exports
sudo exportfs -v

# Check firewall
sudo firewall-cmd --list-services | grep nfs

# Test mount from client
showmount -e 192.168.20.10
```

### RAID Issues

```bash
# Check RAID status
cat /proc/mdstat

# If degraded, check which disk failed
sudo mdadm --detail /dev/md0

# Replace failed disk
sudo mdadm --manage /dev/md0 --fail /dev/sdb
sudo mdadm --manage /dev/md0 --remove /dev/sdb
# Physically replace disk
sudo mdadm --manage /dev/md0 --add /dev/sdb

# Monitor rebuild
watch cat /proc/mdstat
```

### Disk Full

```bash
# Find large files
sudo du -h /mnt/storage | sort -rh | head -20

# Find old files
sudo find /mnt/storage -type f -mtime +365 -exec ls -lh {} \;

# Clean up logs
sudo find /mnt/storage/logs -type f -mtime +90 -delete

# Expand LV if space available
sudo lvextend -L +100G /dev/vg_storage/lv_shared
sudo xfs_growfs /mnt/storage/shared
```

## Security

### Restrict Access by VLAN

Samba - Use `hosts allow` in smb.conf:
```ini
[shared]
    hosts allow = 192.168.10. 192.168.20.
    hosts deny = 0.0.0.0/0
```

NFS - Use netmask in /etc/exports:
```
/mnt/storage/shared  192.168.10.0/24(rw,sync) 192.168.20.0/24(rw,sync)
```

### Enable Audit Logging

```bash
# Samba audit
# Add to smb.conf share section:
vfs objects = full_audit
full_audit:prefix = %u|%I|%m|%S
full_audit:success = open opendir write unlink rename
full_audit:failure = none

# NFS audit
# Add to /etc/nfs.conf:
[exportd]
debug = all
```

## Maintenance

### Daily

```bash
# Check RAID health
cat /proc/mdstat

# Check disk usage
df -h

# Check Samba status
sudo systemctl status smb nmb
```

### Weekly

```bash
# Check SMART status
sudo smartctl -a /dev/sda

# Scrub RAID array
sudo mdadm --action=check /dev/md0

# Backup configuration
sudo tar -czf /tmp/nas-config-$(date +%Y%m%d).tar.gz \
    /etc/samba/ /etc/exports /etc/fstab
```

### Monthly

```bash
# Update system
sudo yum update -y

# Check filesystem
sudo xfs_repair -n /dev/vg_storage/lv_shared

# Review logs
sudo journalctl -u smb --since "1 month ago" | less
```

## Backup Integration

NAS shares are backed up by the backup system (see `../backup/README.md`).

Key backup locations:
- `/mnt/storage/backups/config/` - System configuration backups
- `/mnt/storage/backups/elasticsearch/` - Elasticsearch snapshots
- `/mnt/storage/backups/vm/` - VM backups

## Related Documentation

- [Backup System](../backup/README.md)
- [Architecture](../../docs/architecture.md)
- [Installation Guide](../../docs/installation-guide.md)
- Samba docs: https://www.samba.org/samba/docs/
- NFS docs: https://nfs.sourceforge.net/
