# SSH Key Management for TeamSpeak Bootc

## Generated SSH Keys

This directory contains the SSH key pair for accessing the TeamSpeak Bootc VM:

- `teamspeak-bootc-admin` - Private key (keep secure)
- `teamspeak-bootc-admin.pub` - Public key (embedded in the container image)

## Usage

### SSH Access to VM

```bash
# SSH using the private key
ssh -i keys/teamspeak-bootc-admin fedora@<vm-ip>

# Or add the key to your SSH agent
ssh-add keys/teamspeak-bootc-admin
ssh fedora@<vm-ip>
```

### Key Information

- **Key Type**: Ed25519 (modern, secure)
- **Comment**: teamspeak-bootc-admin
- **User**: fedora (with sudo access via wheel group)

## Security Notes

- The private key should be kept secure and not shared
- The public key is embedded in the container image during build
- Both password and key-based authentication are enabled for flexibility
- Default password is "password" (change in production)

## Regenerating Keys and Injecting into Kickstart

To generate a new SSH key pair and automatically inject the credentials into your kickstart config:

```bash
# Run the management script
./teamspeak-bootc.sh genkey
```

### This command will

- Generate a new key pair in the keys/ directory
- Prompt for username and password
- Automatically update config/config.toml with the new user and public key
- You can then build and deploy your image as usual

No manual editing of the Containerfile or config is required—the script handles key placement and password injection for you.

**Note**: The password is only encoded in the kickstart config and not encrypted.
