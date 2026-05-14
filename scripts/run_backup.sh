#!/bin/bash
# scripts/run_backup.sh - Oracle备份模块入口

# 检查调用方式
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "请通过 run.sh 调用: ./run.sh backup" >&2
    exit 1
fi

# 初始化
init_environment "backup"

# 加载通用函数
source "$SCRIPTS_DIR/common.sh"

# 解析参数
BACKUP_TYPE="full"  # full, schema, table
COMPRESS=false
SCHEMA_NAME=""
TABLE_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --schema) SCHEMA_NAME="$2"; BACKUP_TYPE="schema"; shift 2 ;;
        --table) TABLE_NAME="$2"; BACKUP_TYPE="table"; shift 2 ;;
        --compress) COMPRESS=true; shift ;;
        --full) BACKUP_TYPE="full"; shift ;;
        *) shift ;;
    esac
done

# 注册模块
register_module "database" "$MODULES_DIR/database"
register_module "backup" "$MODULES_DIR/backup"
load_modules || exit 1

# 注册清理
register_module_cleanup "database"
register_module_cleanup "backup"

# 主逻辑
main() {
    log_info "Oracle备份任务开始 (类型: $BACKUP_TYPE)"
    
    # 检查Oracle依赖
    check_dependencies "sqlplus" "expdp" "exp" "gzip"
    
    local work_dir=$(create_module_temp_dir)
    log_info "工作目录: $work_dir"
    
    # 根据备份类型执行不同的备份策略
    local backup_file=""
    case "$BACKUP_TYPE" in
        full)
            log_info "执行全库备份..."
            backup_file=$(oracle_full_backup "$work_dir")
            ;;
        schema)
            if [[ -z "$SCHEMA_NAME" ]]; then
                die "请指定schema名称: --schema SCHEMA_NAME"
            fi
            log_info "备份Schema: $SCHEMA_NAME"
            backup_file=$(oracle_schema_backup "$SCHEMA_NAME" "$work_dir")
            ;;
        table)
            if [[ -z "$TABLE_NAME" ]]; then
                die "请指定表名: --table TABLE_NAME"
            fi
            log_info "备份表: $TABLE_NAME"
            backup_file=$(oracle_table_backup "$TABLE_NAME" "$work_dir")
            ;;
    esac
    
    # 验证备份文件
    validate_oracle_dump "$backup_file" || die "备份文件验证失败"
    
    # 压缩备份
    if [[ "$COMPRESS" == "true" ]]; then
        log_info "压缩备份文件..."
        local final_backup="$BACKUPS_DIR/oracle_${BACKUP_TYPE}_$(date +%Y%m%d_%H%M%S).tar.gz"
        run_cmd tar -czf "$final_backup" -C "$(dirname "$backup_file")" "$(basename "$backup_file")"
        final_backup_file="$final_backup"
    else
        cp "$backup_file" "$BACKUPS_DIR/"
        final_backup_file="$BACKUPS_DIR/$(basename "$backup_file")"
    fi
    
    # 清理旧备份（保留7天）
    find "$BACKUPS_DIR" -name "oracle_*.tar.gz" -mtime +7 -delete 2>/dev/null || true
    find "$BACKUPS_DIR" -name "*.dmp" -mtime +7 -delete 2>/dev/null || true
    
    log_success "Oracle备份完成: $final_backup_file"
    send_notification "Oracle备份完成" "类型: $BACKUP_TYPE\n文件: $final_backup_file"
}

main
