#!/bin/bash

# Dify App Migration Script (English Version)
# Purpose: Export apps from the source environment and import them into the target environment

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case $level in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message"
            ;;
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${timestamp} - $message"
            ;;
        "DEBUG")
            if [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - $message"
            fi
            ;;
    esac
}

# Load environment variables
load_env() {
    local env_file="${1:-.env}"
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Environment config file $env_file does not exist! Please create a .env file based on .env.example."
        exit 1
    fi
    log "INFO" "Loading environment config file: $env_file"
    set -a
    source "$env_file"
    set +a
    local required_vars=(
        "SOURCE_DIFY_URL"
        "SOURCE_BEARER_TOKEN"
        "TARGET_DIFY_URL"
        "TARGET_BEARER_TOKEN"
    )
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log "ERROR" "Required environment variable $var is not set"
            exit 1
        fi
    done
    log "INFO" "Environment variable validation passed"
}

# Create backup directory
create_backup_dir() {
    local backup_dir="${BACKUP_DIR:-./backups}"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    BACKUP_PATH="${backup_dir}/migration_${timestamp}"
    if [[ ! -d "$BACKUP_PATH" ]]; then
        mkdir -p "$BACKUP_PATH"
        log "INFO" "Created backup directory: $BACKUP_PATH"
    fi
}

# Refresh source token
refresh_source_token() {
    if [[ -z "${SOURCE_REFRESH_TOKEN:-}" ]]; then
        log "ERROR" "SOURCE_REFRESH_TOKEN is not set, cannot auto-refresh token"
        return 1
    fi
    log "INFO" "Attempting to auto-refresh source Bearer Token..."
    local refresh_url="${SOURCE_DIFY_URL}/console/api/refresh-token"
    local temp_error=$(mktemp)
    local response=$(curl -s -X POST "$refresh_url" \
        -H "content-type: application/json" \
        -H "user-agent: ${SOURCE_USER_AGENT:-Mozilla/5.0}" \
        --data-raw "{\"refresh_token\":\"${SOURCE_REFRESH_TOKEN}\"}" \
        2>"$temp_error")
    local curl_exit_code=$?
    local error_output=$(cat "$temp_error")
    rm -f "$temp_error"
    if [[ $curl_exit_code -ne 0 ]]; then
        log "ERROR" "curl command failed, exit code: $curl_exit_code"
        log "ERROR" "curl error output: $error_output"
    fi
    local new_token=$(echo "$response" | jq -r 'if (.data | type) == "object" then .data.access_token elif .access_token then .access_token else empty end')
    if [[ -z "$new_token" || "$new_token" == "null" ]]; then
        log "ERROR" "Token refresh failed, response: $response"
        return 1
    fi
    export SOURCE_BEARER_TOKEN="$new_token"
    log "INFO" "Token refreshed successfully, SOURCE_BEARER_TOKEN updated"
    return 0
}

# Refresh target token
refresh_target_token() {
    if [[ -z "${TARGET_REFRESH_TOKEN:-}" ]]; then
        log "ERROR" "TARGET_REFRESH_TOKEN is not set, cannot auto-refresh token"
        return 1
    fi
    log "INFO" "Attempting to auto-refresh target Bearer Token..."
    local refresh_url="${TARGET_DIFY_URL}/console/api/refresh-token"
    local temp_error=$(mktemp)
    local response=$(curl -s -X POST "$refresh_url" \
        -H "content-type: application/json" \
        -H "user-agent: ${TARGET_USER_AGENT:-Mozilla/5.0}" \
        --data-raw "{\"refresh_token\":\"${TARGET_REFRESH_TOKEN}\"}" \
        2>"$temp_error")
    local curl_exit_code=$?
    local error_output=$(cat "$temp_error")
    rm -f "$temp_error"
    if [[ $curl_exit_code -ne 0 ]]; then
        log "ERROR" "curl command failed, exit code: $curl_exit_code"
        log "ERROR" "curl error output: $error_output"
    fi
    local new_token=$(echo "$response" | jq -r 'if (.data | type) == "object" then .data.access_token elif .access_token then .access_token else empty end')
    if [[ -z "$new_token" || "$new_token" == "null" ]]; then
        log "ERROR" "Token refresh failed, response: $response"
        return 1
    fi
    export TARGET_BEARER_TOKEN="$new_token"
    log "INFO" "Token refreshed successfully, TARGET_BEARER_TOKEN updated"
    return 0
}

