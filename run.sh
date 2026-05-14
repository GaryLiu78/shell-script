#!/bin/bash
# ============================================================================
# run.sh - 项目主启动器
# ============================================================================

set -euo pipefail

# 颜色定义
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

# 找到并加载库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/bin/bash_lib.sh" ]]; then
    source "$SCRIPT_DIR/bin/bash_lib.sh"
else
    echo "错误: 找不到 bin/bash_lib.sh" >&2
    exit 1
fi

VERSION="2.0.0"

show_help() {
    cat << EOF
${GREEN}项目启动器 v${VERSION}${NC}

${YELLOW}用法:${NC}
    ./run.sh ${BLUE}<command>${NC} [${GREEN}options${NC}]

${YELLOW}命令:${NC}
    ${BLUE}backup${NC}      - 运行Oracle备份
    ${BLUE}pipeline${NC}    - 运行数据流水线
    ${BLUE}report${NC}      - 生成报表
    ${BLUE}clean${NC}       - 清理临时文件
    ${BLUE}status${NC}      - 查看状态
    ${BLUE}list${NC}        - 列出命令

${YELLOW}选项:${NC}
    ${GREEN}--debug${NC}     - 调试模式
    ${GREEN}--help${NC}      - 帮助信息

${YELLOW}示例:${NC}
    ./run.sh backup
    DEBUG=true ./run.sh pipeline
EOF
}

cmd_clean() {
    init_environment "main"
    log_info "清理项目临时文件..."
    [[ -d "$LOG_BASE_DIR" ]] && find "$LOG_BASE_DIR" -name "*.log" -mtime +3 -delete
    [[ -d "$TEMP_BASE_DIR" ]] && rm -rf "$TEMP_BASE_DIR"/*
    log_success "清理完成"
}

cmd_status() {
    echo "${GREEN}项目状态${NC}"
    echo "项目根目录: $PROJECT_ROOT"
    echo "日志目录: $LOG_BASE_DIR ($(du -sh "$LOG_BASE_DIR" 2>/dev/null | cut -f1))"
    echo "临时目录: $TEMP_BASE_DIR"
    echo "备份目录: $BACKUPS_DIR"
}

cmd_list() {
    echo "${GREEN}可用命令:${NC}"
    for script in "$SCRIPTS_DIR"/run_*.sh; do
        [[ -f "$script" ]] && printf "  ${BLUE}%-12s${NC}\n" "$(basename "$script" .sh | sed 's/run_//')"
    done
    echo "  clean, status, list, help"
}

run_script() {
    local script_name="$1"
    shift
    local script_path="$SCRIPTS_DIR/run_${script_name}.sh"
    
    [[ -f "$script_path" ]] || { log_error "脚本不存在: $script_name"; cmd_list; exit 1; }
    
    export MODULE_NAME="$script_name"
    log_info "执行: $script_name"
    source "$script_path" "$@"
}

main() {
    local command="${1:-}"
    shift || true
    
    case "$command" in
        backup|pipeline|report) init_environment "main"; run_script "$command" "$@" ;;
        clean) cmd_clean ;;
        status) cmd_status ;;
        list|ls) cmd_list ;;
        --help|-h) show_help ;;
        *) [[ -z "$command" ]] && show_help || echo "未知命令: $command" ;;
    esac
}

main "$@"
