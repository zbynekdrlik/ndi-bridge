# Feature Comparison: Monolithic vs Modular Build Scripts

## Analysis Date: 2025-07-20

This document compares the original monolithic build script (`build-ndi-usb-linux-final.sh`) with the modular version (`build-ndi-usb-modular.sh`) to identify missing features.

## Key Missing Features in Modular Version

### 1. Power Outage Resistance Features

**Monolithic Version:**
- Root filesystem mounted as **read-only** by default (`ro,noatime,errors=remount-ro`)
- Journal data mode enabled: `tune2fs -o journal_data` for better data integrity
- Explicit read-only/read-write helper scripts (`ndi-bridge-ro`, `ndi-bridge-rw`)

**Modular Version:**
- Root filesystem remains **read-write** by default
- No journal data mode configuration
- Missing the critical power-failure protection

### 2. Boot Configuration Differences

**Monolithic Version:**
- Partition layout: EFI (512MB) + Root (rest)
- Labels partitions: EFI labeled "EFI", Root labeled "NDIBRIDGE"
- Cleaner partition scheme for embedded use

**Modular Version:**
- Partition layout: BIOS boot (1MB) + EFI (512MB) + Root (rest)
- No partition labels
- Added legacy BIOS support but more complex

### 3. Missing System Configuration

**Monolithic Version:**
- Disables power button actions via systemd logind.conf
- Reduces swappiness: `vm.swappiness=10`
- Configures faster boot timeouts
- Custom GRUB colors and theme

**Modular Version:**
- Power button still triggers shutdown
- Default swappiness
- Some boot optimizations missing

### 4. Missing Helper Scripts

**Modular Version is missing inline definitions for:**
- `ndi-bridge-show-logs` (referenced but not created inline)
- Proper TTY1 log display service configuration

### 5. Network Tools Installation

**Monolithic Version:**
- Explicitly installs: `nload`, `iftop`, `bmon`
- Gracefully handles missing packages

**Modular Version:**
- Attempts to install but fails (packages not in minimal repos)
- No fallback handling

### 6. Filesystem Safety

**Monolithic Version:**
- Root filesystem is read-only protected
- Only specific directories use tmpfs
- Manual remount required for changes

**Modular Version:**
- Root filesystem is read-write (vulnerable to corruption)
- Less comprehensive tmpfs configuration

## Critical Fixes Needed

### 1. Restore Read-Only Root Filesystem
Add to `11-filesystem.sh`:
```bash
# Configure read-only root
cat >> /etc/fstab << EOFFSTAB
UUID=$(blkid -s UUID -o value ${USB_DEVICE}3) / ext4 ro,noatime,errors=remount-ro 0 1
EOFFSTAB

# Enable journal data mode for power failure resistance
tune2fs -o journal_data ${USB_DEVICE}3
```

### 2. Restore Power Button Configuration
Add to system configuration:
```bash
# Disable power button shutdown
mkdir -p /etc/systemd/logind.conf.d/
cat > /etc/systemd/logind.conf.d/00-disable-power-key.conf << 'EOF'
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
EOF
```

### 3. Add Missing Helper Scripts
The `ndi-bridge-show-logs` script needs to be created inline in the TTY configuration module.

### 4. Restore Boot Optimizations
Add swappiness and timeout configurations:
```bash
echo "vm.swappiness=10" >> /etc/sysctl.conf

mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/10-timeout.conf << EOF
[Manager]
DefaultTimeoutStartSec=10s
DefaultTimeoutStopSec=10s
EOF
```

## Version Information
- Monolithic Script: v1.1.3
- Modular Script: v1.3.0 (higher version but missing features)

## Recommendation
The modular version needs to incorporate the power-failure resistance and read-only filesystem features from the monolithic version to maintain the same level of reliability for embedded/appliance use.