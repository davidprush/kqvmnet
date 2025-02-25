#!/bin/bash

# Script to configure KVM/QEMU VM networking with a bridge on Ubuntu 24.04
# Usage: sudo ./kqvmnet.sh [-p PHYSICAL_IFACE] [-b BRIDGE_NAME] [-v VM_NAME] [-e VM_TO_EDIT] [-g GUEST_IFACE] [-r] [-h]

# Immediate sudo check
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31m[ERROR]\033[0m This script must be run as root (sudo). Please run with sudo and try again."
    exit 1
fi

# Default values
PHYSICAL_IFACE="enx0011226830b1"  # Default physical interface
BRIDGE_NAME="br0"                 # Default bridge name
VM_NAME="timemachine"             # Default VM to configure fully
VM_TO_EDIT=()                     # Array of VMs to edit network interface
GUEST_IFACE="enp9s0"              # Default guest interface ID
RESTORE=false                     # Flag for restore operation

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Array to track files backed up
declare -a BACKED_UP_FILES

# Function to print verbose messages
verbose() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Function to print errors and exit
error_exit() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Function to prompt user for confirmation
confirm() {
    echo -e "${YELLOW}[PROMPT]${NC} $1 (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        error_exit "User aborted the operation."
    fi
}

# Function to prompt for guest interface ID
prompt_guest_iface() {
    echo -e "${YELLOW}[PROMPT]${NC} Enter the guest OS network interface ID (e.g., enp9s0) for $VM_NAME: "
    read -r GUEST_IFACE
    if [[ -z "$GUEST_IFACE" ]]; then
        error_exit "Guest interface ID cannot be empty."
    fi
    verbose "Using guest interface ID: $GUEST_IFACE"
}

# Function to backup a file before modification
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="$file.bak"
        verbose "Backing up $file to $backup"
        cp "$file" "$backup" || error_exit "Failed to create backup of $file"
        BACKED_UP_FILES+=("$file")  # Track the file
    else
        verbose "File $file does not exist, no backup needed."
    fi
}