# get_all_apps with auto-refresh token support
get_all_apps() {
    local url="$1"
    local token="$2"
    local page=1
    local limit=50
    local all_apps=""
    local total=0
    local fetched=0
    local has_more=true
    local retried_refresh=false
    log "DEBUG" "Fetching app list from: $url (auto pagination)"
    log "DEBUG" "Full request URL: ${url}/console/api/apps"
    while $has_more; do
        local req_url="${url}/console/api/apps?page=${page}&limit=${limit}"
        log "DEBUG" "Requesting page ${page}: $req_url"
        local temp_response=$(mktemp)
        local temp_headers=$(mktemp)
        local temp_error=$(mktemp)
        local http_code=$(curl -s -w "%{http_code}" \
            "$req_url" \
            -H "authorization: Bearer ${token}" \
            -H "content-type: application/json" \
            -H "user-agent: ${SOURCE_USER_AGENT:-Mozilla/5.0}" \
            -H "accept: application/json" \
            --connect-timeout 30 \
            --max-time 60 \
            -D "$temp_headers" \
            -o "$temp_response" \
            2>"$temp_error")
        local curl_exit_code=$?
        local response=$(cat "$temp_response")
        local error_output=$(cat "$temp_error")
        rm -f "$temp_response" "$temp_headers" "$temp_error"
        if [[ "$http_code" == "401" && "$retried_refresh" == "false" && -n "${SOURCE_REFRESH_TOKEN:-}" ]]; then
            log "WARN" "Token expired, auto-refreshing and retrying..."
            if refresh_source_token; then
                token="$SOURCE_BEARER_TOKEN"
                retried_refresh=true
                continue
            else
                log "ERROR" "Auto-refresh token failed, cannot continue"
                return 1
            fi
        fi
        if [[ $curl_exit_code -ne 0 || "$http_code" != "200" ]]; then
            log "ERROR" "Pagination request failed: page=$page, http_code=$http_code, curl_exit_code=$curl_exit_code"
            log "ERROR" "Error details: $error_output"
            log "ERROR" "Response: $response"
            return 1
        fi
        if ! echo "$response" | jq empty 2>/dev/null; then
            log "ERROR" "Response is not valid JSON: $response"
            return 1
        fi
        local page_apps=$(echo "$response" | jq -r '.data[] | "\(.id),\(.name)"' 2>/dev/null)
        if [[ -n "$page_apps" ]]; then
            all_apps+="$page_apps\n"
            fetched=$((fetched + $(echo "$page_apps" | wc -l)))
        fi
        has_more=$(echo "$response" | jq -r '.has_more // false')
        total=$(echo "$response" | jq -r '.total // 0')
        log "DEBUG" "Fetched $fetched / $total, has_more: $has_more"
        if [[ "$has_more" != "true" ]]; then
            break
        fi
        page=$((page + 1))
    done
    if [[ -z "$all_apps" ]]; then
        log "WARN" "No apps found"
        echo ""
        return 0
    fi
    local app_count=$(echo -e "$all_apps" | grep -v '^$' | wc -l)
    log "INFO" "$app_count apps fetched (auto pagination)"
    echo -e "$all_apps" | grep -v '^$'
}

