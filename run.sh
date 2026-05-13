#!/bin/bash
# ============================================================================
# run.sh - 项目主启动器
# 
# 用法:
#   ./run.sh {command} [options]
#   ./run.sh --help
#   ./run.sh --list
#
# 示例:
#   ./run.sh backup
#   ./run.sh pipeline --debug
#   ./run.sh report --config custom.conf
# ============================================================================

set -euo pipefail

# 颜色定义（用于帮助信息）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# 自动检测项目根目录
# ============================================================================
get_project_root() {
    local script_path
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 方法1：通过脚本位置（run.sh在根目录）
    if [[ -f "$script_path/bin/bash_lib.sh" ]]; then
        echo "$script_path"
        return 0
    fi
    
    # 方法2：向上查找直到找到 bin/bash_lib.sh
    local current="$script_path"
    while [[ "$current" != "/" ]]; do
        if [[ -f "$current/bin/bash_lib.sh" ]]; then
            echo "$current"
            return 0
        fi
        current="$(dirname "$current")"
    done
    
    # 方法3：通过环境变量
    if [[ -n "${PROJECT_ROOT:-}" ]] && [[ -f "$PROJECT_ROOT/bin/bash_lib.sh" ]]; then
        echo "$PROJECT_ROOT"
        return 0
    fi
    
    # 都找不到，报错
    echo "错误: 无法找到项目根目录" >&2
    echo "请确保 run.sh 在项目根目录，或设置 PROJECT_ROOT 环境变量" >&2
    exit 1
}

PROJECT_ROOT="$(get_project_root)"
export PROJECT_ROOT

# 加载核心库
source "$PROJECT_ROOT/bin/bash_lib.sh"

# ============================================================================
# 配置
# ============================================================================
SCRIPT_NAME="run.sh"
VERSION="1.0.0"

# ============================================================================
# 帮助信息
# ============================================================================
show_help() {
    cat << EOF
${GREEN}项目启动器 v${VERSION}${NC}

${YELLOW}用法:${NC}
    ./run.sh ${BLUE}<command>${NC} [${GREEN}options${NC}]

${YELLOW}可用命令:${NC}
    ${BLUE}backup${NC}      - 运行备份模块
    ${BLUE}pipeline${NC}    - 运行完整数据流水线
    ${BLUE}report${NC}      - 生成报表
    ${BLUE}clean${NC}       - 清理日志和临时文件
    ${BLUE}status${NC}      - 查看项目状态
    ${BLUE}list${NC}        - 列出所有可用命令

${YELLOW}选项:${NC}
    ${GREEN}--debug${NC}     - 启用调试模式
    ${GREEN}--config FILE${NC} - 指定配置文件
    ${GREEN}--help${NC}      - 显示此帮助信息
    ${GREEN}--version${NC}   - 显示版本信息

${YELLOW}示例:${NC}
    ./run.sh backup
    ./run.sh pipeline --debug
    ./run.sh report --config production.conf
    DEBUG=true ./run.sh backup

${YELLOW}环境变量:${NC}
    DEBUG          - 启用调试输出 (true/false)
    LOG_LEVEL      - 日志级别 (DEBUG/INFO/WARN/ERROR)
    PROJECT_ROOT   - 覆盖项目根目录路径

${YELLOW}文档:${NC}
    更多信息请查看: docs/README.md
EOF
}

# ============================================================================
# 显示版本
# ============================================================================
show_version() {
    echo "项目启动器 v${VERSION}"
    echo "项目根目录: $PROJECT_ROOT"
}

# ============================================================================
# 列出所有命令
# ============================================================================
list_commands() {
    echo "${GREEN}可用命令:${NC}"
    echo ""
    
    # 扫描 scripts 目录
    if [[ -d "$PROJECT_ROOT/scripts" ]]; then
        for script in "$PROJECT_ROOT/scripts"/run_*.sh; do
            if [[ -f "$script" ]]; then
                local name=$(basename "$script" .sh | sed 's/run_//')
                local desc=$(grep -m 1 "^#.*-" "$script" | sed 's/^#\s*//' || echo "无描述")
                printf "  ${BLUE}%-15s${NC} %s\n" "$name" "$desc"
            fi
        done
    fi
    
    echo ""
    echo "内置命令: clean, status, list, help"
}

