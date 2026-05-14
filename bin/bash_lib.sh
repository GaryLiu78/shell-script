#!/bin/bash
# ============================================================================
# bash_lib.sh - 核心基础设施库
# 版本: 2.0.0
# 描述: 提供日志、模块管理、清理钩子等核心功能
# ============================================================================

# 防止重复加载
if [[ -n "${_BASH_LIB_LOADED:-}" ]]; then
    return 0
fi
readonly _BASH_LIB_LOADED="true"

# ============================================================================
# 1. 基础路径检测
# ============================================================================

# 获取项目根目录
get_project_root() {
    # 方法1: 环境变量
    if [[ -n "${PROJECT_ROOT:-}" ]] && [[ -f "$PROJECT_ROOT/bin/bash_lib.sh" ]]; then
        echo "$PROJECT_ROOT"
        return 0
    fi
    
    # 方法2: 通过库文件位置
    local script_path
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [[ -f "$script_path/../bin/bash_lib.sh" ]]; then
        echo "$(cd "$script_path/.." && pwd)"
        return 0
    fi
    
    # 方法3: 向上查找
    local current="$script_path"
    while [[ "$current" != "/" ]]; do
        if [[ -f "$current/bin/bash_lib.sh" ]]; then
            echo "$current"
            return 0
        fi
        current="$(dirname "$current")"
    done
    
    echo ""
    return 1
}

# 设置只读项目根目录
readonly PROJECT_ROOT="${PROJECT_ROOT:-$(get_project_root)}"
if [[ -z "$PROJECT_ROOT" ]]; then
    echo "错误: 无法确定项目根目录" >&2
    exit 1
fi

# ============================================================================
# 2. 目录配置
# ============================================================================

readonly LOG_BASE_DIR="${LOG_BASE_DIR:-$PROJECT_ROOT/logs}"
readonly TEMP_BASE_DIR="${TEMP_BASE_DIR:-$PROJECT_ROOT/temp}"
readonly CONFIG_DIR="${CONFIG_DIR:-$PROJECT_ROOT/config}"
readonly MODULES_DIR="${MODULES_DIR:-$PROJECT_ROOT/modules}"
readonly SCRIPTS_DIR="${SCRIPTS_DIR:-$PROJECT_ROOT/scripts}"
readonly BACKUPS_DIR="${BACKUPS_DIR:-$PROJECT_ROOT/backups}"

# 模块相关变量
MODULE_NAME="${MODULE_NAME:-unknown}"
SCRIPT_NAME="${SCRIPT_NAME:-$(basename "${BASH_SOURCE[1]:-$0}")}"

# 全局标志
_BASH_LIB_INITIALIZED=false
_LOG_INITIALIZED=false
_TRAPS_SET=false

# ============================================================================
# 3. 日志函数
# ============================================================================

# 日志级别
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

LOG_LEVEL="${LOG_LEVEL:-INFO}"

get_log_level_num() {
    case "${1:-INFO}" in
        DEBUG) echo $LOG_LEVEL_DEBUG ;;
        INFO)  echo $LOG_LEVEL_INFO ;;
        WARN)  echo $LOG_LEVEL_WARN ;;
        ERROR) echo $LOG_LEVEL_ERROR ;;
        *)     echo $LOG_LEVEL_INFO ;;
    esac
}

should_log() {
    local current=$(get_log_level_num "$LOG_LEVEL")
    local required=$(get_log_level_num "$1")
    [[ $required -ge $current ]]
}

format_log_message() {
    local level="$1"
    local message="$2"
    local module_prefix=""
    
    if [[ -n "$MODULE_NAME" && "$MODULE_NAME" != "unknown" ]]; then
        module_prefix="[$MODULE_NAME] "
    fi
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] ${module_prefix}$message"
}

log_debug() {
    if should_log "DEBUG"; then
        echo "$(format_log_message "DEBUG" "$1")"
    fi
}

log_info() {
    if should_log "INFO"; then
        echo "$(format_log_message "INFO" "$1")"
    fi
}

log_warn() {
    if should_log "WARN"; then
        echo "$(format_log_message "WARN" "$1")" >&2
    fi
}

log_error() {
    if should_log "ERROR"; then
        echo "$(format_log_message "ERROR" "$1")" >&2
    fi
}