# Export a single app
export_app() {
    local app_id="$1"
    local app_name="$2"
    local url="$3"
    local token="$4"
    local include_secret="${5:-false}"
    log "INFO" "Exporting app: $app_name (ID: $app_id)"
    local export_url="${url}/console/api/apps/${app_id}/export?include_secret=${include_secret}"
    local max_retries="${MAX_RETRIES:-3}"
    local retry_count=0
    while [[ $retry_count -lt $max_retries ]]; do
        local temp_response=$(mktemp)
        local temp_headers=$(mktemp)
        local temp_error=$(mktemp)
        local http_code=$(curl -s -w "%{http_code}" \
            "$export_url" \
            -H "authorization: Bearer ${token}" \
            -H "content-type: application/json" \
            -H "user-agent: ${SOURCE_USER_AGENT:-Mozilla/5.0}" \
            -D "$temp_headers" \
            -o "$temp_response" \
            2>"$temp_error")
        local curl_exit_code=$?
        local response=$(cat "$temp_response")
        local error_output=$(cat "$temp_error")
        rm -f "$temp_response" "$temp_headers" "$temp_error"
        if [[ $curl_exit_code -ne 0 ]]; then
            log "WARN" "CURL request failed (attempt $((retry_count + 1))/$max_retries), exit code: $curl_exit_code"
        elif [[ "$http_code" != "200" ]]; then
            log "WARN" "HTTP request failed (attempt $((retry_count + 1))/$max_retries), status code: $http_code"
            case $http_code in
                401)
                    log "ERROR" "Authentication failed: Bearer Token may be invalid or expired"
                    ;;
                403)
                    log "ERROR" "Permission denied: Token does not have export permission for this app"
                    ;;
                404)
                    log "ERROR" "App not found: App ID $app_id may be invalid"
                    ;;
            esac
            if [[ -n "$response" ]]; then
                log "DEBUG" "Error response: $response"
            fi
        elif [[ -n "$response" ]]; then
            local yaml_content=$(echo "$response" | jq -r '.data // empty')
            if [[ -z "$yaml_content" || "$yaml_content" == "null" ]]; then
                log "WARN" "No data field in export content, response: $response"
                echo "$response" > "${BACKUP_PATH}/${app_id}_error_${retry_count}.json"
            elif echo "$yaml_content" | grep -q '^app:'; then
                local safe_name=$(echo "$app_name" | sed 's/[^a-zA-Z0-9._-]/_/g')
                local export_file="${BACKUP_PATH}/${app_id}_${safe_name}.yaml"
                echo "$yaml_content" > "$export_file"
                log "INFO" "App exported: $export_file"
                echo "$export_file"
                return 0
            else
                log "WARN" "data field format incorrect (attempt $((retry_count + 1))/$max_retries)"
                log "DEBUG" "data content: ${yaml_content:0:200}..."
                echo "$response" > "${BACKUP_PATH}/${app_id}_error_${retry_count}.json"
            fi
        else
            log "WARN" "Empty response (attempt $((retry_count + 1))/$max_retries)"
        fi
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            sleep 2
        fi
    done
    log "ERROR" "App export failed: $app_name (ID: $app_id) - retried $max_retries times"
    return 1
}