# Function to restore all backed-up files
restore_backups() {
    if [[ ${#BACKED_UP_FILES[@]} -eq 0 ]]; then
        verbose "No backups found to restore."
        exit 0
    fi

    verbose "Restoring all backed-up files..."
    for file in "${BACKED_UP_FILES[@]}"; do
        local backup="$file.bak"
        if [[ -f "$backup" ]]; then
            verbose "Restoring $file from $backup"
            cp "$backup" "$file" || error_exit "Failed to restore $file from $backup"
            # For VM XML, reapply to libvirt
            if [[ "$file" =~ ^/.*\.xml$ ]]; then
                virsh define "$file" || error_exit "Failed to redefine VM from restored $file"
            fi
        else
            echo -e "${YELLOW}[WARNING]${NC} Backup $backup not found, skipping."
        fi
    done
    verbose "All backups restored successfully."
    exit 0
}

# Function to display help menu
show_help() {
    echo -e "${GREEN}KVM/QEMU VM Networking Setup Script${NC}"
    echo "This script configures a network bridge on Ubuntu 24.04 for KVM/QEMU VMs,"
    echo "ensuring they can obtain DHCP IPs from the local network."
    echo
    echo -e "${YELLOW}Usage:${NC}"
    echo "  sudo ./kqvmnet.sh [OPTIONS]"
    echo
    echo -e "${YELLOW}Options:${NC}"
    echo "  -p PHYSICAL_IFACE  Specify the physical network interface to bridge (default: enx0011226830b1)"
    echo "  -b BRIDGE_NAME     Specify the bridge name (default: br0)"
    echo "  -v VM_NAME         Specify the main VM to fully configure (default: timemachine)"
    echo "  -e VM_TO_EDIT      Edit the network interface of an additional VM (can be used multiple times)"
    echo "  -g GUEST_IFACE     Specify the guest OS network interface ID (default: enp9s0)"
    echo "  -r, --restore      Restore all backed-up files to their original state"
    echo "  -h, --help         Display this help menu and exit"
    echo
    echo -e "${YELLOW}Arguments:${NC}"
    echo "  PHYSICAL_IFACE     The physical NIC to connect to the bridge (e.g., eth0, enx0011226830b1)"
    echo "  BRIDGE_NAME        The name of the bridge interface (e.g., br0, mybridge)"
    echo "  VM_NAME            The main VM to configure with bridge and guest OS networking"
    echo "  VM_TO_EDIT         Additional VM(s) to update network interface to use the bridge"
    echo "  GUEST_IFACE        The network interface ID inside the guest OS (e.g., enp9s0, eth0)"
    echo
    echo -e "${YELLOW}Examples:${NC}"
    echo "  sudo ./kqvmnet.sh                          # Use defaults (enx0011226830b1, br0, timemachine, enp9s0)"
    echo "  sudo ./kqvmnet.sh -p eth0 -b mybridge      # Custom physical interface and bridge"
    echo "  sudo ./kqvmnet.sh -v myvm -g eth0          # Configure myvm with guest interface eth0"
    echo "  sudo ./kqvmnet.sh -e vm1 -e vm2            # Edit network for vm1 and vm2"
    echo "  sudo ./kqvmnet.sh -p eth0 -b br0 -v vm1 -e vm2 -g enp1s0  # Full setup for vm1, edit vm2, use enp1s0"
    echo "  sudo ./kqvmnet.sh -r                       # Restore all backups"
    echo
    echo -e "${YELLOW}Notes:${NC}"
    echo "  - Must be run as sudo."
    echo "  - Backups are created with .bak extension in the same directory as originals."
    echo "  - Guest OS networking (Netplan) requires manual configuration inside the VM."
    echo "  - MAC address is hardcoded (52:54:00:aa:bb:cc); ensure uniqueness for multiple VMs."
    exit 0
}

# Function to edit a VM's XML for bridge networking
edit_vm_network() {
    local vm="$1"
    verbose "Editing network interface for VM: $vm"

    # Check if VM exists
    if ! virsh list --all | grep -q "$vm"; then
        error_exit "VM $vm does not exist."
    fi

    # Stop VM if running
    if virsh list | grep -q "$vm.*running"; then
        verbose "Stopping $vm to update configuration..."
        virsh destroy "$vm" || error_exit "Failed to stop $vm"
    fi

    # Update VM network interface XML
    TEMP_FILE=$(mktemp)
    virsh dumpxml "$vm" > "$TEMP_FILE" || error_exit "Failed to dump $vm XML"
    
    # Backup the original XML file
    backup_file "$TEMP_FILE"

    # Check if interface exists and update it
    if grep -q "<interface type='bridge'" "$TEMP_FILE"; then
        verbose "Existing bridge interface found in $vm, updating it..."
        sed -i "/<interface type='bridge'/,/<\/interface>/c\
        <interface type='bridge'>\n\
          <mac address='52:54:00:aa:bb:cc'/>\n\
          <source bridge='$BRIDGE_NAME'/>\n\
          <model type='virtio'/>\n\
        </interface>" "$TEMP_FILE" || error_exit "Failed to update interface in $vm XML"
    else
        verbose "Adding new bridge interface to $vm..."
        sed -i "/<\/devices>/i\
        <interface type='bridge'>\n\
          <mac address='52:54:00:aa:bb:cc'/>\n\
          <source bridge='$BRIDGE_NAME'/>\n\
          <model type='virtio'/>\n\
        </interface>" "$TEMP_FILE" || error_exit "Failed to add interface to $vm XML"
    fi

    # Apply updated XML
    virsh define "$TEMP_FILE" || error_exit "Failed to redefine $vm"
    rm -f "$TEMP_FILE"

    # Start VM
    verbose "Starting $vm..."
    virsh start "$vm" || error_exit "Failed to start $vm"
}

# Parse command-line arguments
while getopts "p:b:v:e:g:rh-:" opt; do
    case $opt in
        p) PHYSICAL_IFACE="$OPTARG";;
        b) BRIDGE_NAME="$OPTARG";;
        v) VM_NAME="$OPTARG";;
        e) VM_TO_EDIT+=("$OPTARG");;
        g) GUEST_IFACE="$OPTARG";;
        r) RESTORE=true;;
        h) show_help;;
        -) # Handle long options
            case "$OPTARG" in
                restore) RESTORE=true;;
                help) show_help;;
                *) error_exit "Unknown option --$OPTARG";;
            esac;;
        ?) error_exit "Invalid option. Usage: $0 [-p PHYSICAL_IFACE] [-b BRIDGE_NAME] [-v VM_NAME] [-e VM_TO_EDIT] [-g GUEST_IFACE] [-r] [-h]";;
    esac
done

# If restore flag is set, perform restore and exit
if $RESTORE; then
    restore_backups
fi

verbose "Script is running with sudo privileges."
verbose "Configuration parameters:"
echo "  Physical Interface: $PHYSICAL_IFACE"
echo "  Bridge Name: $BRIDGE_NAME"
echo "  Main VM Name: $VM_NAME"
echo "  Guest Interface ID: $GUEST_IFACE"
echo "  VMs to Edit Network: ${VM_TO_EDIT[*]}"
confirm "Proceed with these settings?"

# Check if required tools are installed
for tool in nmcli virsh ip bridge; do
    if ! command -v "$tool" &>/dev/null; then
        error_exit "$tool is not installed. Please install it (e.g., sudo apt install $tool)."
    fi
done
verbose "All required tools (nmcli, virsh, ip, bridge) are installed."

# Step 1: Clean up existing conflicting connections
verbose "Cleaning up old network connections..."

# Remove any existing bridge or interface connections except the target ones
for conn in $(nmcli -f NAME,UUID connection show | grep -v "$BRIDGE_NAME" | grep -v "lo" | grep -v "enp3s0" | awk '{print $2}'); do
    verbose "Removing connection UUID: $conn"
    nmcli connection delete "$conn" || error_exit "Failed to delete connection $conn"
done

