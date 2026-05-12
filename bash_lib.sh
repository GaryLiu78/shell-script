#!/bin/bash
# ============================================================================
# Bash infrastructure lib
# ============================================================================

# ============================================================================
# 1. Detect PROJECT_ROOT Path 
# ============================================================================
get_project_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(cd "$script_dir/.." && pwd)"
}

readonly PROJECT_ROOT="${PROJECT_ROOT:-$(get_project_root)}"

# ============================================================================
# 2. Set key path （Based on PROJECT_ROOT）
# ============================================================================
readonly LOG_BASE_DIR="${LOG_BASE_DIR:-$PROJECT_ROOT/logs}"
readonly TEMP_BASE_DIR="${TEMP_BASE_DIR:-$PROJECT_ROOT/temp}"
readonly CONFIG_DIR="${CONFIG_DIR:-$PROJECT_ROOT/config}"
readonly MODULES_DIR="${MODULES_DIR:-$PROJECT_ROOT/modules}"

# Current Module name
MODULE_NAME="${MODULE_NAME:-unknown}"
SCRIPT_NAME="${SCRIPT_NAME:-$(basename "$0")}"

# ============================================================================
# 3. Logging functions （Based on key path）
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

# ============================================================================
# 4. Initialize Logging features （Set log redirection）
# ============================================================================
init_logging() {
    local module_name="${MODULE_NAME:-shared}"
    
    # Create log/temp folders
    mkdir -p "$LOG_BASE_DIR/shared"
    mkdir -p "$LOG_BASE_DIR/$module_name"
    mkdir -p "$TEMP_BASE_DIR/shared"
    mkdir -p "$TEMP_BASE_DIR/$module_name"
    mkdir -p "$CONFIG_DIR/$module_name"
    
    # Generate log file per module/script
    local log_file="$LOG_BASE_DIR/$module_name/${SCRIPT_NAME}_$(date +%Y%m%d_%H%M%S).log"
    readonly LOG_FILE="$log_file"
    
    # Set log redirection
    exec 1> >(tee -a "$LOG_FILE") 2>&1
    
    echo "============================================================================"
    echo "Logging Initialized"
    echo "Script: $SCRIPT_NAME"
    echo "Module: $module_name"
    echo "Logfile: $LOG_FILE"
    echo "Starttime: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================================"
}

# ============================================================================
# 5. Module Registration System（Start to use logging function）
# ============================================================================
declare -A MODULES
declare -a MODULE_LOAD_ORDER

register_module() {
    local module_name="$1"
    local module_path="$2"
    
    if [[ -z "$module_name" ]] || [[ -z "$module_path" ]]; then
        log_error "register_module need module name and path"
        return 1
    fi
    
    MODULES["$module_name"]="$module_path"
    MODULE_LOAD_ORDER+=("$module_name")
    
    log_info "register_module: $module_name -> $module_path"
}

load_modules() {
    log_info "Start to load ${#MODULE_LOAD_ORDER[@]} modules ..."
    
    for module_name in "${MODULE_LOAD_ORDER[@]}"; do
        local module_path="${MODULES[$module_name]}"
        local main_file="$module_path/main.sh"
        
        if [[ -f "$main_file" ]]; then
            # shell check source=/dev/null
            source "$main_file"
            log_debug "loaded_module: $module_name"
        else
            log_warn "module file not exist: $main_file"
        fi
    done
    
    log_info "Module loaded"
}

# ============================================================================
# 6. Auxiliary functions （Use logging functions）
# ============================================================================
get_module_log_dir() {
    local module_name="${1:-$MODULE_NAME}"
    echo "$LOG_BASE_DIR/$module_name"
}

get_module_temp_dir() {
    local module_name="${1:-$MODULE_NAME}"
    echo "$TEMP_BASE_DIR/$module_name"
}

create_module_temp_dir() {
    local module_name="${1:-$MODULE_NAME}"
    local temp_dir="$TEMP_BASE_DIR/$module_name/$$"
    mkdir -p "$temp_dir"
    echo "$temp_dir"
}

# ============================================================================
# 7. Security cleanup functions （Use logging functions）
# ============================================================================
safe_rm_dir() {
    local dir=$1
    
    if [[ -z "$dir" || "$dir" == "/" || "$dir" == "$PROJECT_ROOT" || ${#dir} -lt 3 ]]; then
        log_error "Refuse to delete risky folders: $dir"
        return 1
    fi
    
    if [[ -d "$dir" ]]; then
        rm -rf "$dir"
        log_debug "Deleted folders: $dir"
    fi
}

# ============================================================================
# 8. Clean up system （Use logging and auxiliary functions）
# ============================================================================
declare -a CLEANUP_HOOKS=()
declare -a CLEANUP_MODULES=()

register_cleanup() {
    CLEANUP_HOOKS+=("$1")
    log_debug "Register hock: $1"
}

register_module_cleanup() {
    local module_name="$1"
    CLEANUP_MODULES+=("$module_name")
    log_debug "Clean up registered modules: $module_name"
}

cleanup() {
    local exit_code=$?
    
    echo "----------------------------------------------------------------------------"
    log_info "Start global cleanup..."
    
    # Execute module cleanup
    for module_name in "${CLEANUP_MODULES[@]}"; do
        local cleanup_func="cleanup_${module_name}"
        if declare -f "$cleanup_func" > /dev/null; then
            log_debug "Execute module cleanup: $module_name"
            $cleanup_func
        fi
    done
    
    # Hooks for module registration
    for ((i=${#CLEANUP_HOOKS[@]}-1; i>=0; i--)); do
        if declare -f "${CLEANUP_HOOKS[i]}" > /dev/null; then
            log_debug "Execute hooks cleanup: ${CLEANUP_HOOKS[i]}"
            "${CLEANUP_HOOKS[i]}"
        fi
    done
    
    if [ $exit_code -eq 0 ]; then
        log_info "Script Completed normally"
    else
        log_error "Script exit abnormal (Exit Code: $exit_code)"
    fi
    
    echo "============================================================================"
    echo "End time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================================"
    
    exit $exit_code
}

# ============================================================================
# 9. Set trap （Use cleanup function）
# ============================================================================
setup_traps() {
    trap cleanup EXIT INT TERM
    log_debug "Signal trap set"
}

# ============================================================================
# 10. one-click initilization （overall）
# ============================================================================
init_module_environment() {
    MODULE_NAME="${1:-${MODULE_NAME:-unknown}}"
    SCRIPT_NAME="${SCRIPT_NAME:-$(basename "$0")}"
    
    set -euo pipefail
    init_logging          # Initilize log initilization
    setup_traps           # Set cleanup trap
    
    log_info "Module env initilization completed: $MODULE_NAME"
    log_debug "PROJECT_ROOT: $PROJECT_ROOT"
}
