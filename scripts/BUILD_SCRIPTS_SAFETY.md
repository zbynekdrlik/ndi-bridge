# NDI-Bridge USB Build Scripts - Safety Guide

## Issue: Excessive Output Can Crash Claude/Terminal

The build scripts can generate thousands of lines of output during:
1. **debootstrap** - Installing base Ubuntu system (can output 5000+ lines)
2. **apt-get install** - Installing packages in chroot (can output 3000+ lines)
3. **Various system commands** - Partitioning, formatting, etc.

## Safe Ways to Run Build Scripts

### 1. Use the Safe Test Version
```bash
# Test mode - no actual changes
sudo ./build-ndi-usb-linux-safe-test.sh /dev/sdb

# Actual build with limited output
sudo ./build-ndi-usb-linux-safe-test.sh /dev/sdb --build
```

### 2. Redirect Output to File
```bash
# Run build and save output to file
sudo ./build-ndi-usb-linux-final.sh /dev/sdb > build.log 2>&1 &
tail -f build.log  # Follow progress safely
```

### 3. Use Screen/Tmux
```bash
# Start screen session
screen -S ndi-build

# Run build
sudo ./build-ndi-usb-linux-final.sh /dev/sdb

# Detach with Ctrl+A, D
# Reattach with: screen -r ndi-build
```

### 4. Limit Output with External Tools
```bash
# Use pv to limit throughput
sudo ./build-ndi-usb-linux-final.sh /dev/sdb 2>&1 | pv -L 1k

# Use tail to show only recent lines
sudo ./build-ndi-usb-linux-final.sh /dev/sdb 2>&1 | tail -n 50
```

## Problematic Code Sections

### Original Problem (Fixed with head limiters):
```bash
# These now have "| head -20" or "| head -50" limiters
parted -s $USB_DEVICE mklabel gpt 2>&1 | head -20
mkfs.ext4 -L NDIBRIDGE ${USB_DEVICE}2 2>&1 | head -20
grub-install ... 2>&1 | head -50
```

### Still Potentially Problematic:
```bash
# debootstrap - converts each line to a dot
debootstrap ... 2>&1 | while IFS= read -r line; do
    echo -n "."
done

# chroot setup - filters but still processes all lines
chroot /mnt/usb /tmp/setup.sh 2>&1 | while IFS= read -r line; do
    # filtering logic
done
```

## Recommendations

1. **For Testing**: Always use the safe test version first
2. **For Production**: Run in screen/tmux with output to file
3. **For Development**: Test individual sections rather than full script
4. **For Claude**: Use the safe test version or show only specific sections

## Quick Test Commands

```bash
# Test prerequisites only
sudo bash -c 'source ./build-ndi-usb-linux-final.sh; check_prerequisites'

# Test partitioning only (BE CAREFUL - this will erase USB!)
sudo bash -c 'source ./build-ndi-usb-linux-final.sh; USB_DEVICE=/dev/sdb; partition_usb'
```