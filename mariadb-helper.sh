#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_DIR="$HOME/.config/mariadb-helper"
CONFIG_FILE="$CONFIG_DIR/config"
SERVERS_FILE="$CONFIG_DIR/servers"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_debug() { echo -e "${CYAN}[DEBUG]${NC} $1"; }

load_config() {
    mkdir -p "$CONFIG_DIR"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    if [ -f "$SERVERS_FILE" ]; then
        source "$SERVERS_FILE"
    fi
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
MYSQL_PWD="$MYSQL_PWD"
MYSQL_USER="$MYSQL_USER"
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
EOF
    chmod 600 "$CONFIG_FILE"
}

save_servers() {
    mkdir -p "$CONFIG_DIR"
    cat > "$SERVERS_FILE" << EOF
# Server configurations
# Format: servers[<alias>]="host:port:user:password"
declare -A servers
EOF
    for alias in "${!servers[@]}"; do
        echo "servers[$alias]=\"${servers[$alias]}\"" >> "$SERVERS_FILE"
    done
    chmod 600 "$SERVERS_FILE"
}

set_server() {
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    
    MYSQL_HOST="$host"
    MYSQL_PORT="${port:-3306}"
    MYSQL_USER="$user"
    MYSQL_PWD="$password"
}

mysql_exec() {
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" -N -e "$1" 2>/dev/null
}

mysql_exec_raw() {
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" "$1" 2>/dev/null
}

mysql_query() {
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" -N -e "$1" 2>/dev/null
}

