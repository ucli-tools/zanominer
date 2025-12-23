<h1> Zano Blockchain Mining and Staking Script for Ubuntu Nvidia GPU Node </h1>

<h2>Table of Contents</h2>

- [Introduction](#introduction)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [Interactive Menu](#interactive-menu)
  - [Command Line Interface](#command-line-interface)
  - [Examples](#examples)
- [Wallet Management](#wallet-management)
- [Mining Configuration](#mining-configuration)
- [Service Management](#service-management)
- [Logging System](#logging-system)
- [Security Features](#security-features)
- [Important Notes](#important-notes)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Support](#support)

## Introduction

A comprehensive script for managing Zano blockchain nodes, including wallet management, GPU mining, and PoS staking on Ubuntu systems. Features both interactive and command-line interfaces.

## Features

- Interactive menu-driven interface
- Multiple wallet management options
  - Create new wallets
  - Import existing wallets
  - Restore from seed phrase
- Flexible mining options
  - Solo mining
  - Pool mining (WoolyPooly support)
  - Custom worker names
- Advanced logging system
- Automated NVIDIA driver setup
- Systemd service integration
- Secure password management
- Complete uninstall capability

## Requirements

- Ubuntu Desktop
- NVIDIA GPU (recommended)
- Sudo privileges
- Internet connection
- Base utilities (curl, wget, jq)

## Installation

```bash
# Download
wget https://raw.githubusercontent.com/ucli-tools/zanominer/main/zanominer.sh

# Install
bash zanominer.sh install

# Remove installer
rm zanominer.sh
```

## Usage

### Interactive Menu

Run `zanominer` without arguments to access the menu:

1. Start mining and staking
2. Show status of services
3. Start services
4. Stop services
5. Restart services
6. Show logs
7. Delete logs
8. Exit

### Command Line Interface

```bash
zanominer [COMMAND]
```

Available commands:
- `status` - Show all component status
- `install` - System-wide installation
- `uninstall` - Remove installation
- `build` - Complete setup
- `start` - Start services
- `stop` - Stop services
- `restart` - Restart services
- `logs` - View service logs
- `delete-logs` - Clean up logs
- `help` - Show help message

### Examples

```bash
# Interactive mode
zanominer

# Check status
zanominer status

# Full installation
zanominer build
```

## Wallet Management

Three wallet setup methods:
1. Create new wallet
   - Custom or auto-generated passwords
   - Secure seed phrase generation
2. Import wallet file
   - Existing wallet support
   - Password verification
3. Import from seed phrase
   - Secure recovery process
   - Optional seed password

## Mining Configuration

- Solo mining setup
  - Local node configuration
  - Stratum server setup
- Pool mining options
  - WoolyPooly integration
  - Custom worker names
  - SSL connection support

## Service Management

Managed services:
1. `zanod.service` - Blockchain daemon
2. `tt-miner.service` - GPU mining
3. `zano-pos-mining.service` - PoS staking

## Logging System

Advanced logging with:
- Separate service logs
- Error logging
- Installation logging
- Log viewing interface
- Log cleanup tools

## Security Features

- Secure password generation
- Protected wallet files
- Service isolation
- Secure seed phrase handling
- No root execution
- Temporary file cleanup

## Important Notes

- Backup wallet details immediately
- Store seed phrases securely
- Monitor system resources
- Keep system updated
- Use at your own risk

## Troubleshooting

1. Check status: `zanominer status`
2. View logs: `zanominer logs`
3. Verify services: `systemctl status zanod`
4. Check NVIDIA: `nvidia-smi`
5. Monitor resources: `top` or `htop`

## License

Apache License 2.0

## Support

Issues and questions:
[GitHub Repository](https://github.com/Mik-TF/zanominer)

For more information on Zano:
[Zano Documentation](https://docs.zano.org/)