log_success() {
    echo "$(format_log_message "SUCCESS" "$1")"
}

# ============================================================================
# 4. 日志系统初始化
# ============================================================================

init_logging() {
    if [[ "$_LOG_INITIALIZED" == "true" ]]; then
        return 0
    fi
    
    local module_name="${MODULE_NAME:-shared}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # 创建目录
    mkdir -p "$LOG_BASE_DIR/$module_name" "$TEMP_BASE_DIR/$module_name" "$CONFIG_DIR" "$BACKUPS_DIR"
    
    # 日志文件路径
    readonly LOG_FILE="$LOG_BASE_DIR/$module_name/${SCRIPT_NAME}_${timestamp}.log"
    
    # 保存原始描述符
    exec 3>&1 4>&2
    
    # 设置重定向
    if [[ "${DISABLE_LOGGING:-false}" != "true" ]]; then
        exec 1> >(tee -a "$LOG_FILE")
        exec 2>&1
    fi
    
    _LOG_INITIALIZED=true
    
    echo "============================================================================"
    echo "日志系统初始化"
    echo "脚本: $SCRIPT_NAME | 模块: $module_name | 日志级别: $LOG_LEVEL"
    echo "日志文件: $LOG_FILE"
    echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================================"
}

# ============================================================================
# 5. 模块注册系统
# ============================================================================

declare -A MODULES
declare -a MODULE_LOAD_ORDER

register_module() {
    local module_name="$1"
    local module_path="$2"
    
    if [[ -z "$module_name" ]] || [[ -z "$module_path" ]]; then
        log_error "register_module 需要模块名和路径"
        return 1
    fi
    
    if [[ ! -d "$module_path" ]]; then
        log_error "模块路径不存在: $module_path"
        return 1
    fi
    
    MODULES["$module_name"]="$module_path"
    MODULE_LOAD_ORDER+=("$module_name")
    log_debug "注册模块: $module_name"
    return 0
}

load_module() {
    local module_name="$1"
    local module_path="${MODULES[$module_name]}"
    local main_file="$module_path/main.sh"
    
    if [[ ! -f "$main_file" ]]; then
        log_error "模块文件不存在: $main_file"
        return 1
    fi
    
    local saved_module="$MODULE_NAME"
    MODULE_NAME="$module_name"
    
    # shellcheck source=/dev/null
    if source "$main_file"; then
        log_debug "已加载模块: $module_name"
        MODULE_NAME="$saved_module"
        return 0
    else
        log_error "加载模块失败: $module_name"
        MODULE_NAME="$saved_module"
        return 1
    fi
}

