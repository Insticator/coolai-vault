# CoolAI Vault

A production-ready HashiCorp Vault deployment with automated initialization and unsealing for secure secrets management.

## Features

- **Automated Installation**: One-command Vault installation on Ubuntu
- **Auto Initialization**: Automated vault initialization and unsealing
- **Raft Storage**: High-availability storage backend
- **Web UI**: Modern web interface for secrets management
- **Python SDK**: Ready-to-use Python examples and utilities
- **Security**: Hardened configuration with proper permissions

## Quick Start

### Install Vault

```bash
# Copy to server
scp -r . root@<SERVER_IP>:/root/vault

# Install Vault
ssh root@<SERVER_IP>
cd /root/vault
sudo bash install_vault.sh
```

### Initialize and Unseal

```bash
# Automated initialization and unsealing
sudo bash vault_auto_init_unseal.sh

# Check status
vault status
```

### Access Vault

```bash
# CLI access
vault login <root-token>

# Web UI
open http://<SERVER_IP>:8200/ui
```

## Configuration

| Component | Port | Purpose |
|-----------|------|---------|
| Vault API | 8200 | CLI and API access |
| Web UI | 8200/ui | Browser interface |
| Storage | Raft | High-availability backend |

## Python Integration

```bash
# Setup Python environment
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Bootstrap example setup
export VAULT_TOKEN='<root-token>'
python test_example/bootstrap_setup.py

# Fetch secrets
python test_example/fetch_test_secret.py
```

## Security Features

- **Encrypted Storage**: All secrets encrypted at rest
- **Access Policies**: Fine-grained permission control
- **Audit Logging**: Complete audit trail
- **Token Management**: Secure token lifecycle
- **Unseal Keys**: Distributed key shares for security

## Management Commands

```bash
# Reinstall (preserve data)
sudo bash install_vault.sh --reinstall

# Reinstall (wipe data)
sudo bash install_vault.sh --reinstall --purge-data

# Manual unseal
vault operator unseal <unseal-key>
```

## Requirements

- Ubuntu 20.04/22.04/24.04 LTS
- Root access
- Port 8200 open
- 2+ GB RAM recommended

## License

MIT License - see [LICENSE](LICENSE) file.