#!/bin/bash
# run_backup.sh - 备份模块入口v2
# 
# 描述: 执行系统备份任务
# 用法: ./run_backup.sh [options]
# 示例: ./run_backup.sh --full --compress

# ============================================================================
# 自动检测项目根目录（支持独立执行）
# ============================================================================
get_project_root() {
    # 如果已经设置，直接使用
    if [[ -n "${PROJECT_ROOT:-}" ]] && [[ -f "$PROJECT_ROOT/bin/bash_lib.sh" ]]; then
        echo "$PROJECT_ROOT"
        return 0
    fi
    
    # 通过脚本位置查找
    local script_path
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 如果在 scripts 目录，项目根目录是上级
    if [[ -f "$script_path/../bin/bash_lib.sh" ]]; then
        echo "$(cd "$script_path/.." && pwd)"
        return 0
    fi
    
    # 向上查找
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

PROJECT_ROOT="$(get_project_root)"

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "错误: 无法找到项目根目录" >&2
    exit 1
fi

# 加载核心库
source "$PROJECT_ROOT/bin/bash_lib.sh"

# ============================================================================
# 脚本配置
# ============================================================================
MODULE_NAME="backup"
SCRIPT_NAME="$(basename "$0")"

# 解析命令行参数
BACKUP_TYPE="incremental"  # full, incremental
COMPRESS=false
BACKUP_DEST="${BACKUP_DEST:-$PROJECT_ROOT/backups}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            BACKUP_TYPE="full"
            shift
            ;;
        --compress|-z)
            COMPRESS=true
            shift
            ;;
        --dest|-d)
            BACKUP_DEST="$2"
            shift 2
            ;;
        --help|-h)
            cat << EOF
备份脚本 - 执行系统备份

用法: $0 [options]

选项:
    --full          执行完整备份（默认: 增量）
    --compress, -z  压缩备份文件
    --dest, -d DIR  指定备份目录
    --help, -h      显示此帮助

示例:
    $0 --full --compress
    $0 --dest /mnt/backup
EOF
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# 初始化环境
# ============================================================================
init_environment "$MODULE_NAME"

log_info "========== 备份任务开始 =========="
log_info "备份类型: $BACKUP_TYPE"
log_info "压缩: $COMPRESS"
log_info "目标目录: $BACKUP_DEST"

# ============================================================================
# 模块加载
# ============================================================================
# 注册并加载需要的模块
register_module "database" "$PROJECT_ROOT/modules/database"
register_module "backup" "$PROJECT_ROOT/modules/backup"
load_modules

# 注册清理钩子
register_module_cleanup "database"
register_module_cleanup "backup"

# ============================================================================
# 业务逻辑
# ============================================================================
main() {
    # 创建临时工作目录
    local work_dir=$(create_module_temp_dir)
    log_info "工作目录: $work_dir"
    
    # 创建备份目录
    mkdir -p "$BACKUP_DEST"
    
    # 步骤1: 准备数据库
    log_info "步骤1: 准备数据库"
    database_main || {
        log_error "数据库准备失败"
        exit 1
    }
    
    # 步骤2: 执行数据库备份
    log_info "步骤2: 备份数据库"
    local backup_file
    if [[ "$BACKUP_TYPE" == "full" ]]; then
        backup_file=$(db_backup "full_backup_$(date +%Y%m%d)")
    else
        backup_file=$(db_backup "inc_backup_$(date +%Y%m%d_%H%M%S)")
    fi
    
    if [[ -z "$backup_file" ]]; then
        log_error "数据库备份失败"
        exit 1
    fi
    
    log_success "数据库备份完成: $backup_file"
    
    # 步骤3: 压缩备份（如果需要）
    if [[ "$COMPRESS" == "true" ]]; then
        log_info "步骤3: 压缩备份文件"
        local compressed_file="$BACKUP_DEST/backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        
        run_cmd tar -czf "$compressed_file" -C "$(dirname "$backup_file")" "$(basename "$backup_file")"
        
        log_success "压缩完成: $compressed_file"
        BACKUP_RESULT="$compressed_file"
    else
        cp "$backup_file" "$BACKUP_DEST/"
        BACKUP_RESULT="$BACKUP_DEST/$(basename "$backup_file")"
    fi
    
    # 步骤4: 清理旧备份
    log_info "步骤4: 清理旧备份（保留7天）"
    find "$BACKUP_DEST" -name "*.tar.gz" -mtime +7 -delete 2>/dev/null || true
    find "$BACKUP_DEST" -name "*.sql" -mtime +7 -delete 2>/dev/null || true
    
    # 完成
    log_success "备份任务完成"
    echo ""
    echo "========== 备份摘要 =========="
    echo "备份文件: $BACKUP_RESULT"
    echo "文件大小: $(du -h "$BACKUP_RESULT" | cut -f1)"
    echo "日志文件: $LOG_FILE"
    echo "=============================="
}

# 执行主函数
main