# ============================================================================
# 清理项目
# ============================================================================
cmd_clean() {
    log_info "开始清理项目临时文件..."
    
    # 清理日志（保留最近3天）
    if [[ -d "$LOG_BASE_DIR" ]]; then
        log_info "清理旧日志文件（保留3天）..."
        find "$LOG_BASE_DIR" -name "*.log" -mtime +3 -delete 2>/dev/null || true
        log_success "日志清理完成"
    fi
    
    # 清理临时目录
    if [[ -d "$TEMP_BASE_DIR" ]]; then
        log_info "清理临时目录..."
        rm -rf "$TEMP_BASE_DIR"/*
        log_success "临时目录清理完成"
    fi
    
    # 清理备份（可选）
    if [[ "${CLEAN_BACKUPS:-false}" == "true" ]]; then
        if [[ -d "$PROJECT_ROOT/backups" ]]; then
            log_info "清理旧备份..."
            find "$PROJECT_ROOT/backups" -name "*.tar.gz" -mtime +30 -delete
        fi
    fi
    
    log_success "项目清理完成"
}

# ============================================================================
# 查看状态
# ============================================================================
cmd_status() {
    echo "${GREEN}项目状态${NC}"
    echo "==================="
    echo "项目根目录: $PROJECT_ROOT"
    echo "日志目录: $LOG_BASE_DIR"
    echo "临时目录: $TEMP_BASE_DIR"
    echo "配置目录: $CONFIG_DIR"
    echo ""
    
    # 磁盘使用
    echo "${YELLOW}磁盘使用:${NC}"
    df -h "$PROJECT_ROOT" | awk 'NR==2 {print "  使用: " $3 "/" $2 " (" $5 ")"}'
    echo ""
    
    # 日志统计
    if [[ -d "$LOG_BASE_DIR" ]]; then
        local log_count=$(find "$LOG_BASE_DIR" -name "*.log" -type f | wc -l)
        local log_size=$(du -sh "$LOG_BASE_DIR" 2>/dev/null | cut -f1)
        echo "${YELLOW}日志统计:${NC}"
        echo "  文件数: $log_count"
        echo "  总大小: $log_size"
        echo ""
    fi
    
    # 最近的活动
    if [[ -d "$LOG_BASE_DIR" ]]; then
        echo "${YELLOW}最近的活动:${NC}"
        find "$LOG_BASE_DIR" -name "*.log" -type f -printf '%T@ %p\n' 2>/dev/null | \
            sort -rn | head -3 | while read timestamp file; do
            local date=$(date -d "@${timestamp%.*}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
            echo "  $date: $(basename "$file")"
        done
    fi
}

# ============================================================================
# 运行脚本（通用）
# ============================================================================
run_script() {
    local script_name="$1"
    shift
    local script_path="$PROJECT_ROOT/scripts/run_${script_name}.sh"
    
    if [[ ! -f "$script_path" ]]; then
        log_error "脚本不存在: $script_name"
        echo ""
        echo "可用脚本:"
        list_commands
        exit 1
    fi
    
    log_info "执行脚本: $script_name"
    log_debug "脚本路径: $script_path"
    log_debug "参数: $*"
    
    # 设置环境变量
    export MODULE_NAME="$script_name"
    
    # 执行脚本
    if [[ "${DEBUG:-false}" == "true" ]]; then
        bash -x "$script_path" "$@"
    else
        bash "$script_path" "$@"
    fi
}

# ============================================================================
# 主逻辑
# ============================================================================
main() {
    # 解析参数
    local command=""
    local args=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                show_version
                exit 0
                ;;
            --debug|-d)
                export DEBUG=true
                shift
                ;;
            --config|-c)
                export CONFIG_FILE="$2"
                shift 2
                ;;
            --list|-l)
                list_commands
                exit 0
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$1"
                else
                    args+=("$1")
                fi
                shift
                ;;
        esac
    done
    
    # 如果没有命令，显示帮助
    if [[ -z "$command" ]]; then
        show_help
        exit 0
    fi
    
    # 初始化日志（使用主启动器模块）
    MODULE_NAME="main"
    init_environment "main"
    
    # 执行命令
    case "$command" in
        backup|pipeline|report)
            run_script "$command" "${args[@]}"
            ;;
        clean)
            cmd_clean
            ;;
        status)
            cmd_status
            ;;
        list|ls)
            list_commands
            ;;
        *)
            log_error "未知命令: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
