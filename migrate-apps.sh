#!/bin/bash

# Dify 应用迁移脚本
# 作用：从源环境导出应用并导入到目标环境

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
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

# 加载环境变量
load_env() {
    local env_file="${1:-.env}"
    
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "环境配置文件 $env_file 不存在！请参考 .env.example 创建 .env 文件"
        exit 1
    fi
    
    log "INFO" "加载环境配置文件: $env_file"
    
    # 导出环境变量
    set -a
    source "$env_file"
    set +a
    
    # 验证必要的环境变量
    local required_vars=(
        "SOURCE_DIFY_URL"
        "SOURCE_BEARER_TOKEN"
        "TARGET_DIFY_URL"
        "TARGET_BEARER_TOKEN"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log "ERROR" "必需的环境变量 $var 未设置"
            exit 1
        fi
    done
    
    log "INFO" "环境变量验证通过"
}

# 创建备份目录
create_backup_dir() {
    local backup_dir="${BACKUP_DIR:-./backups}"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    
    BACKUP_PATH="${backup_dir}/migration_${timestamp}"
    
    if [[ ! -d "$BACKUP_PATH" ]]; then
        mkdir -p "$BACKUP_PATH"
        log "INFO" "创建备份目录: $BACKUP_PATH"
    fi
}

# 刷新源环境token
refresh_source_token() {
    if [[ -z "${SOURCE_REFRESH_TOKEN:-}" ]]; then
        log "ERROR" "未配置SOURCE_REFRESH_TOKEN，无法自动刷新token"
        return 1
    fi
    log "INFO" "尝试自动刷新源环境Bearer Token..."
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
        log "ERROR" "curl命令失败，exit code: $curl_exit_code"
        log "ERROR" "curl错误输出: $error_output"
    fi
    # 兼容data为object或string
    local new_token=$(echo "$response" | jq -r 'if (.data | type) == "object" then .data.access_token elif .access_token then .access_token else empty end')
    if [[ -z "$new_token" || "$new_token" == "null" ]]; then
        log "ERROR" "刷新token失败，响应: $response"
        return 1
    fi
    export SOURCE_BEARER_TOKEN="$new_token"
    log "INFO" "刷新token成功，已自动更新SOURCE_BEARER_TOKEN"
    return 0
}

# 刷新目标环境token
refresh_target_token() {
    if [[ -z "${TARGET_REFRESH_TOKEN:-}" ]]; then
        log "ERROR" "未配置TARGET_REFRESH_TOKEN，无法自动刷新token"
        return 1
    fi
    log "INFO" "尝试自动刷新目标环境Bearer Token..."
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
        log "ERROR" "curl命令失败，exit code: $curl_exit_code"
        log "ERROR" "curl错误输出: $error_output"
    fi
    # 兼容data为object或string
    local new_token=$(echo "$response" | jq -r 'if (.data | type) == "object" then .data.access_token elif .access_token then .access_token else empty end')
    if [[ -z "$new_token" || "$new_token" == "null" ]]; then
        log "ERROR" "刷新token失败，响应: $response"
        return 1
    fi
    export TARGET_BEARER_TOKEN="$new_token"
    log "INFO" "刷新token成功，已自动更新TARGET_BEARER_TOKEN"
    return 0
}

# get_all_apps 支持自动刷新token
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

    log "DEBUG" "获取应用列表从: $url (自动分页)"
    log "DEBUG" "完整请求URL: ${url}/console/api/apps"

    while $has_more; do
        local req_url="${url}/console/api/apps?page=${page}&limit=${limit}"
        log "DEBUG" "请求第${page}页: $req_url"

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

        # 401自动刷新token并重试一次
        if [[ "$http_code" == "401" && "$retried_refresh" == "false" && -n "${SOURCE_REFRESH_TOKEN:-}" ]]; then
            log "WARN" "检测到Token过期，自动刷新后重试..."
            if refresh_source_token; then
                token="$SOURCE_BEARER_TOKEN"
                retried_refresh=true
                continue
            else
                log "ERROR" "自动刷新token失败，无法继续"
                return 1
            fi
        fi

        if [[ $curl_exit_code -ne 0 || "$http_code" != "200" ]]; then
            log "ERROR" "分页请求失败: page=$page, http_code=$http_code, curl_exit_code=$curl_exit_code"
            log "ERROR" "错误详情: $error_output"
            log "ERROR" "响应内容: $response"
            return 1
        fi

        if ! echo "$response" | jq empty 2>/dev/null; then
            log "ERROR" "响应不是有效的JSON格式: $response"
            return 1
        fi

        local page_apps=$(echo "$response" | jq -r '.data[] | "\(.id),\(.name)"' 2>/dev/null)
        if [[ -n "$page_apps" ]]; then
            all_apps+="$page_apps\n"
            fetched=$((fetched + $(echo "$page_apps" | wc -l)))
        fi

        has_more=$(echo "$response" | jq -r '.has_more // false')
        total=$(echo "$response" | jq -r '.total // 0')
        log "DEBUG" "已获取 $fetched / $total, has_more: $has_more"

        if [[ "$has_more" != "true" ]]; then
            break
        fi
        page=$((page + 1))
    done

    if [[ -z "$all_apps" ]]; then
        log "WARN" "没有找到任何应用"
        echo ""
        return 0
    fi
    local app_count=$(echo -e "$all_apps" | grep -v '^$' | wc -l)
    log "INFO" "成功获取到 $app_count 个应用（自动分页）"
    echo -e "$all_apps" | grep -v '^$'
}