# Import a single app, with target auto-refresh token support
import_app() {
    local yaml_file="$1"
    local url="$2"
    local token="$3"
    if [[ ! -f "$yaml_file" ]]; then
        log "ERROR" "YAML file does not exist: $yaml_file"
        return 1
    fi
    local first_line=$(head -n 1 "$yaml_file" | tr -d '\r\n')
    if [[ "$first_line" != "app:" ]]; then
        log "ERROR" "YAML file format error: $yaml_file first line is not 'app:', please check export logic or fix manually."
        return 1
    fi
    local app_name=$(basename "$yaml_file" .yaml)
    log "INFO" "Importing app: $app_name"
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "INFO" "[Dry Run] Skipping actual import: $yaml_file"
        return 0
    fi
    local yaml_content=$(awk '{printf "%s\\n", $0}' "$yaml_file" | sed 's/"/\\"/g')
    local max_retries="${MAX_RETRIES:-3}"
    local retry_count=0
    local retried_refresh=false
    while [[ $retry_count -lt $max_retries ]]; do
        local temp_response=$(mktemp)
        local temp_headers=$(mktemp)
        local http_code=$(curl -s -w "%{http_code}" \
            "${url}/console/api/apps/imports" \
            -H "authorization: Bearer ${token}" \
            -H "content-type: application/json" \
            -H "user-agent: ${TARGET_USER_AGENT:-Mozilla/5.0}" \
            -D "$temp_headers" \
            -o "$temp_response" \
            --data-raw "{\"mode\":\"yaml-content\",\"yaml_content\":\"${yaml_content}\"}")
        local curl_exit_code=$?
        local response=$(cat "$temp_response")
        rm -f "$temp_response" "$temp_headers"
        if [[ "$http_code" == "401" && "$retried_refresh" == "false" && -n "${TARGET_REFRESH_TOKEN:-}" ]]; then
            log "WARN" "Target token expired, auto-refreshing and retrying..."
            if refresh_target_token; then
                token="$TARGET_BEARER_TOKEN"
                retried_refresh=true
                continue
            else
                log "ERROR" "Auto-refresh target token failed, cannot continue"
                return 1
            fi
        fi
        if [[ $curl_exit_code -ne 0 ]]; then
            log "WARN" "CURL request failed (attempt $((retry_count + 1))/$max_retries), exit code: $curl_exit_code"
        elif [[ "$http_code" != "200" ]]; then
            log "WARN" "HTTP request failed (attempt $((retry_count + 1))/$max_retries), status code: $http_code"
            case $http_code in
                401)
                    log "ERROR" "Authentication failed: Bearer Token may be invalid or expired"
                    ;;
                403)
                    log "ERROR" "Permission denied: Token does not have import permission"
                    ;;
                400)
                    log "ERROR" "Request format error: App DSL format may be incorrect"
                    ;;
            esac
            if [[ -n "$response" ]]; then
                log "DEBUG" "Error response: $response"
                echo "$response" > "${BACKUP_PATH}/import_error_${app_name}_${retry_count}.json"
            fi
        else
            if echo "$response" | jq -e '.code // empty' >/dev/null 2>&1; then
                local error_code=$(echo "$response" | jq -r '.code // empty')
                local error_message=$(echo "$response" | jq -r '.message // empty')
                if [[ "$error_code" != "null" && "$error_code" != "" ]]; then
                    log "WARN" "Import failed (attempt $((retry_count + 1))/$max_retries) - Error code: $error_code"
                    log "WARN" "Error message: $error_message"
                    echo "$response" > "${BACKUP_PATH}/import_error_${app_name}_${retry_count}.json"
                else
                    log "INFO" "App imported: $app_name"
                    echo "$response" > "${BACKUP_PATH}/import_success_${app_name}.json"
                    return 0
                fi
            else
                log "INFO" "App imported: $app_name"
                echo "$response" > "${BACKUP_PATH}/import_success_${app_name}.json"
                return 0
            fi
        fi
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            sleep 3
        fi
    done
    log "ERROR" "App import failed: $app_name - retried $max_retries times"
    return 1
}

# Show help
show_help() {
    cat << EOF
Dify App Migration Script (English Version)

Usage: $0 [options] [env file]

Options:
    -h, --help          Show help
    -c, --config        Specify environment config file (default: .env)
    -a, --apps          Specify app IDs to migrate, comma-separated (overrides env variable)
    -d, --dry-run       Dry run mode, test only, no actual migration
    -v, --verbose       Verbose output (DEBUG mode)
    --export-only       Only export, do not import
    --import-only       Only import YAML files from specified directory

Examples:
    $0                                  # Full migration with default .env
    $0 -c production.env               # Use specified config file
    $0 -a "app-id-1,app-id-2"         # Only migrate specified apps
    $0 -d                              # Dry run mode
    $0 --export-only                   # Only export apps
    $0 --import-only ./exported_apps   # Only import apps from specified directory

Environment config:
    Please refer to .env.example to create your .env config file
EOF
}

