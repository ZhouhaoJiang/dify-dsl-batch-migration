# Dify Batch Migration Tool

This is an automated script tool for batch migrating applications between different Dify environments.

## Features

- 🚀 **Automated Migration**: Export applications from the source environment and import them into the target environment automatically
- 🔧 **Flexible Configuration**: Configure various environment parameters via the `.env` file
- 📋 **Selective Migration**: Migrate all applications or specify particular application IDs
- 🔄 **Retry Mechanism**: Built-in retry logic to improve migration success rate
- 📁 **Backup Functionality**: Automatically creates backups and saves all exported application files
- 🔍 **Logging**: Detailed operation logs with support for different log levels
- 🧪 **Dry Run Mode**: Test mode to validate configuration without actual migration
- 📊 **Progress Tracking**: Real-time display of migration progress and statistics

## TODO
- [ ] Multi-Workspace Migration

## Prerequisites

### System Dependencies
- `bash` (version 4.0+)
- `curl`
- `jq` (for JSON processing)

### Install dependencies on macOS
```bash
brew install jq
```

### Install dependencies on Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install curl jq
```

### Install dependencies on CentOS/RHEL
```bash
sudo yum install curl jq
```

## Quick Start

### 1. Clone or Download the Project
```bash
git clone <repository-url>
cd batch-migration-dsl
```

### 2. Configure the Environment File
```bash
# Copy the template
cp env.example .env

# Edit the configuration file
vim .env
```

### 3. Set Required Parameters
In the `.env` file, set the following required parameters:

```bash
# Source environment
SOURCE_DIFY_URL=https://your-source.dify.ai
SOURCE_BEARER_TOKEN=your_source_bearer_token

# Target environment
TARGET_DIFY_URL=https://your-target.dify.ai
TARGET_BEARER_TOKEN=your_target_bearer_token
```

### 4. Run Migration
```bash
# Make the script executable
chmod +x migrate-apps.sh

# Run full migration
./migrate-apps.sh
```

## Detailed Usage Guide

### Environment Configuration File

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `SOURCE_DIFY_URL` | Source environment URL | ✅ | - |
| `SOURCE_BEARER_TOKEN` | Source environment access token | ✅ | - |
| `TARGET_DIFY_URL` | Target environment URL | ✅ | - |
| `TARGET_BEARER_TOKEN` | Target environment access token | ✅ | - |
| `APP_IDS_TO_MIGRATE` | Comma-separated list of app IDs to migrate | ❌ | All apps |
| `INCLUDE_SECRET` | Include sensitive info (e.g., API keys) | ❌ | false |
| `BACKUP_DIR` | Backup directory path | ❌ | ./backups |
| `LOG_LEVEL` | Log level | ❌ | INFO |
| `MAX_RETRIES` | Max retry count | ❌ | 3 |
| `DRY_RUN` | Dry run mode | ❌ | false |

### Command Line Options

```bash
./migrate-apps.sh [options] [env file]

Options:
  -h, --help          Show help
  -c, --config        Specify environment config file (default: .env)
  -a, --apps          Specify app IDs to migrate, comma-separated
  -d, --dry-run       Dry run mode, test only, no actual migration
  -v, --verbose       Verbose output (DEBUG mode)
  --export-only       Only export, do not import
  --import-only       Only import YAML files from specified directory
```

### Usage Examples

#### 1. Basic Usage
```bash
./migrate-apps.sh
```

#### 2. Specify Config File
```bash
./migrate-apps.sh -c production.env
```

#### 3. Migrate Specific Apps
```bash
./migrate-apps.sh -a "app-id-1,app-id-2,app-id-3"
```

#### 4. Dry Run Test
```bash
./migrate-apps.sh -d
```

#### 5. Verbose Logging
```bash
./migrate-apps.sh -v
```

#### 6. Step-by-step Execution
**Export only:**
```bash
./migrate-apps.sh --export-only
```

**Import only:**
```bash
./migrate-apps.sh --import-only
./migrate-apps.sh --import-only ./my-exported-apps
```

#### 7. Combined Usage
```bash
./migrate-apps.sh -c staging.env -v -d -a "app-123,app-456"
```

## How to Get Bearer Token

### Method 1: Browser DevTools
1. Log in to Dify Console
2. Open browser DevTools (F12)
3. Go to the Network tab
4. Trigger any API request
5. Find the `authorization: Bearer <token>` header
6. Copy the token value

### Method 2: Browser Local Storage
1. Log in to Dify Console
2. Open browser DevTools (F12)
3. Go to the Application tab
4. Go to Local Storage
5. Find `access_token` and `refresh_token` under the `dify.ai` domain
6. Copy the values

## Directory Structure

```
batch-migration-dsl/
├── migrate-apps.sh     # Main migration script
├── env.example         # Environment config template
├── .env               # Your environment config (to be created)
├── example/           # Example scripts
│   ├── export-dsl-curl-example.sh
│   ├── import-dsl-example.sh
│   └── get-all-apps-example.sh
├── backups/          # Backup directory (auto-created)
│   └── migration_YYYYMMDD_HHMMSS/
└── README.en.md      # This documentation
```

## Backup & Restore

### Backup Location
All exported apps are saved in the backup directory:
```
backups/migration_20240115_143022/
├── app-id-1_app1.yaml
├── app-id-2_app2.yaml
├── exported_files.list
├── import_success_*.json
└── import_error_*.json
```

### Restore Apps
To restore or re-import apps:
```bash
./migrate-apps.sh --import-only ./backups/migration_20240115_143022
```

## Troubleshooting

### Common Issues

#### 1. Token Expired
**Error**: `401 Unauthorized` or `403 Forbidden`
**Solution**: Get a new Bearer Token and update your .env file

#### 2. Network Issues
**Error**: `curl: (6) Could not resolve host`
**Solution**: Check your network and URL config

#### 3. Import Failed
**Error**: App format incompatible
**Solution**: Check Dify version compatibility between source and target

#### 4. Permission Denied
**Error**: Cannot create backup directory
**Solution**: Ensure script has write permission
```bash
chmod +x migrate-apps.sh
mkdir -p backups
```

### Log Analysis
Enable verbose logging for diagnosis:
```bash
./migrate-apps.sh -v 2>&1 | tee migration.log
```

### Test Connection
Use dry run mode to test config:
```bash
./migrate-apps.sh -d -v
```

## Security Notes

1. **Token Security**:
   - Do not commit .env files with real tokens to version control
   - Rotate tokens regularly
   - Use least privilege principle

2. **Sensitive Info**:
   - By default, sensitive info is not exported (`INCLUDE_SECRET=false`)
   - If exporting secrets, ensure backup directory is secure

3. **Network Security**:
   - Run migration in a secure network environment
   - Consider using VPN or private network

## Performance Tips

### Large Scale Migration

1. **Batch Migration**:
```bash
./migrate-apps.sh -a "app1,app2,app3"
./migrate-apps.sh -a "app4,app5,app6"
```

2. **Export then Import**:
```bash
./migrate-apps.sh --export-only
./migrate-apps.sh --import-only
```

3. **Adjust Retry Count**:
```bash
MAX_RETRIES=5
```

## Contribution Guide

Contributions are welcome! Please submit issues and pull requests.

### Dev Environment Setup
```bash
git clone <repository-url>
cd batch-migration-dsl
cp env.example .env.dev
```

### Testing
```bash
./migrate-apps.sh -c .env.dev -d -v
```

## License

[License Info]

## Changelog

### v1.0.0
- Initial release
- Support for basic app export/import
- Environment config file support
- Retry mechanism and error handling
- Backup and logging features