# 导出单个应用
export_app() {
    local app_id="$1"
    local app_name="$2"
    local url="$3"
    local token="$4"
    local include_secret="${5:-false}"
    
    log "INFO" "导出应用: $app_name (ID: $app_id)"
    
    local export_url="${url}/console/api/apps/${app_id}/export?include_secret=${include_secret}"
    
    # 重试机制
    local max_retries="${MAX_RETRIES:-3}"
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        # 使用临时文件保存响应
        local temp_response=$(mktemp)
        local temp_headers=$(mktemp)
        local temp_error=$(mktemp)
        
        # 执行curl请求并保存状态码
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
        
        # 清理临时文件
        rm -f "$temp_response" "$temp_headers" "$temp_error"
        
        if [[ $curl_exit_code -ne 0 ]]; then
            log "WARN" "CURL请求失败 (尝试 $((retry_count + 1))/$max_retries)，退出码: $curl_exit_code"
        elif [[ "$http_code" != "200" ]]; then
            log "WARN" "HTTP请求失败 (尝试 $((retry_count + 1))/$max_retries)，状态码: $http_code"
            case $http_code in
                401)
                    log "ERROR" "认证失败: Bearer Token可能无效或已过期"
                    ;;
                403)
                    log "ERROR" "权限不足: 当前Token没有导出此应用的权限"
                    ;;
                404)
                    log "ERROR" "应用不存在: 应用ID $app_id 可能无效"
                    ;;
            esac
            if [[ -n "$response" ]]; then
                log "DEBUG" "错误响应: $response"
            fi
        elif [[ -n "$response" ]]; then
            # 提取data字段内容作为yaml
            local yaml_content=$(echo "$response" | jq -r '.data // empty')
            if [[ -z "$yaml_content" || "$yaml_content" == "null" ]]; then
                log "WARN" "导出内容无data字段，内容: $response"
                echo "$response" > "${BACKUP_PATH}/${app_id}_error_${retry_count}.json"
            elif echo "$yaml_content" | grep -q '^app:'; then
                local safe_name=$(echo "$app_name" | sed 's/[^a-zA-Z0-9._-]/_/g')
                local export_file="${BACKUP_PATH}/${app_id}_${safe_name}.yaml"
                echo "$yaml_content" > "$export_file"
                log "INFO" "应用导出成功: $export_file"
                echo "$export_file"
                return 0
            else
                log "WARN" "data字段内容格式不正确 (尝试 $((retry_count + 1))/$max_retries)"
                log "DEBUG" "data内容: ${yaml_content:0:200}..."
                echo "$response" > "${BACKUP_PATH}/${app_id}_error_${retry_count}.json"
            fi
        else
            log "WARN" "收到空响应 (尝试 $((retry_count + 1))/$max_retries)"
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            sleep 2
        fi
    done
    
    log "ERROR" "应用导出失败: $app_name (ID: $app_id) - 已重试 $max_retries 次"
    return 1
}

