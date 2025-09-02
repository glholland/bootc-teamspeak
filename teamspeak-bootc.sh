#!/bin/bash

# TeamSpeak Bootc Management Script
# All-in-one script for building, deploying, updating, and debugging TeamSpeak bootc containers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
IMAGE_NAME="localhost/teamspeak-bootc"
CONFIG_FILE="$PROJECT_DIR/config/config.toml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

show_usage() {
    cat << EOF
TeamSpeak Bootc Management Script

USAGE:
    $0 <command> [options]

COMMANDS:
    build           Build the bootc container image
    deploy          Create bootc disk image for deployment
    clean           Remove old images and clean up
    help            Show this help message

EXAMPLES:
    $0 build                    # Build container image
    $0 deploy                   # Create .qcow2 disk image
    $0 clean                    # Clean up old images

    $0 genkey                   # Generate SSH key pair and kickstart lines

EOF
}

# Validation function

validate_configuration() {
    log_info "Validating TeamSpeak bootc configuration..."
    local errors=0
    
    # 1. Validate project directory structure
    log_info "Checking directory structure..."
    if [[ ! -f "$PROJECT_DIR/Containerfile" ]] || [[ ! -f "$PROJECT_DIR/config/teamspeak.service" ]]; then
        log_error "Not in TeamSpeak project directory or missing required files"
        log_info "Expected files: Containerfile, config/teamspeak.service"
        ((errors++))
    else
        log_success "Directory structure validated"
    fi
    
    # 2. Validate required configuration files
    log_info "Checking configuration files..."
    local files=(
        "$PROJECT_DIR/config/ts3server.ini"
        "$CONFIG_FILE"
        "$PROJECT_DIR/config/teamspeak.service"
        "$PROJECT_DIR/Containerfile"
        "$PROJECT_DIR/config/config.toml"
    )
    
    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file not found: $file"
            ((errors++))
        else
            log_success "Found: $(basename "$file")"
        fi
    done
    
    # 3. Validate service configuration
    log_info "Validating service file settings..."
    if ! grep -q "ReadWritePaths=/var/lib/teamspeak" "$PROJECT_DIR/config/teamspeak.service"; then
        log_error "Missing ReadWritePaths=/var/lib/teamspeak"
        ((errors++))
    fi
    
    # 4. Validate SSH keys if referenced in config
    log_info "Checking SSH key configuration..."
    if [[ -f "$CONFIG_FILE" ]] && grep -q "sshkey" "$CONFIG_FILE" 2>/dev/null; then
        if [[ -d "$PROJECT_DIR/keys" ]]; then
            if ! ls "$PROJECT_DIR/keys"/*.pub >/dev/null 2>&1; then
                log_warning "SSH public key files referenced but not found in keys directory"
                ((errors++))
            else
                log_success "SSH public key files found"
            fi
        else
            log_warning "SSH keys referenced in config but keys directory not found"
            ((errors++))
        fi
    fi
    
    # 5. Return validation results
    if [[ $errors -eq 0 ]]; then
        log_success "All configuration validated successfully"
        return 0
    else
        log_error "Configuration validation failed with $errors errors"
        return 1
    fi
}

# Build function
cmd_build() {
    log_info "Building TeamSpeak bootc container..."

    validate_configuration

    cd "$PROJECT_DIR"

    log_info "Building $IMAGE_NAME..."
    if sudo podman build -t "$IMAGE_NAME" . ; then
        log_success "Image built successfully"
    else
        log_error "Image build failed"
        return 1
    fi

    # Validate built image
    log_info "Validating built image..."

    if sudo podman run --rm "$IMAGE_NAME" test -f /opt/teamspeak3-server/ts3server; then
        log_success "TeamSpeak binary exists"
    else
        log_error "TeamSpeak binary missing"
        return 1
    fi

    if sudo podman run --rm "$IMAGE_NAME" test -f /opt/teamspeak3-server/sql/create_sqlite/create_tables.sql; then
        log_success "SQL schema files exist"
    else
        log_error "SQL schema files missing - database initialization will fail"
        return 1
    fi

    log_success "Build completed successfully!"
    log_info "Next step: Run '$0 deploy' to create bootc disk image"
}

# Deploy function
cmd_deploy() {
    log_info "Creating bootc ISO image for deployment..."

    if ! sudo podman image exists "$IMAGE_NAME"; then
        log_error "Image $IMAGE_NAME not found. Run '$0 build' first."
        return 1
    fi

    # Validate config.toml exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "config/config.toml not found. This file is required for user injection."
        return 1
    fi

    log_info "Validating bootc configuration..."
    if grep -q "customizations.installer.kickstart" "$CONFIG_FILE"; then
        log_success "Kickstart configuration validated"
    else
        log_error "config/config.toml missing required kickstart section"
        return 1
    fi

    mkdir -p "$PROJECT_DIR/output"

    log_info "Creating bootc ISO image (this may take several minutes)..."
    if sudo podman run --memory 24g --rm -it --privileged --pull=newer \
         -v "$CONFIG_FILE:/config.toml:ro" \
         -v "$PROJECT_DIR/output:/output" \
         -v /var/lib/containers/storage:/var/lib/containers/storage \
         quay.io/centos-bootc/bootc-image-builder:latest \
         --rootfs ext4 \
         --type anaconda-iso "$IMAGE_NAME"; then

        log_success "Bootc ISO image created successfully!"
        log_info "ISO image location: $PROJECT_DIR/output/install.iso"

        echo
        log_info "DEPLOYMENT STEPS (AUTOMATED KICKSTART INSTALLATION):"
        echo "1. Upload install.iso to Proxmox ISO storage"
        echo "2. Create new VM with at least 4GB RAM and 20GB disk"
        echo "3. Attach the ISO as CD/DVD and set as boot device"
        echo "4. Boot VM - installation will proceed automatically (no interaction needed)"
        echo "5. After auto-reboot: ssh fedora@<vm-ip> (password: password)"
        echo "6. TeamSpeak will be running automatically: sudo systemctl status teamspeak"
        echo "7. TeamSpeak server admin token will be in: /opt/teamspeak3-server/logs/ts3server_*.log"

    else
        log_error "Failed to create bootc disk image"
        return 1
    fi
}

# Clean function
cmd_clean() {
    log_info "Cleaning up old images and containers..."

    # Remove old TeamSpeak images
    if sudo podman images | grep -q teamspeak; then
        sudo podman rmi $(sudo podman images | grep teamspeak | awk '{print $3}') 2>/dev/null || true
        log_success "Removed old TeamSpeak images"
    fi

    # Clean up build cache
    sudo podman system prune -f

    # Clean output directory
    if [[ -d "$PROJECT_DIR/output" ]]; then
        rm -rf "$PROJECT_DIR/output"
        log_success "Cleaned output directory"
    fi

    log_success "Cleanup completed"
}

# Generate SSH key pair and output kickstart lines
cmd_genkey() {
    log_info "Generating SSH key pair for kickstart injection..."
    local key_dir="$PROJECT_DIR/keys"
    local key_name="teamspeak-bootc-admin"
    mkdir -p "$key_dir"
    local privkey="$key_dir/$key_name"
    local pubkey="$key_dir/$key_name.pub"
    if [[ -f "$privkey" || -f "$pubkey" ]]; then
        log_warning "Key files already exist: $privkey, $pubkey"
        read -p "Overwrite existing keys? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Aborting key generation."
            return 0
        fi
        rm -f "$privkey" "$pubkey"
    fi
    ssh-keygen -t ed25519 -f "$privkey" -N "" -C "teamspeak-bootc-admin"
    log_success "SSH key pair generated: $privkey, $pubkey"
    local pubkey_content
    pubkey_content=$(cat "$pubkey")
    echo
    read -s -p "Enter password for kickstart user [default: password]: " userpw
    userpw=${userpw:-password}
    echo
    read -p "Enter username for kickstart user [default: fedora]: " username
    username=${username:-fedora}
    echo
    log_info "Injecting user and sshkey lines into config.toml kickstart section..."
    local config_file="$CONFIG_FILE"
    local kickstart_marker="# Automated TeamSpeak Bootc Installation"
    local user_line="user --name=$username --password=$userpw --groups=wheel --homedir=/var/home/$username --shell=/bin/bash"
    local sshkey_line="sshkey --username=$username \"$pubkey_content\""
    if grep -q "$kickstart_marker" "$config_file"; then
        # Remove all previous user/sshkey lines and insert new ones after the marker
        sed "/^user --name=/d;/^sshkey --username=/d" "$config_file" | \
        awk -v u="$user_line" -v k="$sshkey_line" -v m="$kickstart_marker" '
            { print }
            $0 ~ m { print u; print k }
        ' > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
        log_success "Kickstart admin user and sshkey injected into config.toml."
    else
        log_error "Kickstart marker not found in config.toml. Please add manually."
        echo "$user_line"
        echo "$sshkey_line"
    fi
    log_success "Done."
}

# Main function
main() {
    case "${1:-help}" in
        build)
            cmd_build
            ;;
        deploy)
            cmd_deploy
            ;;
        clean)
            cmd_clean
            ;;
        genkey)
            cmd_genkey
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: ${1:-}"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