# Main function
main() {
    local config_file=".env"
    local export_only=false
    local import_only=false
    local import_dir=""
    local specified_apps=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--config)
                config_file="$2"
                shift 2
                ;;
            -a|--apps)
                specified_apps="$2"
                shift 2
                ;;
            -d|--dry-run)
                export DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                export LOG_LEVEL=DEBUG
                shift
                ;;
            --export-only)
                export_only=true
                shift
                ;;
            --import-only)
                import_only=true
                if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
                    import_dir="$2"
                    shift 2
                else
                    import_dir="./backups"
                    shift
                fi
                ;;
            *)
                if [[ -f "$1" ]]; then
                    config_file="$1"
                else
                    log "ERROR" "Unknown argument: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    for cmd in curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR" "Missing required command: $cmd"
            exit 1
        fi
    done
    load_env "$config_file"
    create_backup_dir
    local app_ids_to_migrate="${specified_apps:-${APP_IDS_TO_MIGRATE:-}}"
    if [[ "$import_only" == "true" ]]; then
        log "INFO" "Import mode, from directory: $import_dir"
        if [[ ! -d "$import_dir" ]]; then
            log "ERROR" "Import directory does not exist: $import_dir"
            exit 1
        fi
        local success_count=0
        local total_count=0
        for yaml_file in "$import_dir"/*.yaml; do
            if [[ -f "$yaml_file" ]]; then
                total_count=$((total_count + 1))
                if import_app "$yaml_file" "$TARGET_DIFY_URL" "$TARGET_BEARER_TOKEN"; then
                    success_count=$((success_count + 1))
                fi
            fi
        done
        log "INFO" "Import finished: $success_count/$total_count apps imported successfully"
        exit 0
    fi
    log "INFO" "Fetching app list from source environment..."
    local apps_list
    if [[ -n "$app_ids_to_migrate" ]]; then
        log "INFO" "Using specified app ID list: $app_ids_to_migrate"
        apps_list=$(echo "$app_ids_to_migrate" | tr ',' '\n' | while read -r app_id; do
            echo "${app_id},SpecifiedApp_${app_id}"
        done)
    else
        apps_list=$(get_all_apps "$SOURCE_DIFY_URL" "$SOURCE_BEARER_TOKEN")
        if [[ $? -ne 0 ]] || [[ -z "$apps_list" ]]; then
            log "ERROR" "Failed to fetch app list"
            exit 1
        fi
    fi
    local total_apps=$(echo "$apps_list" | wc -l)
    log "INFO" "$total_apps apps to process"
    local exported_files=()
    local export_success_count=0
    echo "$apps_list" | while IFS=',' read -r app_id app_name; do
        if [[ -n "$app_id" ]]; then
            if export_file=$(export_app "$app_id" "$app_name" "$SOURCE_DIFY_URL" "$SOURCE_BEARER_TOKEN" "${INCLUDE_SECRET:-false}"); then
                export_success_count=$((export_success_count + 1))
                exported_files+=("$export_file")
                echo "$export_file" >> "${BACKUP_PATH}/exported_files.list"
            fi
        fi
    done
    if [[ "$export_only" == "true" ]]; then
        log "INFO" "Export mode finished, exported files in: $BACKUP_PATH"
        exit 0
    fi
    if [[ -f "${BACKUP_PATH}/exported_files.list" ]]; then
        log "INFO" "Starting import to target environment..."
        local import_success_count=0
        local import_total=0
        while read -r yaml_file; do
            if [[ -f "$yaml_file" ]]; then
                import_total=$((import_total + 1))
                if import_app "$yaml_file" "$TARGET_DIFY_URL" "$TARGET_BEARER_TOKEN"; then
                    import_success_count=$((import_success_count + 1))
                fi
            fi
        done < "${BACKUP_PATH}/exported_files.list"
        log "INFO" "Migration complete!"
        log "INFO" "Exported successfully: $export_success_count apps"
        log "INFO" "Imported successfully: $import_success_count/$import_total apps"
        log "INFO" "Backup directory: $BACKUP_PATH"
    else
        log "WARN" "No apps exported successfully, skipping import step"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 