# Remove virbr0 if it exists
if ip link show virbr0 &>/dev/null; then
    verbose "Removing default libvirt bridge virbr0..."
    virsh net-destroy default &>/dev/null || true
    virsh net-undefine default &>/dev/null || true
    ip link delete virbr0 || error_exit "Failed to delete virbr0"
fi

# Step 2: Configure the bridge
verbose "Setting up bridge: $BRIDGE_NAME"

# Check if bridge already exists
if nmcli connection show "$BRIDGE_NAME" &>/dev/null; then
    verbose "Bridge $BRIDGE_NAME already exists. Ensuring it has no IP."
    nmcli connection modify "$BRIDGE_NAME" ipv4.method manual ipv4.addresses "" || error_exit "Failed to modify $BRIDGE_NAME"
else
    verbose "Creating new bridge: $BRIDGE_NAME"
    nmcli connection add type bridge ifname "$BRIDGE_NAME" con-name "$BRIDGE_NAME" ipv4.method manual || error_exit "Failed to create bridge $BRIDGE_NAME"
fi

# Get bridge UUID
BRIDGE_UUID=$(nmcli -f UUID connection show "$BRIDGE_NAME" | awk 'NR>1 {print $1}')
if [[ -z "$BRIDGE_UUID" ]]; then
    error_exit "Failed to retrieve UUID for $BRIDGE_NAME"
fi
verbose "Bridge UUID: $BRIDGE_UUID"

# Step 3: Enslave physical interface to bridge
verbose "Configuring $PHYSICAL_IFACE as a slave to $BRIDGE_NAME..."

# Check if physical interface exists
if ! ip link show "$PHYSICAL_IFACE" &>/dev/null; then
    error_exit "Physical interface $PHYSICAL_IFACE does not exist."
fi

# Create or update the physical interface connection
PHYSICAL_CONN="enxusb"  # Connection name for the physical interface
if nmcli connection show "$PHYSICAL_CONN" &>/dev/null; then
    verbose "Updating existing connection $PHYSICAL_CONN"
    nmcli connection modify "$PHYSICAL_CONN" master "$BRIDGE_UUID" connection.slave-type bridge || error_exit "Failed to modify $PHYSICAL_CONN"
else
    verbose "Creating new connection for $PHYSICAL_IFACE"
    nmcli connection add type ethernet ifname "$PHYSICAL_IFACE" con-name "$PHYSICAL_CONN" master "$BRIDGE_UUID" || error_exit "Failed to create $PHYSICAL_CONN"
fi

# Activate connections
verbose "Activating network connections..."
nmcli connection up "$PHYSICAL_CONN" || error_exit "Failed to activate $PHYSICAL_CONN"
nmcli connection up "$BRIDGE_NAME" || error_exit "Failed to activate $BRIDGE_NAME"

# Verify bridge setup
verbose "Verifying bridge setup..."
if ! bridge link | grep -q "$PHYSICAL_IFACE.*master $BRIDGE_NAME"; then
    error_exit "$PHYSICAL_IFACE is not enslaved to $BRIDGE_NAME"
fi
verbose "$PHYSICAL_IFACE is successfully enslaved to $BRIDGE_NAME"

# Step 4: Configure main VM networking (if specified)
if [[ -n "$VM_NAME" ]]; then
    verbose "Configuring main VM: $VM_NAME"
    edit_vm_network "$VM_NAME"

    # Step 5: Configure guest OS networking for main VM (assumes Ubuntu 24.04)
    verbose "Configuring guest OS networking for $VM_NAME..."

    # Prompt for guest interface if not provided via -g
    if [[ "$GUEST_IFACE" == "enp9s0" && -z "$OPTARG" ]]; then
        prompt_guest_iface
    fi

    verbose "Using guest interface ID: $GUEST_IFACE for $VM_NAME"
    echo "Please ensure SSH access or manually configure Netplan inside $VM_NAME:"
    echo "  1. SSH into $VM_NAME or use 'virsh console $VM_NAME'"
    echo "  2. Run these commands inside the VM:"
    echo "     sudo nano /etc/netplan/01-netcfg.yaml"
    echo "     Paste:"
    echo "       network:"
    echo "         version: 2"
    echo "         ethernets:"
    echo "           $GUEST_IFACE:"
    echo "             dhcp4: true"
    echo "     Save and exit, then run:"
    echo "     sudo netplan apply"
    echo "     sudo systemctl restart systemd-resolved"
fi

# Step 6: Edit additional VMs' network interfaces (if specified)
if [[ ${#VM_TO_EDIT[@]} -gt 0 ]]; then
    verbose "Editing network interfaces for additional VMs..."
    for vm in "${VM_TO_EDIT[@]}"; do
        confirm "Edit network interface for VM: $vm?"
        edit_vm_network "$vm"
    done
fi

# Final verification
verbose "Final verification of host bridge setup..."
sudo ip link
bridge link

verbose "Setup complete! Please verify DNS resolution and connectivity inside all configured VMs."
verbose "If DNS issues persist, manually set nameservers in /etc/resolv.conf or ensure systemd-resolved is running."
verbose "Backed-up files: ${BACKED_UP_FILES[*]}"
verbose "To restore backups, run: sudo $0 -r"