# 导入单个应用，支持目标端自动refresh token
import_app() {
    local yaml_file="$1"
    local url="$2"
    local token="$3"
    
    if [[ ! -f "$yaml_file" ]]; then
        log "ERROR" "YAML文件不存在: $yaml_file"
        return 1
    fi
    
    # 校验YAML文件第一行是否为app:
    local first_line=$(head -n 1 "$yaml_file" | tr -d '\r\n')
    if [[ "$first_line" != "app:" ]]; then
        log "ERROR" "YAML文件格式错误: $yaml_file 第一行不是 'app:'，请检查导出逻辑或手动修正。"
        return 1
    fi
    
    local app_name=$(basename "$yaml_file" .yaml)
    log "INFO" "导入应用: $app_name"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "INFO" "[干运行] 跳过实际导入: $yaml_file"
        return 0
    fi
    
    # 读取YAML内容并转义，兼容macOS
    local yaml_content=$(awk '{printf "%s\\n", $0}' "$yaml_file" | sed 's/"/\\"/g')
    
    # 重试机制
    local max_retries="${MAX_RETRIES:-3}"
    local retry_count=0
    local retried_refresh=false
    
    while [[ $retry_count -lt $max_retries ]]; do
        # 使用临时文件保存响应
        local temp_response=$(mktemp)
        local temp_headers=$(mktemp)
        
        # 执行curl请求并保存状态码
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
        
        # 清理临时文件
        rm -f "$temp_response" "$temp_headers"
        
        # 401自动刷新token并重试一次
        if [[ "$http_code" == "401" && "$retried_refresh" == "false" && -n "${TARGET_REFRESH_TOKEN:-}" ]]; then
            log "WARN" "检测到目标Token过期，自动刷新后重试..."
            if refresh_target_token; then
                token="$TARGET_BEARER_TOKEN"
                retried_refresh=true
                continue
            else
                log "ERROR" "自动刷新目标token失败，无法继续"
                return 1
            fi
        fi
        
        if [[ $curl_exit_code -ne 0 ]]; then
            log "WARN" "CURL请求失败 (尝试 $((retry_count + 1))/$max_retries)，退出码: $curl_exit_code"
        elif [[ "$http_code" != "200" ]]; then
            log "WARN" "HTTP请求失败 (尝试 $((retry_count + 1))/$max_retries)，状态码: $http_code"
            case $http_code in
                401)
                    log "ERROR" "认证失败: Bearer Token可能无效或已过期"
                    ;;
                403)
                    log "ERROR" "权限不足: 当前Token没有导入应用的权限"
                    ;;
                400)
                    log "ERROR" "请求格式错误: 应用DSL格式可能有问题"
                    ;;
            esac
            if [[ -n "$response" ]]; then
                log "DEBUG" "错误响应: $response"
                echo "$response" > "${BACKUP_PATH}/import_error_${app_name}_${retry_count}.json"
            fi
        else
            # 检查响应是否包含错误
            if echo "$response" | jq -e '.code // empty' >/dev/null 2>&1; then
                local error_code=$(echo "$response" | jq -r '.code // empty')
                local error_message=$(echo "$response" | jq -r '.message // empty')
                
                if [[ "$error_code" != "null" && "$error_code" != "" ]]; then
                    log "WARN" "导入失败 (尝试 $((retry_count + 1))/$max_retries) - 错误代码: $error_code"
                    log "WARN" "错误信息: $error_message"
                    echo "$response" > "${BACKUP_PATH}/import_error_${app_name}_${retry_count}.json"
                else
                    log "INFO" "应用导入成功: $app_name"
                    echo "$response" > "${BACKUP_PATH}/import_success_${app_name}.json"
                    return 0
                fi
            else
                log "INFO" "应用导入成功: $app_name"
                echo "$response" > "${BACKUP_PATH}/import_success_${app_name}.json"
                return 0
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            sleep 3
        fi
    done
    
    log "ERROR" "应用导入失败: $app_name - 已重试 $max_retries 次"
    return 1
}

