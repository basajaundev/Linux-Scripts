# AGENTS.md - Guidelines for Agentic Coding in This Repository

This document provides guidelines for AI agents operating in the Linux-Scripts repository.

## Repository Overview

This is a collection of bash scripts for Linux system administration, currently containing:
- `git-helper.sh` - Git command wrapper with GitHub API integration
- `mariadb-helper.sh` - MariaDB/MySQL database management script

All scripts are standalone bash executables that work on any Linux system with required dependencies installed.

## Build, Lint, and Test Commands

### Executable Permissions
```bash
# Make script executable
chmod +x <script-name>.sh

# Verify executable status
ls -la *.sh
```

### Syntax Validation
```bash
# Check bash syntax without executing
bash -n <script-name>.sh

# Lint with shellcheck (recommended)
shellcheck <script-name>.sh

# Install shellcheck if needed
apt install shellcheck  # Debian/Ubuntu
yum install epel-release && yum install shellcheck  # RHEL/CentOS
```

### Shellcheck Suppressions
When disabling specific warnings, document the reason:
```bash
# shellcheck disable=SC2034  # Unused variables expected for config patterns
# shellcheck disable=SC2086  # Word splitting intentional for query results
```

### Testing Scripts
```bash
# Test script execution (dry run mode where applicable)
./<script-name>.sh --help

# Test specific functionality
./git-helper.sh status
./mariadb-helper.sh status

# Test with verbose output
bash -x <script-name>.sh <command>
```

### Testing on Multiple Systems
```bash
# Test script portability
docker run -v $(pwd):/scripts ubuntu:22.04 /bin/bash -c "apt update && apt install -y git mariadb-client && chmod +x /scripts/*.sh && /scripts/git-helper.sh help"
```

## Code Style Guidelines

### Shebang and Error Handling
```bash
#!/bin/bash
set -euo pipefail  # Strict error handling
```

### Color Output Constants
Define at script start for consistent styling:
```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'  # No Color
```

### Logging Functions
Create consistent logging helpers:
```bash
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
```

### Variable Naming
- Global constants: `UPPER_CASE` (e.g., `CONFIG_DIR`, `GITHUB_API_BASE`)
- Local variables: `lower_case` (e.g., `local username="$1"`)
- Arrays/associative arrays: `plural_lower_case` (e.g., `local -a options; local -A servers`)
- Config files: `$HOME/.config/<script-name>/`

### Function Naming
- Command handlers: `cmd_<action>` (e.g., `cmd_status()`, `cmd_commit()`)
- Helper utilities: `lower_case_verb` (e.g., `load_config()`, `check_connection()`)
- All functions must have docstrings for complex logic

### Function Structure
```bash
cmd_function_name() {
    local arg1="$1"
    local arg2="${2:-default}"
    
    # Validation
    if [ -z "$arg1" ]; then
        log_error "Usage: script function <arg1> [arg2]"
        exit 1
    fi
    
    # Core logic
    log_info "Processing..."
    # ...
    
    log_success "Operation completed"
}
```

### Parameter Handling
```bash
# Parse positional parameters
local command="${1:-}"
shift 2>/dev/null || true

# Handle flags
local flag=""
case "$command" in
    --flag|-f) flag="value"; shift ;;
esac

# Default values
local value="${1:-default_value}"
```

### Exit Codes
- `0` - Success
- `1` - General error
- `2` - Invalid arguments/usage error
- `3` - External dependency missing

### Configuration Management
```bash
CONFIG_DIR="$HOME/.config/<script-name>"
CONFIG_FILE="$CONFIG_DIR/config"

load_config() {
    mkdir -p "$CONFIG_DIR"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
VAR1="$VAR1"
VAR2="$VAR2"
EOF
    chmod 600 "$CONFIG_FILE"  # Protect sensitive data
}
```

### API Integration Patterns
For external API calls:
```bash
# Base URL constant
API_BASE="https://api.example.com"

# Request helper
api_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    curl -s -X "$method" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Accept: application/json" \
        "${API_BASE}${endpoint}" \
        ${data:+-d "$data"}
}
```

### Main Entry Point
```bash
main() {
    load_config
    
    local command="${1:-}"
    shift 2>/dev/null || true
    
    case "$command" in
        subcommand)
            cmd_subcommand "$@"
            ;;
        help|--help|-h)
            cmd_help
            ;;
        "")
            cmd_help
            exit 1
            ;;
        *)
            log_error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
```

### Output Format
- Use color-coded output for status messages
- Prefix with `[INFO]`, `[SUCCESS]`, `[ERROR]`, `[WARN]`
- Errors go to stderr (`>&2`)
- Output for consumption (API results) should be plain text

### Security Practices
- Store credentials in config files with `chmod 600`
- Never log passwords or tokens
- Use `MYSQL_PWD` environment variable for MySQL (more secure than CLI password)
- Validate all user inputs before use

### Command Design Pattern
All scripts should follow the command-subcommand pattern:
```
script command [options] [arguments]
script help
```

### Documentation
Every script should have:
1. Shebang at line 1
2. Color constants
3. Logging functions
4. Main entry point
5. Help command (`cmd_help`)
6. Usage examples in help text

## Adding New Scripts

1. Create `<script-name>.sh` with proper structure
2. Add to git: `git add <script-name>.sh && git commit -m "feat: Add <script-name>"`
3. Push: `git push origin main`
4. Installation: `sudo cp <script-name>.sh /usr/local/bin/<script-name> && chmod +x`

## Common Operations

### Git Workflow
```bash
# Create feature branch
git checkout -b feature/new-script

# Commit with conventional format
git commit -m "feat: Add description of changes"

# Push and create PR
git push -u origin feature/new-script
```

### Release Process
1. Update version in script if applicable
2. Create git tag: `git tag v1.x.x`
3. Push tags: `git push --tags`

## Dependencies

Scripts may require:
- `git` - For git-helper.sh
- `mysql`/`mariadb-client` - For mariadb-helper.sh
- `curl` - For API calls
- `jq` - For JSON parsing (optional, prefer native bash where possible)

## File Locations

- Scripts: `/usr/local/bin/` (after installation)
- Config: `$HOME/.config/<script-name>/`
- Backups: User-specified or `./backups/`
