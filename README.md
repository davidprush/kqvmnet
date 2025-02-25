# kqvmnet
Script to configure KVM/QEMU VM networking with a bridge on Ubuntu 24.04
# VM Network Setup Script Changes

## Key Changes

### New Backup Function: `backup_file`
- Takes a file path as an argument.
- Checks if the file exists, then creates a `.bak` copy in the same directory (e.g., `/tmp/file.xml.bak`).
- Adds the file to the `BACKED_UP_FILES` array to track it.
- Called in `edit_vm_network` before modifying the VM XML.

### New Restore Function: `restore_backups`
- Iterates over `BACKED_UP_FILES`.
- Copies each `.bak` file back to its original location.
- For VM XML files (detected by `.xml` extension), reapplies them with `virsh define`.
- Exits after restoration.

### Option Parsing Updated
- Added `-r` and `--restore` to trigger `restore_backups`.
- If `-r` is present, the script runs the restore operation and exits immediately.

### Integration in `edit_vm_network`
- Before modifying the XML (sed operations), the script calls `backup_file "$TEMP_FILE"`.
- The temporary XML file is backed up (e.g., `/tmp/tmp.xyz.bak`) before changes are applied.

### Help Menu Updated
- Added `-r`, `--restore` option with description.
- Updated examples to include `-r`.
- Added note about backups.

### Verbose Output
- Lists backed-up files at the end and provides the restore command.

## How to Use

### Save and Make Executable
```bash
nano setup-vm-network.sh
chmod +x setup-vm-network.sh
```
## Sample Output
### Normal Run
```
[INFO] Script is running with sudo privileges.
[INFO] Configuration parameters:
  Physical Interface: enx0011226830b1
  Bridge Name: br0
  Main VM Name: timemachine
  Guest Interface ID: eth0
  VMs to Edit Network: 
[PROMPT] Proceed with these settings? (y/N): y
...
[INFO] Editing network interface for VM: timemachine
[INFO] Backing up /tmp/tmp.abc123 to /tmp/tmp.abc123.bak
[INFO] Existing bridge interface found in timemachine, updating it...
...
[INFO] Setup complete! Please verify DNS resolution and connectivity inside all configured VMs.
[INFO] Backed-up files: /tmp/tmp.abc123
[INFO] To restore backups, run: sudo ./setup-vm-network.sh -r
```
## Restore Run
```
[INFO] Restoring all backed-up files...
[INFO] Restoring /tmp/tmp.abc123 from /tmp/tmp.abc123.bak
[INFO] All backups restored successfully.
```
### Notes
- Backup Location: Backups are in /tmp since virsh dumpxml uses temporary files. These persist until the script removes them (rm -f "$TEMP_FILE") or the system clears /tmp.
- Scope: Only VM XML files are backed up here, as no other files (e.g., Netplan configs) are modified directly by the script.
- Restore Limitation: Tracks backups from the current run only; previous runs’ backups aren’t automatically included unless you persist BACKED_UP_FILES.
- Let me know if you’d like to expand this (e.g., persistent backup tracking, backing up guest configs via SSH)! The script now ensures safe modifications with easy rollback.