# 显示帮助信息
show_help() {
    cat << EOF
Dify 应用迁移脚本

用法: $0 [选项] [环境文件]

选项:
    -h, --help          显示帮助信息
    -c, --config        指定环境配置文件 (默认: .env)
    -a, --apps          指定要迁移的应用ID，用逗号分隔 (覆盖环境变量)
    -d, --dry-run       干运行模式，仅测试不实际执行
    -v, --verbose       详细输出 (DEBUG模式)
    --export-only       仅导出，不导入
    --import-only       仅导入指定目录中的YAML文件

示例:
    $0                                  # 使用默认.env文件进行完整迁移
    $0 -c production.env               # 使用指定配置文件
    $0 -a "app-id-1,app-id-2"         # 仅迁移指定应用
    $0 -d                              # 干运行模式
    $0 --export-only                   # 仅导出应用
    $0 --import-only ./exported_apps   # 仅导入指定目录中的应用

环境配置:
    请参考 .env.example 文件创建 .env 配置文件
EOF
}

# 主函数
main() {
    local config_file=".env"
    local export_only=false
    local import_only=false
    local import_dir=""
    local specified_apps=""
    
    # 解析命令行参数
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
                    log "ERROR" "未知参数: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # 检查依赖
    for cmd in curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR" "缺少必需的命令: $cmd"
            exit 1
        fi
    done
    
    # 加载环境变量
    load_env "$config_file"
    
    # 创建备份目录
    create_backup_dir
    
    # 设置应用ID列表
    local app_ids_to_migrate="${specified_apps:-${APP_IDS_TO_MIGRATE:-}}"
    
    if [[ "$import_only" == "true" ]]; then
        log "INFO" "开始导入模式，从目录: $import_dir"
        
        if [[ ! -d "$import_dir" ]]; then
            log "ERROR" "导入目录不存在: $import_dir"
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
        
        log "INFO" "导入完成: $success_count/$total_count 个应用成功导入"
        exit 0
    fi
    
    # 获取应用列表
    log "INFO" "开始获取源环境应用列表..."
    local apps_list
    
    if [[ -n "$app_ids_to_migrate" ]]; then
        log "INFO" "使用指定的应用ID列表: $app_ids_to_migrate"
        # 将逗号分隔的ID转换为列表格式
        apps_list=$(echo "$app_ids_to_migrate" | tr ',' '\n' | while read -r app_id; do
            echo "${app_id},指定应用_${app_id}"
        done)
    else
        apps_list=$(get_all_apps "$SOURCE_DIFY_URL" "$SOURCE_BEARER_TOKEN")
        if [[ $? -ne 0 ]] || [[ -z "$apps_list" ]]; then
            log "ERROR" "获取应用列表失败"
            exit 1
        fi
    fi
    
    local total_apps=$(echo "$apps_list" | wc -l)
    log "INFO" "找到 $total_apps 个应用需要处理"
    
    # 导出应用
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
        log "INFO" "导出模式完成，导出的文件保存在: $BACKUP_PATH"
        exit 0
    fi
    
    # 导入应用
    if [[ -f "${BACKUP_PATH}/exported_files.list" ]]; then
        log "INFO" "开始导入到目标环境..."
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
        
        log "INFO" "迁移完成！"
        log "INFO" "导出成功: $export_success_count 个应用"
        log "INFO" "导入成功: $import_success_count/$import_total 个应用"
        log "INFO" "备份目录: $BACKUP_PATH"
    else
        log "WARN" "没有成功导出的应用，跳过导入步骤"
    fi
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi