#!/bin/bash
# ============================================================================
# bash_lib.sh - 核心基础设施库
# ============================================================================

# 检测项目根目录
get_project_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(cd "$script_dir/.." && pwd)"
}

readonly PROJECT_ROOT="${PROJECT_ROOT:-$(get_project_root)}"

# 目录配置
readonly LOG_BASE_DIR="${LOG_BASE_DIR:-$PROJECT_ROOT/logs}"
readonly TEMP_BASE_DIR="${TEMP_BASE_DIR:-$PROJECT_ROOT/temp}"
readonly CONFIG_DIR="${CONFIG_DIR:-$PROJECT_ROOT/config}"
readonly MODULES_DIR="${MODULES_DIR:-$PROJECT_ROOT/modules}"

# 当前模块名称
MODULE_NAME="${MODULE_NAME:-unknown}"
SCRIPT_NAME="${SCRIPT_NAME:-$(basename "$0")}"

# ============================================================================
# 日志函数
# ============================================================================
log_info() {
    local module_prefix=""
    [[ -n "$MODULE_NAME" && "$MODULE_NAME" != "unknown" ]] && module_prefix="[$MODULE_NAME] "
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ${module_prefix}$1"
}

log_error() {
    local module_prefix=""
    [[ -n "$MODULE_NAME" && "$MODULE_NAME" != "unknown" ]] && module_prefix="[$MODULE_NAME] "
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] ${module_prefix}$1" >&2
}

log_warn() {
    local module_prefix=""
    [[ -n "$MODULE_NAME" && "$MODULE_NAME" != "unknown" ]] && module_prefix="[$MODULE_NAME] "
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] ${module_prefix}$1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        local module_prefix=""
        [[ -n "$MODULE_NAME" && "$MODULE_NAME" != "unknown" ]] && module_prefix="[$MODULE_NAME] "
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] ${module_prefix}$1"
    fi
}

log_success() {
    local module_prefix=""
    [[ -n "$MODULE_NAME" && "$MODULE_NAME" != "unknown" ]] && module_prefix="[$MODULE_NAME] "
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] ${module_prefix}$1"
}

# ============================================================================
# 日志系统初始化
# ============================================================================
init_logging() {
    local module_name="${MODULE_NAME:-shared}"
    
    mkdir -p "$LOG_BASE_DIR/shared"
    mkdir -p "$LOG_BASE_DIR/$module_name"
    mkdir -p "$TEMP_BASE_DIR/shared"
    mkdir -p "$TEMP_BASE_DIR/$module_name"
    
    local log_file="$LOG_BASE_DIR/$module_name/${SCRIPT_NAME}_$(date +%Y%m%d_%H%M%S).log"
    readonly LOG_FILE="$log_file"
    
    exec 1> >(tee -a "$LOG_FILE") 2>&1
    
    echo "============================================================================"
    echo "日志系统初始化"
    echo "脚本: $SCRIPT_NAME"
    echo "模块: $module_name"
    echo "日志: $LOG_FILE"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================================"
}

# ============================================================================
# 模块注册系统
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
    
    MODULES["$module_name"]="$module_path"
    MODULE_LOAD_ORDER+=("$module_name")
    
    log_info "注册模块: $module_name"
}

load_modules() {
    log_info "加载 ${#MODULE_LOAD_ORDER[@]} 个模块"
    
    for module_name in "${MODULE_LOAD_ORDER[@]}"; do
        local module_path="${MODULES[$module_name]}"
        local main_file="$module_path/main.sh"
        
        if [[ -f "$main_file" ]]; then
            # shellcheck source=/dev/null
            source "$main_file"
            log_info "✓ 已加载模块: $module_name"
        else
            log_warn "模块文件不存在: $main_file"
        fi
    done
}

# ============================================================================
# 辅助函数
# ============================================================================
get_module_log_dir() {
    echo "$LOG_BASE_DIR/${1:-$MODULE_NAME}"
}

get_module_temp_dir() {
    echo "$TEMP_BASE_DIR/${1:-$MODULE_NAME}"
}

create_module_temp_dir() {
    local module_name="${1:-$MODULE_NAME}"
    local temp_dir="$TEMP_BASE_DIR/$module_name/$$"
    mkdir -p "$temp_dir"
    echo "$temp_dir"
}

# ============================================================================
# 安全删除
# ============================================================================
safe_rm_dir() {
    local dir=$1
    
    if [[ -z "$dir" || "$dir" == "/" || "$dir" == "$PROJECT_ROOT" || ${#dir} -lt 3 ]]; then
        log_error "拒绝删除危险路径: $dir"
        return 1
    fi
    
    if [[ -d "$dir" ]]; then
        rm -rf "$dir"
        log_debug "已删除: $dir"
    fi
}

# ============================================================================
# 清理系统
# ============================================================================
declare -a CLEANUP_HOOKS=()
declare -a CLEANUP_MODULES=()

register_cleanup() {
    CLEANUP_HOOKS+=("$1")
    log_debug "注册清理钩子: $1"
}

register_module_cleanup() {
    CLEANUP_MODULES+=("$1")
    log_debug "注册模块清理: $1"
}

cleanup() {
    local exit_code=$?
    
    echo "----------------------------------------------------------------------------"
    log_info "开始清理..."
    
    # 执行模块清理
    for module_name in "${CLEANUP_MODULES[@]}"; do
        local cleanup_func="cleanup_${module_name}"
        if declare -f "$cleanup_func" > /dev/null; then
            log_debug "执行模块清理: $module_name"
            $cleanup_func
        fi
    done
    
    # 执行钩子
    for ((i=${#CLEANUP_HOOKS[@]}-1; i>=0; i--)); do
        if declare -f "${CLEANUP_HOOKS[i]}" > /dev/null; then
            log_debug "执行钩子: ${CLEANUP_HOOKS[i]}"
            "${CLEANUP_HOOKS[i]}"
        fi
    done
    
    if [ $exit_code -eq 0 ]; then
        log_success "脚本正常完成"
    else
        log_error "脚本异常退出 (退出码: $exit_code)"
    fi
    
    echo "============================================================================"
    exit $exit_code
}

setup_traps() {
    trap cleanup EXIT INT TERM
    log_debug "已设置信号陷阱"
}

# ============================================================================
# 一键初始化
# ============================================================================
init_environment() {
    MODULE_NAME="${1:-${MODULE_NAME:-unknown}}"
    SCRIPT_NAME="${SCRIPT_NAME:-$(basename "$0")}"
    
    set -euo pipefail
    init_logging
    setup_traps
    
    log_info "环境初始化完成: $MODULE_NAME"
}