load_modules() {
    log_info "加载 ${#MODULE_LOAD_ORDER[@]} 个模块"
    local failed=()
    
    for module_name in "${MODULE_LOAD_ORDER[@]}"; do
        if ! load_module "$module_name"; then
            failed+=("$module_name")
        fi
    done
    
    if [[ ${#failed[@]} -gt 0 ]]; then
        log_error "模块加载失败: ${failed[*]}"
        return 1
    fi
    
    log_info "模块加载完成"
    return 0
}

# ============================================================================
# 6. 辅助函数
# ============================================================================

create_module_temp_dir() {
    local module_name="${1:-$MODULE_NAME}"
    local subdir="${2:-$$}"
    local temp_dir="$TEMP_BASE_DIR/$module_name/$subdir"
    mkdir -p "$temp_dir"
    echo "$temp_dir"
}

get_module_log_dir() {
    echo "$LOG_BASE_DIR/${1:-$MODULE_NAME}"
}

safe_rm_dir() {
    local dir="$1"
    
    if [[ -z "$dir" ]]; then
        log_error "拒绝删除：路径为空"
        return 1
    fi
    
    if [[ "$dir" == "/" ]] || [[ "$dir" == "/root" ]] || [[ "$dir" == "/etc" ]]; then
        log_error "拒绝删除：系统关键目录 ($dir)"
        return 1
    fi
    
    if [[ "$dir" == "$PROJECT_ROOT" ]]; then
        log_error "拒绝删除：项目根目录"
        return 1
    fi
    
    if [[ ${#dir} -lt 3 ]]; then
        log_error "拒绝删除：路径过短 ($dir)"
        return 1
    fi
    
    if [[ -d "$dir" ]]; then
        rm -rf "$dir" && log_debug "已删除目录: $dir"
    fi
}

run_cmd() {
    log_debug "执行: $*"
    if "$@"; then
        log_debug "成功: $1"
        return 0
    else
        local exit_code=$?
        log_error "失败: $1 (退出码: $exit_code)"
        return $exit_code
    fi
}

check_dependencies() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
            log_error "缺少依赖: $cmd"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "缺少必要依赖: ${missing[*]}" 1
    fi
    
    log_info "依赖检查通过: $*"
}

die() {
    log_error "$1"
    exit "${2:-1}"
}

# ============================================================================
# 7. 清理系统
# ============================================================================

declare -a CLEANUP_HOOKS=()
declare -a CLEANUP_MODULES=()
declare -a CLEANUP_DIRS=()

register_cleanup() { CLEANUP_HOOKS+=("$1"); log_debug "注册清理钩子: $1"; }
register_module_cleanup() { CLEANUP_MODULES+=("$1"); log_debug "注册模块清理: $1"; }
register_cleanup_dir() { CLEANUP_DIRS+=("$1"); log_debug "注册清理目录: $1"; }

cleanup() {
    local exit_code=$?
    
    if [[ "${_CLEANUP_DONE:-false}" == "true" ]]; then
        return 0
    fi
    _CLEANUP_DONE=true
    
    if [[ "$_LOG_INITIALIZED" == "true" ]]; then
        echo "----------------------------------------------------------------------------"
        log_info "开始清理资源..."
    fi
    
    # 模块清理
    for ((i=${#CLEANUP_MODULES[@]}-1; i>=0; i--)); do
        local func="cleanup_${CLEANUP_MODULES[i]}"
        declare -f "$func" >/dev/null && $func 2>/dev/null || true
    done
    
    # 清理钩子
    for ((i=${#CLEANUP_HOOKS[@]}-1; i>=0; i--)); do
        declare -f "${CLEANUP_HOOKS[i]}" >/dev/null && "${CLEANUP_HOOKS[i]}" 2>/dev/null || true
    done
    
    # 清理目录
    for dir in "${CLEANUP_DIRS[@]}"; do
        safe_rm_dir "$dir" 2>/dev/null || true
    done
    
    # 模块临时目录
    if [[ -n "$MODULE_NAME" && "$MODULE_NAME" != "unknown" ]]; then
        safe_rm_dir "$TEMP_BASE_DIR/$MODULE_NAME" 2>/dev/null || true
    fi
    
    if [[ "$_LOG_INITIALIZED" == "true" ]]; then
        if [ $exit_code -eq 0 ]; then
            log_success "脚本正常完成"
        else
            log_error "脚本异常退出 (退出码: $exit_code)"
        fi
        echo "============================================================================"
    fi
    
    exec 1>&3 2>&4 3>&- 4>&- 2>/dev/null || true
    exit $exit_code
}

setup_traps() {
    if [[ "$_TRAPS_SET" == "true" ]]; then
        return 0
    fi
    trap cleanup EXIT INT TERM HUP
    _TRAPS_SET=true
    log_debug "已设置信号陷阱"
}

# ============================================================================
# 8. 配置加载
# ============================================================================

load_config() {
    local config_file="$CONFIG_DIR/${1}.conf"
    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file" 2>/dev/null && log_info "已加载配置: $1" || log_warn "配置加载失败: $1"
    else
        log_debug "配置文件不存在: $config_file"
    fi
}

# ============================================================================
# 9. 一键初始化
# ============================================================================

init_environment() {
    MODULE_NAME="${1:-${MODULE_NAME:-unknown}}"
    set -euo pipefail
    init_logging
    setup_traps
    load_config "global"
    load_config "modules"
    log_info "环境初始化完成: $MODULE_NAME"
}

quick_init() {
    MODULE_NAME="${1:-quick}"
    set -euo pipefail
    init_logging
    setup_traps
}

# ============================================================================
# 10. 库验证
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "bash_lib.sh v2.0.0 - 测试模式"
    echo "项目根目录: $PROJECT_ROOT"
    echo "库加载成功"
fi