check_connection() {
    if mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" -e "SELECT 1;" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

wait_for_connection() {
    local max_attempts="${1:-10}"
    local delay="${2:-2}"
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if check_connection; then
            log_success "Connected to $MYSQL_HOST:$MYSQL_PORT"
            return 0
        fi
        log_info "Attempt $attempt/$max_attempts - Waiting ${delay}s..."
        sleep $delay
        attempt=$((attempt + 1))
    done
    
    log_error "Cannot connect to $MYSQL_HOST:$MYSQL_PORT"
    return 1
}

cmd_status() {
    load_config
    
    echo -e "${BLUE}MariaDB/MySQL Status${NC}"
    echo "================================"
    echo ""
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        echo ""
        echo "Current configuration:"
        echo "  Host: ${MYSQL_HOST:-localhost}"
        echo "  Port: ${MYSQL_PORT:-3306}"
        echo "  User: ${MYSQL_USER:-root}"
        return 1
    fi
    
    local version=$(mysql_query "SELECT VERSION();" | head -1)
    echo -e "${GREEN}Connected${NC} to MySQL $version"
    echo ""
    echo "Server Info:"
    echo "  Host: $MYSQL_HOST"
    echo "  Port: $MYSQL_PORT"
    echo "  User: $MYSQL_USER"
    echo ""
    
    local db_count=$(mysql_query "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema', 'performance_schema');")
    local user_count=$(mysql_query "SELECT COUNT(*) FROM mysql.user WHERE user NOT IN ('root', 'mysql.sys', 'mysql.session', 'mysql.infoschema');")
    echo "Databases: $db_count"
    echo "Users: $user_count"
}

cmd_user_list() {
    load_config
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    echo -e "${BLUE}MySQL Users${NC}"
    echo "================================"
    echo ""
    
    mysql_query "SELECT user, host FROM mysql.user WHERE user NOT IN ('root', 'mysql.sys', 'mysql.session', 'mysql.infoschema') ORDER BY user, host;" | while read user host; do
        echo -e "  ${GREEN}$user${NC}@$host"
    done
}

cmd_user_create() {
    load_config
    local username="$1"
    local password="$2"
    local host="${3:-%}"
    local privileges="${4:-ALL PRIVILEGES}"
    
    if [ -z "$username" ] || [ -z "$password" ]; then
        log_error "Usage: mariadb-helper user-create <username> <password> [--host=%] [--privileges=ALL]"
        exit 1
    fi
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    log_info "Creating user '$username'@'$host'..."
    
    mysql_exec "CREATE USER IF NOT EXISTS '$username'@'$host' IDENTIFIED BY '$password';"
    mysql_exec "GRANT $privileges ON *.* TO '$username'@'$host';"
    mysql_exec "FLUSH PRIVILEGES;"
    
    log_success "User '$username'@'$host' created with $privileges"
}

cmd_user_modify() {
    load_config
    local username="$1"
    local password="$2"
    local host="${3:-%}"
    local privileges="${4:-}"
    
    if [ -z "$username" ] || [ -z "$password" ]; then
        log_error "Usage: mariadb-helper user-modify <username> <password> [--host=%] [--privileges=ALL]"
        exit 1
    fi
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    log_info "Modifying user '$username'@'$host'..."
    
    mysql_exec "SET PASSWORD FOR '$username'@'$host' = PASSWORD('$password');"
    
    if [ -n "$privileges" ]; then
        mysql_exec "REVOKE ALL PRIVILEGES ON *.* FROM '$username'@'$host';"
        mysql_exec "GRANT $privileges ON *.* TO '$username'@'$host';"
    fi
    
    mysql_exec "FLUSH PRIVILEGES;"
    
    log_success "User '$username'@'$host' modified"
}

cmd_user_delete() {
    load_config
    local username="$1"
    local host="${2:-%}"
    
    if [ -z "$username" ]; then
        log_error "Usage: mariadb-helper user-delete <username> [--host=%]"
        exit 1
    fi
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    log_info "Deleting user '$username'@'$host'..."
    
    mysql_exec "DROP USER IF EXISTS '$username'@'$host';"
    mysql_exec "FLUSH PRIVILEGES;"
    
    log_success "User '$username'@'$host' deleted"
}

cmd_show_privileges() {
    load_config
    local username="$1"
    local host="${2:-%}"
    
    if [ -z "$username" ]; then
        log_error "Usage: mariadb-helper show-privileges <username> [--host=%]"
        exit 1
    fi
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    echo -e "${BLUE}Privileges for $username@$host${NC}"
    echo "================================"
    echo ""
    
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" -N -e "SHOW GRANTS FOR '$username'@'$host';" 2>/dev/null | while read grant_line; do
        echo "  $grant_line"
    done
}

cmd_grant() {
    load_config
    local username="$1"
    local dbname="$2"
    local privileges="${3:-ALL PRIVILEGES}"
    local host="${4:-%}"
    
    if [ -z "$username" ] || [ -z "$dbname" ]; then
        log_error "Usage: mariadb-helper grant <username> <dbname> <privileges> [--host=%]"
        exit 1
    fi
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    log_info "Granting $privileges on $dbname to $username@$host..."
    
    mysql_exec "GRANT $privileges ON \`$dbname\`.* TO '$username'@'$host';"
    mysql_exec "FLUSH PRIVILEGES;"
    
    log_success "Privileges granted"
}

cmd_revoke() {
    load_config
    local username="$1"
    local dbname="$2"
    local privileges="${3:-ALL PRIVILEGES}"
    local host="${4:-%}"
    
    if [ -z "$username" ] || [ -z "$dbname" ]; then
        log_error "Usage: mariadb-helper revoke <username> <dbname> <privileges> [--host=%]"
        exit 1
    fi
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    log_info "Revoking $privileges on $dbname from $username@$host..."
    
    mysql_exec "REVOKE $privileges ON \`$dbname\`.* FROM '$username'@'$host';"
    mysql_exec "FLUSH PRIVILEGES;"
    
    log_success "Privileges revoked"
}

cmd_db_list() {
    load_config
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    echo -e "${BLUE}Databases${NC}"
    echo "================================"
    echo ""
    
    mysql_query "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema', 'performance_schema', 'mysql') ORDER BY schema_name;" | while read dbname; do
        local size=$(mysql_query "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) FROM information_schema.tables WHERE table_schema='$dbname';")
        echo -e "  ${GREEN}$dbname${NC} (${size:-0} MB)"
    done
}

cmd_db_create() {
    load_config
    local dbname="$1"
    local charset="${2:-utf8mb4}"
    local collate="${3:-utf8mb4_unicode_ci}"
    
    if [ -z "$dbname" ]; then
        log_error "Usage: mariadb-helper db-create <dbname> [--charset=utf8mb4] [--collate=utf8mb4_unicode_ci]"
        exit 1
    fi
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    log_info "Creating database '$dbname'..."
    
    mysql_exec "CREATE DATABASE IF NOT EXISTS \`$dbname\` CHARACTER SET $charset COLLATE $collate;"
    
    log_success "Database '$dbname' created with charset $charset"
}

cmd_db_delete() {
    load_config
    local dbname="$1"
    local force="${2:-}"
    
    if [ -z "$dbname" ]; then
        log_error "Usage: mariadb-helper db-delete <dbname> [--force]"
        exit 1
    fi
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    if [ "$force" != "--force" ]; then
        log_warn "This will delete ALL data in '$dbname'. Use --force to confirm."
        read -p "Are you sure? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Cancelled"
            exit 0
        fi
    fi
    
    log_info "Deleting database '$dbname'..."
    
    mysql_exec "DROP DATABASE IF EXISTS \`$dbname\`;"
    
    log_success "Database '$dbname' deleted"
}

cmd_db_list_tables() {
    load_config
    local dbname="$1"
    
    if [ -z "$dbname" ]; then
        log_error "Usage: mariadb-helper db-list-tables <dbname>"
        exit 1
    fi
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    echo -e "${BLUE}Tables in $dbname${NC}"
    echo "================================"
    echo ""
    
    mysql_query "SELECT table_name FROM information_schema.tables WHERE table_schema='$dbname' ORDER BY table_name;" | while read table; do
        local rows=$(mysql_query "SELECT COUNT(*) FROM \`$dbname\`.\`$table\`;")
        echo -e "  ${GREEN}$table${NC} ($rows rows)"
    done
}

cmd_backup() {
    load_config
    local dbname="$1"
    local output_dir="${2:-./backups}"
    local compress="${3:-true}"
    
    if [ -z "$dbname" ]; then
        log_error "Usage: mariadb-helper backup <dbname> [--output=/path] [--compress|--no-compress]"
        exit 1
    fi
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    mkdir -p "$output_dir"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local filename="${dbname}_${timestamp}.sql"
    local filepath="$output_dir/$filename"
    
    log_info "Backing up database '$dbname'..."
    
    if [ "$compress" = "--compress" ] || [ "$compress" = "true" ]; then
        mysqldump -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" --single-transaction --routines --triggers "$dbname" | gzip > "$filepath.gz"
        log_success "Backup created: ${filepath}.gz"
    else
        mysqldump -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" --single-transaction --routines --triggers "$dbname" > "$filepath"
        log_success "Backup created: $filepath"
    fi
}

cmd_backup_all() {
    load_config
    local output_dir="${1:-./backups}"
    local compress="${2:-true}"
    local exclude="${3:-}"
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    mkdir -p "$output_dir"
    
    local dbs=$(mysql_query "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema', 'performance_schema', 'mysql') ORDER BY schema_name;")
    
    log_info "Backing up all databases..."
    echo ""
    
    for dbname in $dbs; do
        local skip=false
        if [ -n "$exclude" ]; then
            for ex in $(echo "$exclude" | tr ',' ' '); do
                if [ "$dbname" = "$ex" ]; then
                    skip=true
                    break
                fi
            done
        fi
        
        if [ "$skip" = "true" ]; then
            log_warn "Skipping $dbname"
            continue
        fi
        
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local filename="${dbname}_${timestamp}.sql"
        local filepath="$output_dir/$filename"
        
        if [ "$compress" = "--compress" ] || [ "$compress" = "true" ]; then
            mysqldump -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" --single-transaction --routines --triggers "$dbname" | gzip > "$filepath.gz"
            log_success "Backed up: ${dbname}.sql.gz"
        else
            mysqldump -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" --single-transaction --routines --triggers "$dbname" > "$filepath"
            log_success "Backed up: $filename"
        fi
    done
    
    echo ""
    log_success "All databases backed up to $output_dir"
}

cmd_restore() {
    load_config
    local dbname="$1"
    local backup_file="$2"
    
    if [ -z "$dbname" ] || [ -z "$backup_file" ]; then
        log_error "Usage: mariadb-helper restore <dbname> <backup_file>"
        exit 1
    fi
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    log_info "Creating database '$dbname' if it doesn't exist..."
    mysql_exec "CREATE DATABASE IF NOT EXISTS \`$dbname\`;"
    
    log_info "Restoring database '$dbname' from $backup_file..."
    
    if [[ "$backup_file" =~ \.gz$ ]]; then
        gunzip -c "$backup_file" | mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" "$dbname"
    else
        mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PWD" "$dbname" < "$backup_file"
    fi
    
    log_success "Database '$dbname' restored from $backup_file"
}

cmd_query() {
    load_config
    local query="$1"
    
    if [ -z "$query" ]; then
        log_error "Usage: mariadb-helper query \"SELECT * FROM table\""
        exit 1
    fi
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    mysql_query "$query"
}

cmd_query_json() {
    load_config
    local query="$1"
    
    if [ -z "$query" ]; then
        log_error "Usage: mariadb-helper query-json \"SELECT * FROM table\""
        exit 1
    fi
    
    if ! check_connection; then
        log_error "Cannot connect to server"
        exit 1
    fi
    
    local result=$(mysql_query "$query")
    local headers=$(echo "$result" | head -1 | tr '\t' ',')
    local data=$(echo "$result" | tail -n +2)
    
    echo "{"
    echo "  \"headers\": [\"$(echo "$headers" | tr ',' '\", \"')\"],"
    echo "  \"data\": ["
    echo "$data" | while IFS=$'\t' read -r line; do
        if [ -n "$line" ]; then
            echo "    [\"$(echo "$line" | tr '\t' '\", \"')\"],"
        fi
    done | sed '$ s/,$//'
    echo "  ]"
    echo "}"
}

cmd_server_add() {
    load_config
    local alias="$1"
    local host="$2"
    local port="${3:-3306}"
    local user="$4"
    local password="$5"
    
    if [ -z "$alias" ] || [ -z "$host" ] || [ -z "$user" ] || [ -z "$password" ]; then
        log_error "Usage: mariadb-helper server-add <alias> <host> <port> <user> <password>"
        exit 1
    fi
    
    servers[$alias]="$host:$port:$user:$password"
    save_servers
    
    log_success "Server '$alias' added: $host:$port"
}

cmd_server_list() {
    load_config
    
    echo -e "${BLUE}Configured Servers${NC}"
    echo "================================"
    echo ""
    
    if [ ${#servers[@]} -eq 0 ]; then
        log_warn "No servers configured. Use: mariadb-helper server-add <alias> <host> <port> <user> <password>"
        return 0
    fi
    
    for alias in "${!servers[@]}"; do
        local info="${servers[$alias]}"
        local host=$(echo "$info" | cut -d':' -f1)
        local port=$(echo "$info" | cut -d':' -f2)
        local user=$(echo "$info" | cut -d':' -f3)
        echo -e "  ${GREEN}$alias${NC} -> $host:$port ($user)"
    done
}

cmd_server_use() {
    load_config
    local alias="$1"
    
    if [ -z "$alias" ]; then
        log_error "Usage: mariadb-helper server-use <alias>"
        exit 1
    fi
    
    if [ -z "${servers[$alias]}" ]; then
        log_error "Server '$alias' not found. Use mariadb-helper server-list to see configured servers."
        exit 1
    fi
    
    local info="${servers[$alias]}"
    local host=$(echo "$info" | cut -d':' -f1)
    local port=$(echo "$info" | cut -d':' -f2)
    local user=$(echo "$info" | cut -d':' -f3)
    local password=$(echo "$info" | cut -d':' -f4-)
    
    set_server "$host" "$port" "$user" "$password"
    MYSQL_HOST="$host"
    MYSQL_PORT="$port"
    MYSQL_USER="$user"
    MYSQL_PWD="$password"
    
    if check_connection; then
        log_success "Switched to server '$alias' ($host:$port)"
    else
        log_error "Cannot connect to server '$alias'"
        exit 1
    fi
}

cmd_server_delete() {
    load_config
    local alias="$1"
    
    if [ -z "$alias" ]; then
        log_error "Usage: mariadb-helper server-delete <alias>"
        exit 1
    fi
    
    if [ -z "${servers[$alias]}" ]; then
        log_error "Server '$alias' not found"
        exit 1
    fi
    
    unset servers[$alias]
    save_servers
    
    log_success "Server '$alias' deleted"
}

cmd_check_connection() {
    load_config
    
    echo -e "${BLUE}Testing Connection${NC}"
    echo "================================"
    echo ""
    echo "Host: ${MYSQL_HOST:-localhost}"
    echo "Port: ${MYSQL_PORT:-3306}"
    echo "User: ${MYSQL_USER:-root}"
    echo ""
    
    if wait_for_connection 5 2; then
        log_success "Connection successful"
    else
        log_error "Connection failed"
        exit 1
    fi
}

cmd_config() {
    load_config
    local password="$1"
    local user="$2"
    local host="$3"
    local port="$4"
    
    if [ -n "$password" ]; then
        MYSQL_PWD="$password"
        log_info "Password configured"
    fi
    
    if [ -n "$user" ]; then
        MYSQL_USER="$user"
        log_info "User configured: $user"
    fi
    
    if [ -n "$host" ]; then
        MYSQL_HOST="$host"
        log_info "Host configured: $host"
    fi
    
    if [ -n "$port" ]; then
        MYSQL_PORT="$port"
        log_info "Port configured: $port"
    fi
    
    if [ -z "$password" ] && [ -z "$user" ] && [ -z "$host" ] && [ -z "$port" ]; then
        echo "Current configuration:"
        echo "  Host: ${MYSQL_HOST:-localhost}"
        echo "  Port: ${MYSQL_PORT:-3306}"
        echo "  User: ${MYSQL_USER:-root}"
        echo "  Password: ${MYSQL_PWD:0:3}***"
        echo ""
        echo "Servers configured: ${#servers[@]}"
        for alias in "${!servers[@]}"; do
            echo "  - $alias"
        done
    fi
    
    save_config
    log_success "Configuration saved"
}

cmd_help() {
    echo "mariadb-helper - MariaDB/MySQL management script"
    echo ""
    echo "Usage: mariadb-helper <command> [options]"
    echo ""
    echo "Server Commands:"
    echo "  status              Show server status and info"
    echo "  check-connection    Test connection to server"
    echo "  server-add <alias> <host> <port> <user> <password>  Add server"
    echo "  server-list         List configured servers"
    echo "  server-use <alias>  Switch to configured server"
    echo "  server-delete <alias>  Remove configured server"
    echo ""
    echo "User Commands:"
    echo "  user-list                           List all users"
    echo "  user-create <user> <pass> [--host] [--privs]  Create user"
    echo "  user-modify <user> <pass> [--host] [--privs]  Modify user"
    echo "  user-delete <user> [--host]         Delete user"
    echo "  show-privileges <user> [--host]     Show user privileges"
    echo "  grant <user> <db> <privs> [--host]  Grant privileges"
    echo "  revoke <user> <db> <privs> [--host]  Revoke privileges"
    echo ""
    echo "Database Commands:"
    echo "  db-list                List all databases"
    echo "  db-create <name> [--charset] [--collate]  Create database"
    echo "  db-delete <name> [--force]  Delete database"
    echo "  db-list-tables <name>  List tables in database"
    echo ""
    echo "Backup Commands:"
    echo "  backup <db> [--output=/path] [--compress]  Backup database"
    echo "  backup-all [--output=/path] [--compress] [--exclude=db1,db2]  Backup all"
    echo "  restore <db> <file>  Restore database from backup"
    echo ""
    echo "Query Commands:"
    echo "  query \"SQL\"           Execute query and show results"
    echo "  query-json \"SQL\"      Execute query and show JSON"
    echo ""
    echo "Configuration:"
    echo "  config [pass] [user] [host] [port]  Configure defaults"
    echo "  help                       Show this help"
    echo ""
    echo "Examples:"
    echo "  mariadb-helper config \"mypassword\" \"root\""
    echo "  mariadb-helper user-create myuser mypass --host=% --privs=ALL"
    echo "  mariadb-helper db-create myapp --charset=utf8mb4"
    echo "  mariadb-helper backup myapp --compress"
    echo "  mariadb-helper backup-all --exclude=test_db"
    echo "  mariadb-helper restore myapp backups/myapp_2024.sql.gz"
    echo "  mariadb-helper server-add prod db.example.com 3306 admin \"pass\""
    echo "  mariadb-helper query \"SELECT COUNT(*) FROM users\""
}

main() {
    load_config
    
    local command="${1:-}"
    shift 2>/dev/null || true
    
    case "$command" in
        status)
            cmd_status
            ;;
        check-connection)
            cmd_check_connection
            ;;
        server-add)
            cmd_server_add "$@"
            ;;
        server-list)
            cmd_server_list
            ;;
        server-use)
            cmd_server_use "$@"
            ;;
        server-delete)
            cmd_server_delete "$@"
            ;;
        user-list)
            cmd_user_list
            ;;
        user-create)
            cmd_user_create "$@"
            ;;
        user-modify)
            cmd_user_modify "$@"
            ;;
        user-delete)
            cmd_user_delete "$@"
            ;;
        show-privileges)
            cmd_show_privileges "$@"
            ;;
        grant)
            cmd_grant "$@"
            ;;
        revoke)
            cmd_revoke "$@"
            ;;
        db-list)
            cmd_db_list
            ;;
        db-create)
            cmd_db_create "$@"
            ;;
        db-delete)
            cmd_db_delete "$@"
            ;;
        db-list-tables)
            cmd_db_list_tables "$@"
            ;;
        backup)
            cmd_backup "$@"
            ;;
        backup-all)
            cmd_backup_all "$@"
            ;;
        restore)
            cmd_restore "$@"
            ;;
        query)
            cmd_query "$@"
            ;;
        query-json)
            cmd_query_json "$@"
            ;;
        config)
            cmd_config "$@"
            ;;
        help|--help|-h)
            cmd_help
            ;;
        "")
            cmd_help
            ;;
        *)
            log_error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
