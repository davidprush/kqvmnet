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
