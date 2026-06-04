#!/bin/bash

CLEANUP_DIRS=()
CLEANUP_DIR_COUNT=0

register_cleanup_dir() {
    CLEANUP_DIRS+=("$1")
    CLEANUP_DIR_COUNT=$((CLEANUP_DIR_COUNT + 1))
}

safe_rm_dir() {
    local dir="${1:-}"

    if [[ -z "$dir" || "$dir" == "/" || "$dir" == "$PROJECT_ROOT" || ${#dir} -lt 3 ]]; then
        log_warn "Refusing to delete unsafe path: ${dir:-<empty>}"
        return 1
    fi

    [[ -d "$dir" ]] && rm -rf "$dir"
}

cleanup() {
    local exit_code=$?

    if [[ "${_CLEANUP_DONE:-false}" == "true" ]]; then
        return 0
    fi
    _CLEANUP_DONE=true

    if [[ "${_LOG_INITIALIZED:-false}" == "true" ]]; then
        echo "----------------------------------------------------------------------------"
        log_info "Cleaning up resources"
    fi

    local dir
    if (( CLEANUP_DIR_COUNT > 0 )); then
        for dir in "${CLEANUP_DIRS[@]}"; do
            safe_rm_dir "$dir" 2>/dev/null || true
        done
    fi

    if [[ "${_LOG_INITIALIZED:-false}" == "true" ]]; then
        if [[ "$exit_code" -eq 0 ]]; then
            log_success "Script completed normally"
        else
            log_error "Script failed (Exit Code: $exit_code)"
        fi
        echo "============================================================================"
    fi

    exec 1>&3 2>&4 3>&- 4>&- 2>/dev/null || true
    exit "$exit_code"
}

setup_traps() {
    trap cleanup EXIT INT TERM HUP
}
